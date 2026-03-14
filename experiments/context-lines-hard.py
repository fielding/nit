#!/usr/bin/env python3
"""Comprehensive context-lines experiment.

Harder scenarios designed to stress-test whether reducing diff context
lines actually degrades agent understanding:

1. Multi-file: similar variable names across files, agent must identify
   which file/function a change belongs to
2. Nested control flow: change inside deeply nested if/for/try blocks,
   context needed to know which branch
3. Ambiguous changes: multiple similar code blocks, context needed to
   distinguish which one was modified
4. Move + modify: code was moved between functions and slightly changed,
   context helps understand the refactor
5. Config sprawl: changes scattered across a large config-like file,
   agent must understand the section structure

Usage: python3 experiments/context-lines-hard.py [--runs N]
"""

import subprocess
import json
import os
import sys
import tempfile
import shutil
import re
import argparse

VARIANTS = ["U0", "U1", "U3"]


def run_claude(prompt, timeout=90):
    """Run claude -p and return parsed response."""
    result = subprocess.run(
        ["claude", "-p", prompt, "--output-format", "json"],
        capture_output=True, text=True, timeout=timeout
    )
    try:
        data = json.loads(result.stdout)
        return {
            "response": data.get("result", ""),
            "input_tokens": data.get("input_tokens", 0),
            "output_tokens": data.get("output_tokens", 0),
            "cost": data.get("cost_usd", 0),
            "duration_ms": data.get("duration_ms", 0),
        }
    except (json.JSONDecodeError, KeyError):
        return {"response": result.stdout, "error": "parse_error"}


# ── Scenario 1: Multi-file with similar names ──────────────────────

