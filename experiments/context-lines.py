#!/usr/bin/env python3
"""Experiment: does reducing diff context lines hurt agent performance?

Creates a test repo with known changes, then asks Claude to perform tasks
that require understanding those changes - with varying context lines.

Measures: success rate, total tokens, follow-up file reads needed.

Usage: python3 experiments/context-lines.py
"""

import subprocess
import json
import os
import sys
import tempfile
import shutil

RUNS_PER_VARIANT = 3
VARIANTS = ["U0", "U1", "U3"]

# Check for claude CLI
if not shutil.which("claude"):
    print("error: claude CLI required")
    sys.exit(1)

# Create a test repo with a known codebase and known changes
def setup_test_repo(tmpdir):
    """Create a repo with a file, make a commit, then make changes."""
    subprocess.run(["git", "init"], cwd=tmpdir, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=tmpdir, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=tmpdir, capture_output=True)

    # Create a Python file with several functions
    code = '''"""User management module."""

import hashlib
import logging

logger = logging.getLogger(__name__)

class UserManager:
    def __init__(self, db):
        self.db = db
        self.cache = {}

    def get_user(self, user_id):
        """Fetch a user by ID."""
        if user_id in self.cache:
            return self.cache[user_id]
        user = self.db.query("SELECT * FROM users WHERE id = ?", user_id)
        if user:
            self.cache[user_id] = user
        return user

    def create_user(self, name, email):
        """Create a new user."""
        password_hash = hashlib.md5(email.encode()).hexdigest()
        user = self.db.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (?, ?, ?)",
            name, email, password_hash
        )
        logger.info(f"Created user {name}")
        return user

    def delete_user(self, user_id):
        """Delete a user by ID."""
        self.db.execute("DELETE FROM users WHERE id = ?", user_id)
        if user_id in self.cache:
            del self.cache[user_id]
        logger.info(f"Deleted user {user_id}")

    def update_email(self, user_id, new_email):
        """Update a user's email."""
        self.db.execute(
            "UPDATE users SET email = ? WHERE id = ?",
            new_email, user_id
        )
        if user_id in self.cache:
            self.cache[user_id]["email"] = new_email
        logger.info(f"Updated email for user {user_id}")

    def list_users(self, limit=100):
        """List all users."""
        return self.db.query("SELECT * FROM users LIMIT ?", limit)

    def search_users(self, query):
        """Search users by name."""
        return self.db.query(
            "SELECT * FROM users WHERE name LIKE ?",
            f"%{query}%"
        )
'''
    with open(os.path.join(tmpdir, "users.py"), "w") as f:
        f.write(code)

    subprocess.run(["git", "add", "."], cwd=tmpdir, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=tmpdir, capture_output=True)

    # Now make changes: fix the security issue (md5 -> sha256) and add validation
    new_code = code.replace(
        '        password_hash = hashlib.md5(email.encode()).hexdigest()',
        '        password_hash = hashlib.sha256(email.encode()).hexdigest()'
    ).replace(
        '    def update_email(self, user_id, new_email):\n        """Update a user\'s email."""\n        self.db.execute(',
        '    def update_email(self, user_id, new_email):\n        """Update a user\'s email."""\n        if not new_email or "@" not in new_email:\n            raise ValueError("Invalid email address")\n        self.db.execute('
    )
    with open(os.path.join(tmpdir, "users.py"), "w") as f:
        f.write(new_code)

    return tmpdir


def get_diff(tmpdir, context_lines):
    """Get the diff with specified context lines."""
    result = subprocess.run(
        ["git", "diff", f"-U{context_lines}"],
        cwd=tmpdir, capture_output=True, text=True
    )
    return result.stdout


