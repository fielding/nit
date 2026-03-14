# experiments

empirical tests to validate nit's design decisions.

## context-lines

**question:** does reducing diff context lines (U0 vs U1 vs U3) hurt an AI agent's ability to understand and act on diffs?

**why it matters:** every context line in a diff costs tokens. nit defaults to U1 (1 line of context) instead of git's U3 (3 lines). if agents perform just as well with less context, we can save more tokens. if they don't, we need to know.

### basic test (`context-lines.py`)

creates a test repo with a python module, makes two changes (security fix + input validation), then asks claude to answer 4 questions of increasing difficulty about the diff:

1. what security issue was fixed? (reads +/- lines)
2. what validation was added and where? (needs method-level understanding)
3. what line number is the change on? (needs positional awareness)
4. where would you insert similar code? (needs structural understanding)

runs 3 trials per variant (U0, U1, U3) and grades responses automatically.

```sh
python3 experiments/context-lines.py
```

**results (2026-03-14):** all variants scored 4/4 across all trials. U0 performed identically to U3. the hunk header line numbers + the changed lines themselves provide enough information for the agent to orient.

### comprehensive test (`context-lines-hard.py`)

a harder version designed to stress-test context dependence with scenarios where context should actually matter:

- multi-file diffs with similar variable names across files
- changes inside nested control flow (need context to know which branch)
- renamed/moved code where context distinguishes similar blocks
- diffs where the change is ambiguous without surrounding code

```sh
python3 experiments/context-lines-hard.py
```

### running your own

these tests require the `claude` CLI (`brew install claude`). each run costs a few cents in API tokens. adjust `RUNS_PER_VARIANT` to trade off statistical confidence vs cost.

### contributing

if you run these experiments and get different results (different model, larger codebase, different language), open an issue with your data. we want to know if U1 is the right default or if we should go lower/higher.
