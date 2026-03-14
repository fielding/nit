#!/usr/bin/env bash
# bench.sh — benchmark nit vs git
#
# Usage: ./bench.sh [repo-path]
# Defaults to current directory. Use a repo with dirty working tree for best results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIT="${NIT:-$SCRIPT_DIR/zig-out/bin/nit}"
REPO="${1:-.}"

# Resolve to absolute path
NIT="$(cd "$(dirname "$NIT")" && pwd)/$(basename "$NIT")"
RUNS=100

if ! command -v hyperfine &>/dev/null; then
  echo "error: hyperfine required (brew install hyperfine)"
  exit 1
fi

if [ ! -x "$NIT" ]; then
  echo "error: nit binary not found at $NIT"
  echo "       run: zig build -Doptimize=ReleaseFast"
  exit 1
fi

cd "$REPO"

echo "=== nit vs git benchmark ==="
echo "repo: $(pwd)"
echo "runs: $RUNS"
echo ""

# --- Speed benchmarks ---

echo "--- status ---"
hyperfine \
  --warmup 5 \
  --runs "$RUNS" \
  --export-markdown /dev/null \
  'git status' \
  'git status --porcelain -b' \
  "$NIT status" \
  2>&1

echo ""
echo "--- log (20 commits) ---"
hyperfine \
  --warmup 5 \
  --runs "$RUNS" \
  'git log -20 --oneline' \
  'git log -20' \
  "$NIT log" \
  2>&1

echo ""
echo "--- diff ---"
hyperfine \
  --warmup 5 \
  --runs "$RUNS" \
  'git diff' \
  'git diff -U1' \
  "$NIT diff" \
  2>&1

# --- Token benchmarks ---

echo ""
echo "=== token savings ==="
echo ""

measure() {
  local label="$1"
  shift
  local chars
  chars=$("$@" 2>/dev/null | wc -c | tr -d ' ')
  local tokens=$((chars / 4))
  printf "  %-30s %6s chars  ~%5s tokens\n" "$label" "$chars" "$tokens"
}

echo "--- status ---"
measure "git status" git status
measure "git status --porcelain -b" git status --porcelain -b
measure "nit status" "$NIT" status
echo ""

echo "--- log (20 commits) ---"
measure "git log -20" git log -20
measure "git log -20 --oneline" git log -20 --oneline
measure "nit log" "$NIT" log
echo ""

echo "--- diff ---"
measure "git diff" git diff
measure "git diff -U1" git diff -U1
measure "nit diff" "$NIT" diff
