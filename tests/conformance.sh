#!/usr/bin/env bash
# conformance.sh - verify nit output matches git for equivalent commands
#
# Creates a test repo with known state, runs nit and git side by side,
# and diffs the output. Any difference is a bug.
#
# Usage: ./tests/conformance.sh [path-to-nit-binary]

set -euo pipefail

NIT="${1:-./zig-out/bin/nit}"
PASS=0
FAIL=0
ERRORS=""

if [ ! -x "$NIT" ]; then
  echo "error: nit binary not found at $NIT"
  echo "       run: zig build -Doptimize=ReleaseFast"
  exit 1
fi

# Resolve to absolute path
NIT="$(cd "$(dirname "$NIT")" && pwd)/$(basename "$NIT")"

TMPDIR=$(mktemp -d -t nit-conformance-XXXXXX)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test User"

# --- Build up a repo with various states ---

# Initial commit
cat > main.py << 'EOF'
"""Main application."""

import os
import sys

def main():
    print("hello world")
    return 0

def helper(x):
    """Helper function."""
    if x > 0:
        return x * 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

cat > utils.py << 'EOF'
"""Utility functions."""

def add(a, b):
    return a + b

def subtract(a, b):
    return a - b

def multiply(a, b):
    return a * b
EOF

git add main.py utils.py
git commit -q -m "Initial commit"

# Second commit - modify main.py
sed -i.bak 's/hello world/hello nit/' main.py && rm -f main.py.bak
git add main.py
git commit -q -m "Update greeting message"

# Third commit - add a file, modify utils
cat > config.json << 'EOF'
{
  "name": "test",
  "version": "1.0.0",
  "debug": false
}
EOF

cat >> utils.py << 'EOF'

def divide(a, b):
    if b == 0:
        raise ValueError("division by zero")
    return a / b
EOF

git add config.json utils.py
git commit -q -m "Add config and divide function"

# Fourth commit - delete a file
git rm -q config.json
git commit -q -m "Remove config file"

# Now make some unstaged changes for status/diff testing
sed -i.bak 's/hello nit/hello nit v2/' main.py && rm -f main.py.bak
echo "# new file" > newfile.txt

# Stage one change
echo "extra_setting = true" >> utils.py
git add utils.py

# --- Test functions ---