def run_trial(tmpdir, diff_text, variant, trial_num):
    """Run a single trial: give Claude the diff and a task."""
    prompt = f"""Here is a git diff from a Python codebase:

```
{diff_text}
```

Based on this diff, answer these questions precisely:

1. What security vulnerability was fixed and how? (one sentence)
2. What validation was added and to which method? (one sentence)
3. What line number (approximately) is the email validation check on now?
4. If I wanted to add similar input validation to the create_user method (validate that email contains @), what line would I add it before? Quote the exact line of code that should come AFTER the validation check.

Reply with a JSON object with keys: security_fix, validation_added, validation_line, insert_before
"""

    result = subprocess.run(
        ["claude", "-p", prompt, "--output-format", "json"],
        capture_output=True, text=True, timeout=60
    )

    try:
        response = json.loads(result.stdout)
        return {
            "variant": variant,
            "trial": trial_num,
            "response": response.get("result", ""),
            "tokens_in": response.get("input_tokens", 0),
            "tokens_out": response.get("output_tokens", 0),
            "total_tokens": response.get("input_tokens", 0) + response.get("output_tokens", 0),
            "cost": response.get("cost_usd", 0),
            "duration_ms": response.get("duration_ms", 0),
            "raw": response,
        }
    except json.JSONDecodeError:
        return {
            "variant": variant,
            "trial": trial_num,
            "response": result.stdout[:500],
            "tokens_in": 0,
            "tokens_out": 0,
            "total_tokens": 0,
            "error": "parse_error",
        }


def grade_response(response_text):
    """Grade whether the response correctly understood the diff."""
    text = response_text.lower() if response_text else ""
    score = 0

    # Q1: security fix - md5 to sha256
    if "md5" in text and "sha256" in text:
        score += 1

    # Q2: validation added to update_email
    if "update_email" in text and ("validation" in text or "@" in text or "email" in text):
        score += 1

    # Q3: approximate line number (should be around line 40-42)
    # Just check they gave a number in a reasonable range
    import re
    numbers = re.findall(r'\b(\d+)\b', text)
    for n in numbers:
        if 35 <= int(n) <= 48:
            score += 1
            break

    # Q4: insert before the db.execute line in create_user
    if "password_hash" in text or "insert into" in text.lower() or "db.execute" in text:
        score += 1

    return score


def main():
    tmpdir = tempfile.mkdtemp(prefix="nit-experiment-")
    print(f"test repo: {tmpdir}")
    print(f"runs per variant: {RUNS_PER_VARIANT}")
    print()

    setup_test_repo(tmpdir)

    results = []

    for variant in VARIANTS:
        context = int(variant[1:])
        diff_text = get_diff(tmpdir, context)
        diff_tokens_approx = len(diff_text) // 4

        print(f"--- {variant} (diff: {len(diff_text)} chars, ~{diff_tokens_approx} tokens) ---")

        for trial in range(RUNS_PER_VARIANT):
            print(f"  trial {trial + 1}/{RUNS_PER_VARIANT}...", end=" ", flush=True)
            result = run_trial(tmpdir, diff_text, variant, trial)
            score = grade_response(result["response"])
            result["score"] = score
            result["max_score"] = 4
            results.append(result)
            print(f"score={score}/4, tokens={result['total_tokens']}")

    # Summary
    print()
    print("=" * 60)
    print("RESULTS")
    print("=" * 60)
    print()

    for variant in VARIANTS:
        variant_results = [r for r in results if r["variant"] == variant]
        scores = [r["score"] for r in variant_results]
        tokens = [r["total_tokens"] for r in variant_results]
        avg_score = sum(scores) / len(scores) if scores else 0
        avg_tokens = sum(tokens) / len(tokens) if tokens else 0

        context = int(variant[1:])
        diff_text = get_diff(tmpdir, context)

        print(f"  {variant}:")
        print(f"    diff size:  {len(diff_text)} chars (~{len(diff_text)//4} tokens)")
        print(f"    avg score:  {avg_score:.1f}/4")
        print(f"    avg tokens: {avg_tokens:.0f}")
        print(f"    scores:     {scores}")
        print()

    # Save raw results
    output_path = os.path.join(os.path.dirname(__file__), "context-lines-results.json")
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2, default=str)
    print(f"raw results saved to: {output_path}")

    # Cleanup
    shutil.rmtree(tmpdir)


if __name__ == "__main__":
    main()