def setup_multifile(tmpdir):
    """Two files with similar function/variable names."""
    os.makedirs(os.path.join(tmpdir, "src"), exist_ok=True)

    with open(os.path.join(tmpdir, "src", "orders.py"), "w") as f:
        f.write('''"""Order processing."""

def calculate_total(items, discount=0):
    subtotal = sum(item["price"] * item["qty"] for item in items)
    tax = subtotal * 0.08
    total = subtotal + tax - discount
    return round(total, 2)

def calculate_shipping(items, destination):
    weight = sum(item["weight"] * item["qty"] for item in items)
    if destination == "international":
        rate = 2.50
    else:
        rate = 1.25
    return round(weight * rate, 2)

def process_order(order):
    total = calculate_total(order["items"], order.get("discount", 0))
    shipping = calculate_shipping(order["items"], order["destination"])
    return {"total": total, "shipping": shipping, "grand_total": total + shipping}
''')

    with open(os.path.join(tmpdir, "src", "invoices.py"), "w") as f:
        f.write('''"""Invoice generation."""

def calculate_total(line_items, tax_rate=0.08):
    subtotal = sum(item["amount"] * item["quantity"] for item in line_items)
    tax = subtotal * tax_rate
    total = subtotal + tax
    return round(total, 2)

def calculate_shipping(line_items, method="standard"):
    weight = sum(item.get("weight", 0) * item["quantity"] for item in line_items)
    if method == "express":
        rate = 3.75
    elif method == "overnight":
        rate = 8.50
    else:
        rate = 1.25
    return round(weight * rate, 2)

def generate_invoice(customer, line_items, tax_rate=0.08):
    total = calculate_total(line_items, tax_rate)
    shipping = calculate_shipping(line_items)
    return {
        "customer": customer,
        "subtotal": total,
        "shipping": shipping,
        "amount_due": total + shipping
    }
''')

    subprocess.run(["git", "add", "."], cwd=tmpdir, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Add order and invoice modules"], cwd=tmpdir, capture_output=True)

    # Change: fix tax calculation in invoices.py (not orders.py)
    # and add express shipping surcharge in orders.py (not invoices.py)
    invoices = open(os.path.join(tmpdir, "src", "invoices.py")).read()
    invoices = invoices.replace(
        "    total = subtotal + tax\n    return round(total, 2)",
        "    total = subtotal + tax\n    discount = sum(item.get(\"discount\", 0) for item in line_items)\n    return round(total - discount, 2)"
    )
    with open(os.path.join(tmpdir, "src", "invoices.py"), "w") as f:
        f.write(invoices)

    orders = open(os.path.join(tmpdir, "src", "orders.py")).read()
    orders = orders.replace(
        '    if destination == "international":\n        rate = 2.50\n    else:\n        rate = 1.25',
        '    if destination == "international":\n        rate = 2.50\n    elif destination == "express":\n        rate = 4.00\n    else:\n        rate = 1.25'
    )
    with open(os.path.join(tmpdir, "src", "orders.py"), "w") as f:
        f.write(orders)


MULTIFILE_QUESTIONS = """Based on this diff, answer precisely:

1. Which file had the tax/discount calculation changed? (just the filename)
2. Which file had the shipping rates changed? (just the filename)
3. In the shipping change, what new destination type was added?
4. In the discount change, what is the default discount value per item if not specified?

Reply as JSON with keys: tax_file, shipping_file, new_destination, default_discount"""


def grade_multifile(response):
    text = response.lower() if response else ""
    score = 0
    if "invoices" in text and "tax" not in text.split("shipping_file")[0].split("invoices")[-1] if "shipping_file" in text else True:
        score += 1
    if "orders" in text:
        score += 1
    if "express" in text:
        score += 1
    if "0" in text:
        score += 1
    return score


# ── Scenario 2: Nested control flow ────────────────────────────────

def setup_nested(tmpdir):
    with open(os.path.join(tmpdir, "processor.py"), "w") as f:
        f.write('''"""Event processor with nested control flow."""

def process_events(events, config):
    results = []
    for event in events:
        if event["type"] == "click":
            if event.get("target"):
                if event["target"].startswith("btn-"):
                    if config.get("track_buttons"):
                        results.append({"action": "button_click", "id": event["target"]})
                    else:
                        results.append({"action": "click", "id": event["target"]})
                elif event["target"].startswith("link-"):
                    if config.get("track_navigation"):
                        results.append({"action": "nav_click", "url": event.get("href")})
                    else:
                        results.append({"action": "click", "url": event.get("href")})
                else:
                    results.append({"action": "click", "target": event["target"]})
        elif event["type"] == "scroll":
            if event.get("depth", 0) > 50:
                if config.get("track_deep_scroll"):
                    results.append({"action": "deep_scroll", "depth": event["depth"]})
                else:
                    results.append({"action": "scroll", "depth": event["depth"]})
            else:
                results.append({"action": "scroll", "depth": event.get("depth", 0)})
        elif event["type"] == "input":
            if event.get("field"):
                if event["field"] in config.get("sensitive_fields", []):
                    results.append({"action": "input", "field": event["field"], "redacted": True})
                else:
                    results.append({"action": "input", "field": event["field"], "value": event.get("value")})
    return results
''')

    subprocess.run(["git", "add", "."], cwd=tmpdir, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Add event processor"], cwd=tmpdir, capture_output=True)

    # Change: modify behavior inside the nested btn- + track_buttons=False branch
    code = open(os.path.join(tmpdir, "processor.py")).read()
    code = code.replace(
        '                    else:\n                        results.append({"action": "click", "id": event["target"]})',
        '                    else:\n                        results.append({"action": "untracked_click", "id": event["target"], "ignored": True})'
    )
    # Also change the deep_scroll tracking
    code = code.replace(
        '                    results.append({"action": "deep_scroll", "depth": event["depth"]})',
        '                    results.append({"action": "deep_scroll", "depth": event["depth"], "pct": round(event["depth"] / 100, 2)})'
    )
    with open(os.path.join(tmpdir, "processor.py"), "w") as f:
        f.write(code)


NESTED_QUESTIONS = """Based on this diff, answer precisely:

1. For button clicks: the change affects which tracking condition? (track_buttons=True or track_buttons=False/missing?)
2. What was the old action name for untracked button clicks, and what is it now?
3. For scroll events: what new field was added to deep_scroll tracking?
4. Does the deep_scroll change apply when track_deep_scroll is True or False?

Reply as JSON with keys: button_condition, old_action_new_action, scroll_new_field, scroll_condition"""


def grade_nested(response):
    text = response.lower() if response else ""
    score = 0
    # Q1: affects track_buttons=False/missing
    if "false" in text or "missing" in text or "not set" in text or "else" in text:
        score += 1
    # Q2: click -> untracked_click
    if "untracked_click" in text and "click" in text:
        score += 1
    # Q3: pct field
    if "pct" in text:
        score += 1
    # Q4: track_deep_scroll=True
    if "true" in text:
        score += 1
    return score


# ── Scenario 3: Ambiguous similar blocks ───────────────────────────

def setup_ambiguous(tmpdir):
    with open(os.path.join(tmpdir, "routes.py"), "w") as f:
        f.write('''"""API route handlers."""

def handle_get_users(request):
    limit = request.args.get("limit", 50)
    offset = request.args.get("offset", 0)
    users = db.query("SELECT * FROM users LIMIT ? OFFSET ?", limit, offset)
    return {"users": users, "count": len(users)}

def handle_get_posts(request):
    limit = request.args.get("limit", 50)
    offset = request.args.get("offset", 0)
    posts = db.query("SELECT * FROM posts LIMIT ? OFFSET ?", limit, offset)
    return {"posts": posts, "count": len(posts)}

def handle_get_comments(request):
    limit = request.args.get("limit", 50)
    offset = request.args.get("offset", 0)
    comments = db.query("SELECT * FROM comments LIMIT ? OFFSET ?", limit, offset)
    return {"comments": comments, "count": len(comments)}

def handle_get_tags(request):
    limit = request.args.get("limit", 50)
    offset = request.args.get("offset", 0)
    tags = db.query("SELECT * FROM tags LIMIT ? OFFSET ?", limit, offset)
    return {"tags": tags, "count": len(tags)}
''')

    subprocess.run(["git", "add", "."], cwd=tmpdir, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Add route handlers"], cwd=tmpdir, capture_output=True)

    # Change: only modify handle_get_posts to add sorting, and handle_get_comments to add filtering
    code = open(os.path.join(tmpdir, "routes.py")).read()
    code = code.replace(
        '    posts = db.query("SELECT * FROM posts LIMIT ? OFFSET ?", limit, offset)',
        '    sort = request.args.get("sort", "created_at")\n    posts = db.query(f"SELECT * FROM posts ORDER BY {sort} LIMIT ? OFFSET ?", limit, offset)'
    )
    code = code.replace(
        '    comments = db.query("SELECT * FROM comments LIMIT ? OFFSET ?", limit, offset)',
        '    post_id = request.args.get("post_id")\n    if post_id:\n        comments = db.query("SELECT * FROM comments WHERE post_id = ? LIMIT ? OFFSET ?", post_id, limit, offset)\n    else:\n        comments = db.query("SELECT * FROM comments LIMIT ? OFFSET ?", limit, offset)'
    )
    with open(os.path.join(tmpdir, "routes.py"), "w") as f:
        f.write(code)


AMBIGUOUS_QUESTIONS = """Based on this diff, answer precisely:

1. Which two handler functions were modified? (list both names)
2. Which handler got sorting added?
3. Which handler got filtering added?
4. The sorting defaults to which field? And the filtering is by which field?

Reply as JSON with keys: modified_handlers, sorting_handler, filtering_handler, sort_default_and_filter_field"""


def grade_ambiguous(response):
    text = response.lower() if response else ""
    score = 0
    if "posts" in text and "comments" in text:
        score += 1
    if "posts" in text and "sort" in text:
        score += 1
    if "comments" in text and "filter" in text:
        score += 1
    if "created_at" in text and "post_id" in text:
        score += 1
    return score


# ── Runner ─────────────────────────────────────────────────────────

SCENARIOS = [
    ("multifile", setup_multifile, MULTIFILE_QUESTIONS, grade_multifile),
    ("nested", setup_nested, NESTED_QUESTIONS, grade_nested),
    ("ambiguous", setup_ambiguous, AMBIGUOUS_QUESTIONS, grade_ambiguous),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=3, help="trials per variant per scenario")
    args = parser.parse_args()

    all_results = []

    for scenario_name, setup_fn, questions, grade_fn in SCENARIOS:
        print(f"\n{'='*60}")
        print(f"SCENARIO: {scenario_name}")
        print(f"{'='*60}")

        for variant in VARIANTS:
            context = int(variant[1:])

            # Fresh repo each time
            tmpdir = tempfile.mkdtemp(prefix=f"nit-{scenario_name}-")
            subprocess.run(["git", "init"], cwd=tmpdir, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=tmpdir, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=tmpdir, capture_output=True)

            setup_fn(tmpdir)
            diff = subprocess.run(["git", "diff", f"-U{context}"], cwd=tmpdir, capture_output=True, text=True).stdout

            print(f"\n  {variant} (diff: {len(diff)} chars, ~{len(diff)//4} tok)")

            for trial in range(args.runs):
                print(f"    trial {trial+1}/{args.runs}...", end=" ", flush=True)

                prompt = f"Here is a git diff:\n\n```\n{diff}\n```\n\n{questions}"
                result = run_claude(prompt)
                score = grade_fn(result.get("response", ""))

                entry = {
                    "scenario": scenario_name,
                    "variant": variant,
                    "trial": trial,
                    "diff_chars": len(diff),
                    "score": score,
                    "max_score": 4,
                    "response": result.get("response", "")[:500],
                    "input_tokens": result.get("input_tokens", 0),
                    "output_tokens": result.get("output_tokens", 0),
                    "cost": result.get("cost", 0),
                }
                all_results.append(entry)
                print(f"score={score}/4")

            shutil.rmtree(tmpdir)

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}\n")

    for scenario_name, _, _, _ in SCENARIOS:
        print(f"  {scenario_name}:")
        for variant in VARIANTS:
            entries = [r for r in all_results if r["scenario"] == scenario_name and r["variant"] == variant]
            scores = [r["score"] for r in entries]
            avg = sum(scores) / len(scores) if scores else 0
            diff_size = entries[0]["diff_chars"] if entries else 0
            print(f"    {variant}: avg {avg:.1f}/4  scores={scores}  diff={diff_size} chars")
        print()

    # Overall by variant
    print("  OVERALL:")
    for variant in VARIANTS:
        entries = [r for r in all_results if r["variant"] == variant]
        scores = [r["score"] for r in entries]
        avg = sum(scores) / len(scores) if scores else 0
        print(f"    {variant}: avg {avg:.2f}/4  ({sum(scores)}/{len(scores)*4} points)")

    # Save results
    output_path = os.path.join(os.path.dirname(__file__), "context-lines-hard-results.json")
    with open(output_path, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\n  results saved to: {output_path}")


if __name__ == "__main__":
    main()