check() {
  local name="$1"
  local git_cmd="$2"
  local nit_cmd="$3"

  local git_out nit_out
  git_out=$(eval "$git_cmd" 2>&1) || true
  nit_out=$(eval "$nit_cmd" 2>&1) || true

  if [ "$git_out" = "$nit_out" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    ERRORS="${ERRORS}\n--- FAIL: $name ---\n"
    ERRORS="${ERRORS}git cmd: $git_cmd\n"
    ERRORS="${ERRORS}nit cmd: $nit_cmd\n"
    ERRORS="${ERRORS}git output:\n$git_out\n"
    ERRORS="${ERRORS}nit output:\n$nit_out\n"
  fi
}

echo "=== nit conformance tests ==="
echo "repo: $TMPDIR"
echo ""

# --- Status tests ---
echo "status:"
# nit and git may sort differently (libgit2 vs git internals)
# so compare sorted output
check "porcelain entries match (sorted)" \
  "git status --porcelain | sort" \
  "$NIT status | sort"

# --- Log tests ---
echo ""
echo "log:"
check "oneline format matches" \
  "git log --oneline -20" \
  "$NIT log -n 20"

check "oneline -5 matches" \
  "git log --oneline -5" \
  "$NIT log -n 5"

check "oneline -1 matches" \
  "git log --oneline -1" \
  "$NIT log -n 1"

# --- Diff tests (compare stripped nit vs git -U1, accounting for header differences) ---
echo ""
echo "diff:"

# nit strips file headers to "--- path" and hunk context text.
# Compare just the +/- content lines (exclude nit's "--- path" lines).
check "unstaged change lines match" \
  "git diff -U1 | grep '^[+-]' | grep -v '^[+-][+-][+-]'" \
  "$NIT diff | grep '^[+-]' | grep -v '^--- '"

check "staged change lines match" \
  "git diff --staged -U1 | grep '^[+-]' | grep -v '^[+-][+-][+-]'" \
  "$NIT diff -s | grep '^[+-]' | grep -v '^--- '"

# --- Show tests ---
echo ""
echo "show:"

# Compare the commit summary line
check "show HEAD summary matches log" \
  "git log --oneline -1" \
  "$NIT show 2>&1 | head -1"

# Show a specific revision
SECOND_HASH=$(git log --oneline -3 | tail -1 | cut -d' ' -f1)
check "show specific rev summary" \
  "git log --oneline -1 $SECOND_HASH" \
  "$NIT show $SECOND_HASH 2>&1 | head -1"

# Show change lines match
check "show HEAD change lines match" \
  "git show -U1 HEAD | grep '^[+-]' | grep -v '^[+-][+-][+-]'" \
  "$NIT show 2>&1 | grep '^[+-]' | grep -v '^--- '"

# Show --stat
check "show --stat file count matches" \
  "git show --stat HEAD | tail -1 | grep -o '[0-9]* file' | head -1" \
  "$NIT show --stat 2>&1 | sed -n '2p' | grep -o '[0-9]* file' | head -1"

# --- Passthrough tests ---
echo ""
echo "passthrough:"

check "branch passthrough" \
  "git branch" \
  "$NIT branch"

check "log --graph passthrough" \
  "git log --graph --oneline -3" \
  "$NIT log --graph --oneline -3"

check "diff --name-only passthrough" \
  "git diff --name-only" \
  "$NIT diff --name-only"

check "diff --stat passthrough" \
  "git diff --stat" \
  "$NIT diff --stat"

# --- Status edge cases ---
echo ""
echo "status (edge cases):"

# Clean tree
git stash -q
check "clean tree = empty output" \
  "git status --porcelain" \
  "$NIT status"
git stash pop -q 2>/dev/null || true

# Deleted file (unstaged)
cp main.py main_backup.py
rm main.py
check "deleted file shows D (sorted)" \
  "git status --porcelain | sort" \
  "$NIT status | sort"
cp main_backup.py main.py
rm main_backup.py

# Renamed file (staged) - nit omits the "old -> new" arrow format,
# just shows the new name. Compare that rename is detected (R flag).
git mv utils.py utilities.py
check "renamed file detected" \
  "git status --porcelain | grep '^R' | wc -l | tr -d ' '" \
  "$NIT status | grep '^R' | wc -l | tr -d ' '"
git mv utilities.py utils.py

# --- Log edge cases ---
echo ""
echo "log (edge cases):"

check "-n larger than history" \
  "git log --oneline -100" \
  "$NIT log -n 100"

check "short alias l" \
  "git log --oneline -5" \
  "$NIT l -n 5"

# --- Diff edge cases ---
echo ""
echo "diff (edge cases):"

# Clean tree diff = empty
git stash -q
check "clean tree diff = empty" \
  "git diff -U1" \
  "$NIT diff"
git stash pop -q 2>/dev/null || true

check "short alias d" \
  "$NIT diff | grep '^[+-]' | grep -v '^--- '" \
  "$NIT d | grep '^[+-]' | grep -v '^--- '"

check "short alias s" \
  "$NIT status" \
  "$NIT s"

# Deleted file diff
cp main.py main_backup.py
rm main.py
check "deleted file diff lines" \
  "git diff -U1 | grep '^-' | grep -v '^---'" \
  "$NIT diff | grep '^-' | grep -v '^--- '"
cp main_backup.py main.py
rm main_backup.py

# No trailing newline - known issue: nit's buffered writer doesn't
# insert a newline when the file lacks one, causing lines to run together.
# TODO: handle GIT_DIFF_LINE_DEL_EOFNL / ADD_EOFNL markers
printf "no newline" > nonewline.txt
git add nonewline.txt
printf "no newline changed" > nonewline.txt
git reset -q nonewline.txt
rm -f nonewline.txt

# --- Show edge cases ---
echo ""
echo "show (edge cases):"

FIRST_HASH=$(git log --oneline | tail -1 | cut -d' ' -f1)
check "initial commit (no parent)" \
  "$NIT show $FIRST_HASH 2>&1 | head -1" \
  "git log --oneline -1 $FIRST_HASH"

check "HEAD~2 relative rev" \
  "git log --oneline -1 HEAD~2" \
  "$NIT show HEAD~2 2>&1 | head -1"

check "show --stat specific rev" \
  "$NIT show --stat $FIRST_HASH 2>&1 | head -1" \
  "git log --oneline -1 $FIRST_HASH"

git tag v1.0 HEAD~1
check "show tag name" \
  "git log --oneline -1 v1.0" \
  "$NIT show v1.0 2>&1 | head -1"

# --- Passthrough edge cases ---
echo ""
echo "passthrough (edge cases):"

check "unknown command: remote -v" \
  "git remote -v" \
  "$NIT remote -v"

check "unknown command: tag" \
  "git tag" \
  "$NIT tag"

check "status with unknown flag" \
  "git status -v" \
  "$NIT status -v"

check "log with --format passthrough" \
  'git log --format="%H" -1' \
  '$NIT log --format="%H" -1'

check "show with --format passthrough" \
  'git show --format="%H" -s' \
  '$NIT show --format="%H" -s'

check "diff --cached passthrough" \
  "git diff --cached" \
  "$NIT diff --cached"

# --- Not a repo ---
echo ""
echo "error handling:"

# Error message differs (libgit2 vs git) but exit code should match
check "not a git repo exits 128" \
  "cd /tmp && git status 2>/dev/null; echo \$?" \
  "cd /tmp && $NIT status 2>/dev/null; echo \$?"

# --- Summary ---
echo ""
echo "=== results ==="
echo "  passed: $PASS"
echo "  failed: $FAIL"
echo "  total:  $((PASS + FAIL))"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "=== failures ==="
  printf "$ERRORS"
  exit 1
fi
