# nit

the smallest unit of git.

nit is a native git replacement built with Zig + libgit2, optimized for AI agent consumption. smaller output, fewer tokens, faster execution.

## why

AI agents (Claude Code, Codex, Cursor, etc.) call git *constantly*. every call burns tokens on verbose output that machines don't need — decorative headers, instructional text, column padding. across a single session, this adds up to thousands of wasted tokens.

nit fixes this by defaulting to compact, machine-readable output while being **1.5-1.7x faster** than git thanks to native libgit2.

## benchmarks

measured with [hyperfine](https://github.com/sharkdp/hyperfine), 100 runs, ReleaseFast build:

### speed

| command | git | nit | speedup |
|---|---|---|---|
| `status` | 14.7 ms | 8.9 ms | **1.66x faster** |
| `diff` | 14.0 ms | 9.6 ms | **1.46x faster** |
| `log -20` | 8.6 ms | 8.7 ms | ~1x (parity) |

### token savings

| command | git (tokens) | nit (tokens) | savings |
|---|---|---|---|
| `status` | ~116 | ~30 | **74%** |
| `log -20` | ~2,273 | ~301 | **87%** |
| `diff` | ~942 | ~811 | **14%** |

*token counts approximated at ~4 chars/token. savings scale with repo size and dirty file count.*

based on analysis of 2,830 real Claude Code sessions: git accounts for **310K+ tokens** of output. nit's compact defaults would save **100-150K tokens** across those sessions.

## install

requires [libgit2](https://libgit2.org/) and [zig](https://ziglang.org/) 0.14+.

```sh
# dependencies
brew install libgit2 zig

# build
git clone https://github.com/your-username/nit.git
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
nit diff            # 1-line context, minimal headers
nit diff -s         # staged changes

nit status -H       # grouped by staged/unstaged/untracked
nit log -H          # includes dates
nit diff -H         # 3-line context, full headers

nit log -n 5        # limit to 5 commits
```

any command nit doesn't implement is passed through to git:

```sh
nit commit -m "..."   # → git commit -m "..."
nit push              # → git push
nit checkout -b foo   # → git checkout -b foo
```

this means you can `alias git=nit` and everything works — optimized commands go native, everything else falls through with zero overhead.

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

nit uses [libgit2](https://libgit2.org/) directly via Zig's zero-cost C interop — no subprocess, no shell, no parsing git's text output. this is why it's faster: it reads the git object database natively instead of spawning a process and parsing stdout.

for commands nit hasn't implemented yet, it calls `execvpe("git", ...)` which replaces the nit process with git — zero overhead, no wrapper tax.

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

- [ ] `show` command (4th most token-heavy in real agent sessions)
- [ ] strip more diff chrome (remove `diff --git` / `---`/`+++` headers in compact mode)
- [ ] `branch` command (compact listing)
- [ ] `stash` command
- [ ] cross-platform release binaries (GitHub Actions)
- [ ] homebrew formula
- [ ] benchmark against larger repos (linux kernel, chromium)

## license

MIT
