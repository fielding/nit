# Experiments

Empirical tests to validate nit's design decisions.

## Context Lines

**Question:** Does reducing diff context lines (U0 vs U1 vs U3) hurt an AI agent's ability to understand and act on diffs?

**Why it matters:** Every context line in a diff costs tokens. nit defaults to U1 (1 line of context) instead of git's U3 (3 lines). If agents perform just as well with less context, we can save more tokens. If they don't, we need to know.

### Basic Test (`context-lines.py`)

Creates a test repo with a Python module, makes two changes (security fix + input validation), then asks Claude to answer 4 questions of increasing difficulty about the diff:

1. What security issue was fixed? (reads +/- lines)
2. What validation was added and where? (needs method-level understanding)
3. What line number is the change on? (needs positional awareness)
4. Where would you insert similar code? (needs structural understanding)

Runs 3 trials per variant (U0, U1, U3) and grades responses automatically.

```sh
python3 experiments/context-lines.py
```

**Results (2026-03-14):** All variants scored 4/4 across all trials. U0 performed identically to U3. The hunk header line numbers + the changed lines themselves provide enough information for the agent to orient.

### Comprehensive Test (`context-lines-hard.py`)

A harder version designed to stress-test context dependence with scenarios where context should actually matter:

- Multi-file diffs with similar variable names across files
- Changes inside nested control flow (need context to know which branch)
- Renamed/moved code where context distinguishes similar blocks
- Diffs where the change is ambiguous without surrounding code

```sh
python3 experiments/context-lines-hard.py
```

**Results (2026-03-14):** All variants scored 4/4 across all 27 trials. Even with ambiguous similar code blocks and deeply nested control flow, U0 performed identically to U3.

### Behavioral Analysis (`read-after-diff.py`)

Analyzes 561 real `git diff` / `git show` calls from Claude Code session transcripts to measure what agents do *after* seeing a diff. The question: do agents compensate for less context by reading the file?

```sh
python3 experiments/read-after-diff.py
```

**Results (2026-03-14):**
- Only 3.9% of the time does an agent Read a file immediately after diffing
- Only 15% within 3 tool calls
- 85% of the time, the diff is all the agent uses to understand changes

**Conclusion:** Agents understand diffs perfectly at any context level (U0 = U1 = U3 for comprehension). But since they rarely read files after diffing, the diff's context lines are their primary source of surrounding code info. U1 balances token savings with giving the agent enough to orient.

### Running Your Own

These tests require the `claude` CLI (`brew install claude`). Each run costs a few cents in API tokens. Adjust `RUNS_PER_VARIANT` to trade off statistical confidence vs cost.

### Contributing

If you run these experiments and get different results (different model, larger codebase, different language), open an issue with your data. We want to know if U1 is the right default or if we should go lower/higher.
