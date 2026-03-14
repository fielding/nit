# nit

The smallest unit of git.

A native git replacement built with Zig + libgit2, optimized for AI agent consumption. Smaller output, fewer tokens, faster execution.

## Why

AI agents (Claude Code, Codex, Cursor, etc.) call git *constantly*. Every call burns tokens on verbose output that machines don't need - decorative headers, instructional text, column padding. Across a single session, this adds up to thousands of wasted tokens.

nit fixes this by defaulting to compact, machine-readable output while being **1.4-1.5x faster** than git thanks to native libgit2.

## Benchmarks

Measured with [hyperfine](https://github.com/sharkdp/hyperfine), 100 runs, ReleaseFast build:

### Speed (equivalent output, apples-to-apples)

| Command | git equivalent | git | nit | Speedup |
|---|---|---|---|---|
| `status` | `git status --porcelain -b` | 13.7 ms | 8.4 ms | **1.64x faster** |
| `diff` | `git diff -U1` | 14.3 ms | 9.9 ms | **1.44x faster** |
| `show` | `git show` | 10.2 ms | 7.3 ms | **1.39x faster** |
| `log -20` | `git log -20 --oneline` | 7.7 ms | 9.5 ms | ~0.8x (slower) |

### Token savings (nit default vs git default)

| Command | `git` default | `nit` default | Savings |
|---|---|---|---|
| `status` | ~125 tokens | ~36 tokens | **71%** |
| `log -20` | ~2,273 tokens | ~301 tokens | **87%** |
| `diff` | ~1,016 tokens | ~657 tokens | **35%** |
| `show` | ~20,583 tokens | ~19,737 tokens | **4%** |
| `show --stat` | ~260 tokens | ~118 tokens | **55%** |

*Token counts approximated at ~4 chars/token. Savings scale with repo size and dirty file count.*

The speed gains come from libgit2 (no subprocess, native object db reads). The token savings come from compact defaults - the same flags exist in git, but agents don't use them because they'd need to be told to. nit just does it out of the box.

Note on `show --stat`: analysis of real sessions shows agents already use `git show --stat` 36% of the time. nit's compact stat drops the histogram bars and column padding, cutting output by 55%.

Based on analysis of 3,156 real sessions across Claude Code, Codex, and Pi: git accounts for **~459K tokens** of output, representing **7.4% of all shell commands**. Codex is the heaviest user at 10.7% of all bash calls being git. nit's compact defaults would cut **150-250K tokens** across those sessions.

### Context line validation

We ran [experiments](experiments/) to validate our choice of 1 context line (vs git's default 3). Across 36 trials with varying difficulty (multi-file diffs, nested control flow, ambiguous similar blocks), agents scored perfectly at U0, U1, and U3. However, behavioral analysis of 561 real agent sessions showed agents rarely read files after diffing (only 3.9% of the time), meaning diff context is their primary source of surrounding code info. U1 balances savings with orientation. See [experiments/README.md](experiments/README.md) for details.

## Install

Requires [libgit2](https://libgit2.org/) and [zig](https://ziglang.org/) 0.14+.

```sh
# From source
brew install libgit2 zig
git clone https://github.com/fielding/nit.git
cd nit
zig build -Doptimize=ReleaseFast
cp zig-out/bin/nit ~/.local/bin/

# Or via Homebrew
brew install fielding/tap/nit
```

## Usage

nit defaults to compact, agent-optimized output. Pass `-H` for human-readable formatting with ANSI colors.

```sh
nit status          # compact porcelain output
nit log             # oneline, 20 most recent
nit diff            # 1-line context, stripped file headers
nit diff -s         # staged changes
nit show            # HEAD commit + patch
nit show abc123     # specific commit

nit status -H       # grouped by staged/unstaged/untracked, colored
nit log -H          # includes dates, colored hashes
nit diff -H         # 3-line context, stat summary, colored output

nit log -n 5        # limit to 5 commits
nit show --stat     # compact file change summary
```

### Passthrough

nit only optimizes a handful of commands today - the ones that burn the most tokens in real agent sessions. Everything else is passed through to git automatically:

```sh
nit commit -m "..."   # -> git commit -m "..."
nit push              # -> git push
nit checkout -b foo   # -> git checkout -b foo
```

Passthrough also kicks in for **unrecognized flags** on native commands. If you pass a flag nit doesn't handle, it delegates to git rather than silently ignoring it:

```sh
nit diff --name-only  # nit doesn't implement --name-only, passes to git
nit log --graph       # nit doesn't implement --graph, passes to git
nit show --format=... # nit doesn't implement --format, passes to git
```

This makes `alias git=nit` safe. You never lose functionality - you just get optimized output for the flags nit knows about, and standard git behavior for everything else.

Passthrough uses `execvpe` - it replaces the nit process with git directly. No subprocess, no wrapper overhead. It's as if you typed `git` yourself.

As commands and flags get optimized with native libgit2 implementations (prioritized by real-world usage frequency), the passthrough shrinks and nit gets faster - no config changes needed.

## Compact vs Human

```
$ nit status
 M src/main.zig
 M src/cli.zig
?? TODO.md

$ nit status -H
unstaged:
  modified: src/main.zig
  modified: src/cli.zig

untracked:
  TODO.md
```

```
$ nit log -n 3
a1b2c3d Fix null pointer in parser
e4f5g6h Add user authentication
9i0j1k2 Initial commit

$ nit log -n 3 -H
a1b2c3d 2026-03-14 Fix null pointer in parser
e4f5g6h 2026-03-13 Add user authentication
9i0j1k2 2026-03-12 Initial commit
```

## How It Works

nit uses [libgit2](https://libgit2.org/) directly via Zig's zero-cost C interop - no subprocess, no shell, no parsing git's text output. This is why it's faster: it reads the git object database natively instead of spawning a process and parsing stdout.

For commands nit hasn't implemented yet, it calls `execvpe("git", ...)` which replaces the nit process with git - zero overhead, no wrapper tax.

## Testing

78 conformance tests verify nit's output matches git across: all 4 commands in compact and human mode, passthrough for unknown commands and flags, edge cases (clean tree, deleted files, renames, merge commits, detached HEAD, staged new/delete, subdirectories, aliases, flag combos, not-a-repo).

```sh
zig build && ./tests/conformance.sh
```

## Project Structure

```
src/
  main.zig        entry point
  cli.zig         arg parsing, dispatch, git passthrough
  git.zig         libgit2 wrapper (@cImport, repo, error handling)
  color.zig       ANSI escape codes + TTY detection
  fmt.zig         shared diff callbacks, stat output, date formatting
  cmd/
    status.zig    compact + human output
    log.zig       oneline + human with dates
    diff.zig      stripped headers + colored human mode
    show.zig      commit info + patch + --stat
```

## Roadmap

- [ ] `branch` command (compact listing)
- [ ] `stash` command
- [ ] `show <rev>:<path>` native implementation (36% of show usage)
- [ ] Benchmark against larger repos (linux kernel, chromium)

## License

MIT
