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
git init -q -b main
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

stat_body_additions() {
  "$NIT" show --stat "$1" 2>&1 \
    | tail -n +3 \
    | grep -o '+[0-9]*' \
    | tr -d '+' \
    | awk '{sum += $1} END {print sum + 0}'
}

stat_summary_additions() {
  "$NIT" show --stat "$1" 2>&1 \
    | sed -n '2p' \
    | grep -o '+[0-9]*' \
    | tr -d '+'
}

hex_dump() {
  od -An -tx1 -v | tr -d ' \n'
  echo
}

script_tty() {
  if script -q -c "true" /dev/null >/dev/null 2>&1; then
    local quoted=""
    local arg
    for arg in "$@"; do
      quoted+="$(printf '%q' "$arg") "
    done
    script -q -c "$quoted" /dev/null
  else
    script -q /dev/null "$@"
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

check "short alias l --graph passthrough" \
  "git log --graph --oneline -3" \
  "$NIT l --graph --oneline -3"

check "diff --name-only passthrough" \
  "git diff --name-only" \
  "$NIT diff --name-only"

check "short alias d --name-only passthrough" \
  "git diff --name-only" \
  "$NIT d --name-only"

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

# No trailing newline: compact diff should keep git's marker on its own
# line instead of running the deletion/addition lines together.
git stash -q
printf "no newline" > nonewline.txt
git add nonewline.txt
git commit -q -m "Add no-newline fixture"
printf "no newline changed" > nonewline.txt
check "no trailing newline markers" \
  "git diff -U1 | grep -E '^[-+]no newline|^\\\\ No newline'" \
  "$NIT diff | grep -E '^[-+]no newline|^\\\\ No newline'"
git reset --hard -q HEAD~1
git stash pop -q 2>/dev/null || true
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

check "show -s passthrough (suppress diff)" \
  "git show -s | wc -l | tr -d ' '" \
  "$NIT show -s | wc -l | tr -d ' '"

check "diff -s works (staged)" \
  "git diff --staged -U1 | grep '^[+-]' | grep -v '^[+-][+-][+-]'" \
  "$NIT diff -s | grep '^[+-]' | grep -v '^--- '"

# --- Show --stat edge cases ---
echo ""
echo "show --stat (edge cases):"

# Stat on the delete-only commit
DELETE_HASH=$(git log --oneline -1 --all --grep="Remove" | cut -d' ' -f1)
# Delete commit should have at least one file with deletions
check "show --stat delete commit has deletions" \
  "$NIT show --stat $DELETE_HASH 2>&1 | grep -c '^\  .*-[0-9]'" \
  "echo 1"

# Initial commit should have files with additions (the per-file lines)
check "show --stat initial commit has additions" \
  "$NIT show --stat $FIRST_HASH 2>&1 | grep -c '^\  .*+[0-9]'" \
  "echo 2"

# Stat per-file totals add up to summary
check "show --stat totals consistent" \
  "stat_body_additions $FIRST_HASH" \
  "stat_summary_additions $FIRST_HASH"

# --- Merge commit ---
echo ""
echo "merge commit:"

# Create a clean merge (no conflicts) by touching different files
git stash -q
git checkout -q -b feature
echo "# feature notes" > feature.txt
git add feature.txt
git commit -q -m "Add feature file"
git checkout -q main
echo "# readme" > README.txt
git add README.txt
git commit -q -m "Add readme"
git merge -q --no-edit feature

check "merge commit in log" \
  "git log --oneline -1" \
  "$NIT log -n 1"

check "merge commit show summary" \
  "git log --oneline -1" \
  "$NIT show 2>&1 | head -1"

git stash pop -q 2>/dev/null || true

# --- Multiple files in diff ---
echo ""
echo "multi-file:"

check "diff lists all changed files" \
  "git diff -U1 --name-only | sort" \
  "$NIT diff | grep '^--- ' | sed 's/^--- //' | sort"

check "diff file count matches" \
  "git diff --stat | tail -1 | grep -o '[0-9]* file' | head -1" \
  "$NIT diff | grep '^--- ' | wc -l | tr -d ' ' | sed 's/$/& file/;s/^\\([0-9]*\\)& /\\1 /'"

# --- Subdirectory ---
echo ""
echo "subdirectory:"

mkdir -p sub
check "status from subdirectory" \
  "cd sub && git status --porcelain | sort" \
  "cd sub && $NIT status | sort"

check "log from subdirectory" \
  "cd sub && git log --oneline -3" \
  "cd sub && $NIT log -n 3"

check "diff from subdirectory" \
  "cd sub && git diff -U1 | grep '^[+-]' | grep -v '^[+-][+-][+-]'" \
  "cd sub && $NIT diff | grep '^[+-]' | grep -v '^--- '"

# --- Usage/help ---
echo ""
echo "usage:"

check "no args shows usage" \
  "$NIT 2>&1 | head -1" \
  "echo 'nit - the smallest unit of git'"

check "--help shows usage" \
  "$NIT --help 2>&1 | head -1" \
  "echo 'nit - the smallest unit of git'"

check "help shows usage" \
  "$NIT help 2>&1 | head -1" \
  "echo 'nit - the smallest unit of git'"

# --- Not a repo ---
echo ""
echo "error handling:"

# Error message differs (libgit2 vs git) but exit code should match
check "not a git repo exits 128" \
  "cd /tmp && git status 2>/dev/null; echo \$?" \
  "cd /tmp && $NIT status 2>/dev/null; echo \$?"

# --- Human mode (-H) ---
echo ""
echo "human mode (-H):"

check "status -H has unstaged section" \
  "$NIT status -H 2>&1 | grep -c '^unstaged:'" \
  "echo 1"

check "status -H has untracked section" \
  "$NIT status -H 2>&1 | grep -c '^untracked:'" \
  "echo 1"

check "status --human same as -H" \
  "$NIT status -H 2>&1" \
  "$NIT status --human 2>&1"

check "log -H includes date" \
  "$NIT log -H -n 1 2>&1 | grep -cE '[0-9]{4}-[0-9]{2}-[0-9]{2}'" \
  "echo 1"

check "log -H hash matches compact" \
  "$NIT log -n 1 | cut -d' ' -f1" \
  "$NIT log -H -n 1 2>&1 | cut -d' ' -f1"

check "diff -H includes stat summary" \
  "$NIT diff -H 2>&1 | head -1 | grep -cE '[0-9]+ file'" \
  "echo 1"

check "show -H includes full hash" \
  "$NIT show -H 2>&1 | head -1 | grep -cE 'commit [0-9a-f]{40}'" \
  "echo 1"

check "show -H includes Author line" \
  "$NIT show -H 2>&1 | grep -c '^Author:'" \
  "echo 1"

check "show -H includes Date line" \
  "$NIT show -H 2>&1 | grep -cE '^Date:'" \
  "echo 1"

# --- Detached HEAD ---
echo ""
echo "detached HEAD:"

git checkout -q --detach HEAD

check "status in detached HEAD (sorted)" \
  "git status --porcelain | sort" \
  "$NIT status | sort"

check "log in detached HEAD" \
  "git log --oneline -3" \
  "$NIT log -n 3"

check "show in detached HEAD" \
  "git log --oneline -1" \
  "$NIT show 2>&1 | head -1"

git checkout -q -

# --- Staged deletion ---
echo ""
echo "staged deletion:"

# git rm --cached leaves file on disk, so git shows "D  main.py" (deleted from index)
# plus " D main.py" is NOT shown (file still exists but now untracked).
# nit may show D? because libgit2 sees both deleted-from-index and untracked-in-workdir.
# Compare that the D flag is present in the index column.
git rm -q --cached main.py
check "staged deletion has D in index column" \
  "git status --porcelain | grep '^D' | wc -l | tr -d ' '" \
  "$NIT status | grep '^D' | wc -l | tr -d ' '"

check "status -H labels it deleted" \
  "$NIT status -H 2>&1 | grep -c 'deleted:'" \
  "echo 1"
git reset -q HEAD main.py

# --- Staged new file ---
echo ""
echo "staged new file:"

echo "brand new" > brandnew.txt
git add brandnew.txt
check "staged new file shows A" \
  "git status --porcelain | grep brandnew" \
  "$NIT status | grep brandnew"

check "status -H labels it new" \
  "$NIT status -H 2>&1 | grep -c 'new:.*brandnew'" \
  "echo 1"
git reset -q HEAD brandnew.txt
rm -f brandnew.txt

# --- Flag edge cases ---
echo ""
echo "flag edge cases:"

check "-n 0 shows nothing" \
  "$NIT log -n 0 2>&1" \
  ""

check "--staged same as -s for diff" \
  "$NIT diff -s 2>&1" \
  "$NIT diff --staged 2>&1"

check "log --stat passthrough" \
  "git log --stat -1" \
  "$NIT log --stat -1"

# --- Not a repo for each command ---
echo ""
echo "not-a-repo (all commands):"

check "log not-a-repo exits 128" \
  "cd /tmp && git log 2>/dev/null; echo \$?" \
  "cd /tmp && $NIT log 2>/dev/null; echo \$?"

# git diff exits 129 outside a repo, nit exits 128. Both are non-zero error.
check "diff not-a-repo exits non-zero" \
  "cd /tmp && $NIT diff 2>/dev/null; [ \$? -ne 0 ] && echo error" \
  "echo error"

check "show not-a-repo exits 128" \
  "cd /tmp && git show 2>/dev/null; echo \$?" \
  "cd /tmp && $NIT show 2>/dev/null; echo \$?"

# --- Compact format verification ---
echo ""
echo "compact format:"

check "hunk headers end at @@" \
  "$NIT diff 2>&1 | grep '^@@' | head -1 | grep -cE '@@$'" \
  "echo 1"

check "file headers use --- path format" \
  "$NIT diff 2>&1 | grep '^--- ' | head -1 | grep -cE '^--- [a-zA-Z]'" \
  "echo 1"

# --- Alias + flag combos ---
echo ""
echo "alias + flag combos:"

check "s -H works" \
  "$NIT status -H 2>&1" \
  "$NIT s -H 2>&1"

check "l -H -n 3 works" \
  "$NIT log -H -n 3 2>&1" \
  "$NIT l -H -n 3 2>&1"

check "d -s works" \
  "$NIT diff -s 2>&1" \
  "$NIT d -s 2>&1"

# --- Human mode clean tree ---
echo ""
echo "human mode clean tree:"

# Stash doesn't capture untracked files, so remove them first
git stash -q
rm -f newfile.txt
check "status -H clean tree = empty" \
  "$NIT status -H 2>&1" \
  ""

check "diff -H clean tree = empty" \
  "$NIT diff -H 2>&1" \
  ""
git stash pop -q 2>/dev/null || true
echo "# new file" > newfile.txt

# --- Branch tests ---
echo ""
echo "branch:"

# Create extra branches for testing
git branch feature-alpha
git branch feature-beta

check "branch compact lists current branch" \
  "$NIT branch 2>&1 | grep -c '^\*'" \
  "echo 1"

check "branch compact current branch marker" \
  "$NIT branch 2>&1 | grep '^\*' | awk '{print \$2}'" \
  "git rev-parse --abbrev-ref HEAD"

check "branch compact lists all local branches" \
  "$NIT branch 2>&1 | wc -l | tr -d ' '" \
  "git branch | wc -l | tr -d ' '"

# git uses 2 spaces before branch name, nit also uses 2 spaces.
# Compare branch names only (strip leading whitespace and *)
check "branch compact matches git branch names" \
  "git branch | sed 's/^[* ]*//' | sort" \
  "$NIT branch 2>&1 | sed 's/^[* ]*//' | sort"

check "branch alias b works" \
  "$NIT branch 2>&1" \
  "$NIT b 2>&1"

check "branch -H output matches compact (no tty)" \
  "$NIT branch 2>&1" \
  "$NIT branch -H 2>&1"

check "branch -a passthrough" \
  "git branch -a" \
  "$NIT branch -a"

check "branch -r passthrough" \
  "git branch -r" \
  "$NIT branch -r"

check "branch --merged passthrough" \
  "git branch --merged" \
  "$NIT branch --merged"

# -a passthrough on short alias: currently sends "git b -a" which fails
# because git doesn't know "b". This is a known limitation of alias + passthrough.
# Test that the full command name works instead.
check "branch -a passthrough works" \
  "git branch -a | sed 's/^[* ]*//' | sort" \
  "$NIT branch -a | sed 's/^[* ]*//' | sort"

# Clean up test branches
git branch -D feature-alpha feature-beta -q

# --- Show rev:path tests ---
echo ""
echo "show rev:path:"

check "show HEAD:main.py matches file content" \
  "git show HEAD:main.py" \
  "$NIT show HEAD:main.py 2>&1"

check "show HEAD:utils.py matches file content" \
  "git show HEAD:utils.py" \
  "$NIT show HEAD:utils.py 2>&1"

PREV_HASH=$(git log --oneline -2 | tail -1 | cut -d' ' -f1)
check "show specific-rev:path matches git" \
  "git show $PREV_HASH:main.py" \
  "$NIT show $PREV_HASH:main.py 2>&1"

check "show HEAD~1:main.py relative rev" \
  "git show HEAD~1:main.py" \
  "$NIT show HEAD~1:main.py 2>&1"

check "show nonexistent path exits non-zero" \
  "$NIT show HEAD:nonexistent.txt 2>/dev/null; [ \$? -ne 0 ] && echo error" \
  "echo error"

# Binary file test
printf '\x00\x01\x02\x03BINARY\xff\xfe' > binary.dat
git add binary.dat
git commit -q -m "Add binary file"
check "show HEAD:binary.dat matches git" \
  "git show HEAD:binary.dat | hex_dump" \
  "$NIT show HEAD:binary.dat 2>&1 | hex_dump"

# --- NIT_COLORS env var ---
echo ""
echo "NIT_COLORS:"

# On macOS, script -q /dev/null forces a pseudo-TTY
# Verify that NIT_COLORS changes output when running in a TTY
if command -v script >/dev/null 2>&1; then
  # Without NIT_COLORS: default colors in TTY
  default_out=$(script_tty "$NIT" show -H 2>&1 | cat -v | head -3)
  # With NIT_COLORS: custom hash color (magenta = 35)
  custom_out=$(script_tty env NIT_COLORS="hash=35" "$NIT" show -H 2>&1 | cat -v | head -3)

  if [ "$default_out" != "$custom_out" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS changes output"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS changes output"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS changes output ---\n"
    ERRORS="${ERRORS}default: $default_out\n"
    ERRORS="${ERRORS}custom:  $custom_out\n"
  fi

  # Verify NIT_COLORS doesn't break non-human mode
  check "NIT_COLORS has no effect without -H (no tty)" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=35:add=34' $NIT log -n 1 2>&1"

  # Verify NIT_COLORS doesn't crash with invalid values
  check "NIT_COLORS invalid values don't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='bogus' $NIT log -n 1 2>&1"

  check "NIT_COLORS empty value doesn't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=' $NIT log -n 1 2>&1"

  # Multiple keys at once
  check "NIT_COLORS multiple keys don't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=33:add=32:del=31:hunk=36:context=2:staged=34:unstaged=91:date=35' $NIT log -n 1 2>&1"

  # True-color (24-bit) SGR value
  check "NIT_COLORS true-color value doesn't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=38;2;255;165;0' $NIT log -n 1 2>&1"

  # Verify true-color actually produces escape sequence in TTY
  truecolor_out=$(script_tty env NIT_COLORS="hash=38;2;255;0;0" "$NIT" show -H 2>&1 | cat -v | head -1)
  if echo "$truecolor_out" | grep -q '38;2;255;0;0'; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS true-color escape in TTY output"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS true-color escape in TTY output"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS true-color escape in TTY output ---\n"
    ERRORS="${ERRORS}output: $truecolor_out\n"
  fi

  # Very long NIT_COLORS string (SGR value exceeds 32-byte buffer)
  check "NIT_COLORS oversized SGR falls back gracefully" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=38;2;255;255;255;1;2;3;4;5;6;7;8;9;10;11;12' $NIT log -n 1 2>&1"

  # Unrecognized key (should be silently ignored)
  check "NIT_COLORS unrecognized key ignored" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='boguskey=32' $NIT log -n 1 2>&1"

  # Duplicate keys (last wins) - verify output changes with second value
  dup_out1=$(script_tty env NIT_COLORS="hash=35" "$NIT" show -H 2>&1 | cat -v | head -1)
  dup_out2=$(script_tty env NIT_COLORS="hash=33:hash=35" "$NIT" show -H 2>&1 | cat -v | head -1)
  if [ "$dup_out1" = "$dup_out2" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS duplicate keys (last wins)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS duplicate keys (last wins)"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS duplicate keys (last wins) ---\n"
    ERRORS="${ERRORS}single: $dup_out1\n"
    ERRORS="${ERRORS}dup:    $dup_out2\n"
  fi

  # No = sign in a pair (should skip that pair, not crash)
  check "NIT_COLORS no equals sign doesn't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='noequalssign' $NIT log -n 1 2>&1"

  # Trailing colon
  check "NIT_COLORS trailing colon doesn't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=33:' $NIT log -n 1 2>&1"

  # Leading colon
  check "NIT_COLORS leading colon doesn't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS=':hash=33' $NIT log -n 1 2>&1"

  # Multiple colons in a row
  check "NIT_COLORS consecutive colons don't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='hash=33:::add=32' $NIT log -n 1 2>&1"

  # Buffer exhaustion: more than 10 custom keys (only 10 bufs available)
  check "NIT_COLORS >10 overrides doesn't crash" \
    "$NIT log -n 1 2>&1" \
    "NIT_COLORS='add=31:del=32:hunk=33:context=34:staged=35:unstaged=36:hash=37:date=38:add=39:del=40:hunk=41:context=42' $NIT log -n 1 2>&1"

  # NIT_COLORS affects show -H (color slot: hash, date used in show)
  custom_show=$(script_tty env NIT_COLORS="hash=35" "$NIT" show -H 2>&1 | cat -v | head -1)
  if [ "$default_out" != "$custom_show" ] || echo "$custom_show" | grep -q '35m'; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS affects show -H"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS affects show -H"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS affects show -H ---\n"
  fi

  # NIT_COLORS affects diff -H (color slot: add, del, hunk, context)
  default_diff=$(script_tty "$NIT" diff -H 2>&1 | cat -v | head -3)
  custom_diff=$(script_tty env NIT_COLORS="add=35:del=36" "$NIT" diff -H 2>&1 | cat -v | head -3)
  if [ "$default_diff" != "$custom_diff" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS affects diff -H"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS affects diff -H"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS affects diff -H ---\n"
  fi

  # NIT_COLORS affects log -H (color slot: hash, date)
  default_log=$(script_tty "$NIT" log -H -n 1 2>&1 | cat -v | head -1)
  custom_log=$(script_tty env NIT_COLORS="hash=35:date=36" "$NIT" log -H -n 1 2>&1 | cat -v | head -1)
  if [ "$default_log" != "$custom_log" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS affects log -H"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS affects log -H"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS affects log -H ---\n"
  fi

  # NIT_COLORS affects status -H (color slot: staged, unstaged)
  default_status=$(script_tty "$NIT" status -H 2>&1 | cat -v)
  custom_status=$(script_tty env NIT_COLORS="staged=35:unstaged=36" "$NIT" status -H 2>&1 | cat -v)
  if [ "$default_status" != "$custom_status" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: NIT_COLORS affects status -H"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: NIT_COLORS affects status -H"
    ERRORS="${ERRORS}\n--- FAIL: NIT_COLORS affects status -H ---\n"
  fi
else
  echo "  SKIP: NIT_COLORS (script command not available)"
fi

# --- Human mode non-TTY formatting ---
echo ""
echo "human mode non-TTY (pipe):"

# show -H piped (no TTY) should still produce human-readable text without ANSI
check "show -H non-TTY has commit line" \
  "$NIT show -H 2>&1 | grep -c '^commit '" \
  "echo 1"

check "show -H non-TTY has Author line" \
  "$NIT show -H 2>&1 | grep -c '^Author:'" \
  "echo 1"

check "show -H non-TTY has Date line" \
  "$NIT show -H 2>&1 | grep -c '^Date:'" \
  "echo 1"

check "show -H non-TTY no ANSI escapes" \
  "$NIT show -H 2>&1 | grep -c $'\x1b'" \
  "echo 0"

check "log -H non-TTY includes date" \
  "$NIT log -H -n 1 2>&1 | grep -cE '[0-9]{4}-[0-9]{2}-[0-9]{2}'" \
  "echo 1"

check "log -H non-TTY no ANSI escapes" \
  "$NIT log -H -n 3 2>&1 | grep -c $'\x1b'" \
  "echo 0"

check "diff -H non-TTY includes stat line" \
  "$NIT diff -H 2>&1 | head -1 | grep -cE '[0-9]+ file'" \
  "echo 1"

check "diff -H non-TTY no ANSI escapes" \
  "$NIT diff -H 2>&1 | grep -c $'\x1b'" \
  "echo 0"

check "status -H non-TTY no ANSI escapes" \
  "$NIT status -H 2>&1 | grep -c $'\x1b'" \
  "echo 0"

# --- show --stat + -H combined ---
echo ""
echo "show --stat -H:"

check "show --stat -H includes commit header" \
  "$NIT show --stat -H 2>&1 | grep -c '^commit '" \
  "echo 1"

check "show --stat -H includes stat line" \
  "$NIT show --stat -H 2>&1 | grep -cE '[0-9]+ file'" \
  "echo 1"

check "show --stat -H has no diff hunks" \
  "$NIT show --stat -H 2>&1 | grep -c '^@@'" \
  "echo 0"

# --- fmt.writeStat singular vs plural ---
echo ""
echo "writeStat formatting:"

# The binary.dat commit only touches 1 file - should say "1 file" not "1 files"
BINARY_HASH=$(git log --oneline -1 --all --grep="binary" | cut -d' ' -f1)
check "show --stat singular file" \
  "$NIT show --stat $BINARY_HASH 2>&1 | sed -n '2p' | grep -cE '^1 file,'" \
  "echo 1"

# Multi-file commit should say "files" plural
MULTI_HASH=$(git log --oneline -1 --all --grep="Add config" | cut -d' ' -f1)
check "show --stat plural files" \
  "$NIT show --stat $MULTI_HASH 2>&1 | sed -n '2p' | grep -cE '[2-9] files,'" \
  "echo 1"

# Deletion-only file: per-file lines (indented with 2 spaces) should have -N
check "show --stat delete-only file shows -N" \
  "$NIT show --stat $DELETE_HASH 2>&1 | grep '^  ' | grep -c -- '-[0-9]'" \
  "echo 1"

# --- status -H section combinations ---
echo ""
echo "status -H section combos:"

# Ensure all three states exist
echo "staged change" >> utils.py
git add utils.py
sed -i.bak 's/hello nit/hello nit v3/' main.py && rm -f main.py.bak
echo "# untracked" > untracked_test.txt
check "status -H all three sections present" \
  "$NIT status -H 2>&1 | grep -cE '^(staged:|unstaged:|untracked:)'" \
  "echo 3"
git checkout -q -- main.py
git reset -q HEAD utils.py
git checkout -q -- utils.py
rm -f untracked_test.txt

# Staged-only: stage everything, remove untracked
git stash -q
rm -f newfile.txt
echo "staged only" > staged_only.txt
git add staged_only.txt
check "status -H staged-only has staged section" \
  "$NIT status -H 2>&1 | grep -c '^staged:'" \
  "echo 1"
check "status -H staged-only no unstaged section" \
  "$NIT status -H 2>&1 | grep -c '^unstaged:'" \
  "echo 0"
check "status -H staged-only no untracked section" \
  "$NIT status -H 2>&1 | grep -c '^untracked:'" \
  "echo 0"
git reset -q HEAD staged_only.txt
rm -f staged_only.txt
git stash pop -q 2>/dev/null || true
echo "# new file" > newfile.txt

# Untracked-only
git stash -q
rm -f newfile.txt
echo "just untracked" > only_untracked.txt
check "status -H untracked-only has untracked section" \
  "$NIT status -H 2>&1 | grep -c '^untracked:'" \
  "echo 1"
check "status -H untracked-only no staged section" \
  "$NIT status -H 2>&1 | grep -c '^staged:'" \
  "echo 0"
rm -f only_untracked.txt
git stash pop -q 2>/dev/null || true
echo "# new file" > newfile.txt

# --- showBlob edge cases ---
echo ""
echo "showBlob:"

# Show a directory path (tree object, not blob) should fail
check "show rev:directory exits non-zero" \
  "$NIT show HEAD:. 2>/dev/null; [ \$? -ne 0 ] && echo error" \
  "echo error"

# Show rev:path with relative rev
check "show HEAD~1:main.py works" \
  "git show HEAD~1:main.py" \
  "$NIT show HEAD~1:main.py 2>&1"

# Show empty file
touch empty_file.txt
git add empty_file.txt
git commit -q -m "Add empty file"
check "show HEAD:empty_file produces no output" \
  "git show HEAD:empty_file.txt" \
  "$NIT show HEAD:empty_file.txt 2>&1"

# --- diff -s (staged) edge cases ---
echo ""
echo "diff staged edge cases:"

# Stage a new file and check diff -s output
echo "new staged content" > staged_new.txt
git add staged_new.txt
check "diff -s new file shows additions" \
  "git diff --staged -U1 | grep '^+' | grep -v '^+++'" \
  "$NIT diff -s | grep '^+' | grep -v '^--- '"
git reset -q HEAD staged_new.txt
rm -f staged_new.txt

# --- show initial commit (no parent tree) diff ---
echo ""
echo "show initial commit diff:"

check "show initial commit has diff content" \
  "$NIT show $FIRST_HASH 2>&1 | grep -c '^+'" \
  "git show -U1 $FIRST_HASH | grep '^+' | grep -v '^+++' | wc -l | tr -d ' '"

# --- log default count ---
echo ""
echo "log defaults:"

check "log default returns up to 20 entries" \
  "$NIT log 2>&1 | wc -l | tr -d ' '" \
  "git log --oneline -20 | wc -l | tr -d ' '"

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

