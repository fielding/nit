# nit

the smallest unit of git.

nit is a native git replacement built with Zig + libgit2, optimized for AI agent consumption. smaller output, fewer tokens, faster execution.

## why

AI agents (Claude Code, Codex, Cursor, etc.) call git *constantly*. every call burns tokens on verbose output that machines don't need -decorative headers, instructional text, column padding. across a single session, this adds up to thousands of wasted tokens.

nit fixes this by defaulting to compact, machine-readable output while being **1.4-1.5x faster** than git thanks to native libgit2.

## benchmarks

measured with [hyperfine](https://github.com/sharkdp/hyperfine), 100 runs, ReleaseFast build:

### speed (equivalent output, apples-to-apples)

| command | git equivalent | git | nit | speedup |
|---|---|---|---|---|
| `status` | `git status --porcelain -b` | 11.3 ms | 7.6 ms | **1.49x faster** |
| `diff` | `git diff -U1` | 11.2 ms | 8.1 ms | **1.38x faster** |
| `log -20` | `git log -20 --oneline` | 6.5 ms | 6.6 ms | ~1x (parity) |

### token savings (nit default vs git default)

| command | `git` default | `nit` default | savings |
|---|---|---|---|
| `status` | ~116 tokens | ~30 tokens | **74%** |
| `log -20` | ~2,273 tokens | ~301 tokens | **87%** |
| `diff` | ~942 tokens | ~622 tokens | **34%** |

*token counts approximated at ~4 chars/token. savings scale with repo size and dirty file count.*

the speed gains come from libgit2 (no subprocess, native object db reads). the token savings come from compact defaults - the same flags exist in git, but agents don't use them because they'd need to be told to. nit just does it out of the box.

based on analysis of 3,156 real sessions across Claude Code, Codex, and Pi: git accounts for **~459K tokens** of output, representing **7.4% of all shell commands**. codex is the heaviest user at 10.7% of all bash calls being git. nit's compact defaults would cut **150-250K tokens** across those sessions.

## install

requires [libgit2](https://libgit2.org/) and [zig](https://ziglang.org/) 0.14+.

```sh
# dependencies
brew install libgit2 zig

# build
git clone https://github.com/fielding/nit.git
cd nit
zig build -Doptimize=ReleaseFast

# install
cp zig-out/bin/nit ~/.local/bin/
```

## usage

nit defaults to compact, agent-optimized output. pass `-H` for human-readable formatting.

```sh
nit status          # compact porcelain output
nit log             # oneline, 20 most recent
nit diff            # 1-line context, stripped file headers
nit diff -s         # staged changes
nit show            # HEAD commit + patch
nit show abc123     # specific commit

nit status -H       # grouped by staged/unstaged/untracked
nit log -H          # includes dates
nit diff -H         # 3-line context, full headers

nit log -n 5        # limit to 5 commits
```

### passthrough

nit only optimizes a handful of commands today -the ones that burn the most tokens in real agent sessions. everything else is passed through to git automatically:

```sh
nit commit -m "..."   # → git commit -m "..."
nit push              # → git push
nit checkout -b foo   # → git checkout -b foo
```

passthrough uses `execvpe` -it replaces the nit process with git directly. no subprocess, no wrapper overhead. it's as if you typed `git` yourself.

this means you can `alias git=nit` and everything just works. as commands get optimized with native libgit2 implementations (prioritized by real-world usage frequency), the passthrough shrinks and nit gets faster -no config changes needed.

## compact vs human

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

## how it works

nit uses [libgit2](https://libgit2.org/) directly via Zig's zero-cost C interop -no subprocess, no shell, no parsing git's text output. this is why it's faster: it reads the git object database natively instead of spawning a process and parsing stdout.

for commands nit hasn't implemented yet, it calls `execvpe("git", ...)` which replaces the nit process with git -zero overhead, no wrapper tax.

## project structure

```
src/
  main.zig        entry point
  cli.zig         arg parsing, dispatch, git passthrough
  git.zig         libgit2 wrapper (@cImport, repo, error handling)
  cmd/
    status.zig    compact + human output
    log.zig       oneline + human with dates
    diff.zig      1-line context + human full context
```

## roadmap

- [x] `show` command (4th most token-heavy in real agent sessions)
- [x] strip more diff chrome (remove `diff --git` / `---`/`+++` headers in compact mode)
- [ ] `branch` command (compact listing)
- [ ] `stash` command
- [ ] cross-platform release binaries (GitHub Actions)
- [ ] homebrew formula
- [ ] benchmark against larger repos (linux kernel, chromium)

## license

MIT
