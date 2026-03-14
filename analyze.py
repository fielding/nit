#!/usr/bin/env python3
"""Analyze git command usage and token cost across AI agent session histories.

Scans Claude Code, Codex, Cursor, and Pi session transcripts to measure
how often git commands are called and how many tokens their output consumes.

Usage: python3 analyze.py
"""

import json
import glob
import os
import sys

HOME = os.path.expanduser("~")

git_subcommands = ["status", "log", "diff", "show", "branch", "stash", "remote"]

results = {
    "claude": {"sessions": 0, "bash_total": 0, "git_total": 0, "git_cmds": {}, "git_output": {}},
    "codex":  {"sessions": 0, "bash_total": 0, "git_total": 0, "git_cmds": {}, "git_output": {}},
    "cursor": {"sessions": 0, "bash_total": 0, "git_total": 0, "git_cmds": {}, "git_output": {}},
    "pi":     {"sessions": 0, "bash_total": 0, "git_total": 0, "git_cmds": {}, "git_output": {}},
}

for sub in git_subcommands:
    for agent in results:
        results[agent]["git_cmds"][sub] = 0
        results[agent]["git_output"][sub] = []


def extract_git_subcmd(cmd):
    parts = cmd.strip().split()
    try:
        gi = next(i for i, p in enumerate(parts) if p == "git")
        if gi + 1 < len(parts):
            return parts[gi + 1]
    except StopIteration:
        pass
    return None


def is_git_cmd(cmd):
    return "git " in cmd or cmd.strip().startswith("git ")


# --- Claude Code ---
claude_transcripts = glob.glob(f"{HOME}/.claude/projects/*/*.jsonl")
claude_transcripts += glob.glob(f"{HOME}/.claude/projects/*/subagents/*.jsonl")

for path in claude_transcripts:
    results["claude"]["sessions"] += 1
    try:
        with open(path) as f:
            lines = f.readlines()
    except:
        continue

    pending = {}
    for line in lines:
        try:
            obj = json.loads(line.strip())
        except:
            continue

        content = obj.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue

        for block in content:
            if not isinstance(block, dict):
                continue

            if block.get("type") == "tool_use" and block.get("name") == "Bash":
                cmd = block.get("input", {}).get("command", "")
                results["claude"]["bash_total"] += 1
                if is_git_cmd(cmd):
                    results["claude"]["git_total"] += 1
                    sub = extract_git_subcmd(cmd)
                    if sub in git_subcommands:
                        results["claude"]["git_cmds"][sub] += 1
                        pending[block.get("id", "")] = sub

            if block.get("type") == "tool_result":
                tid = block.get("tool_use_id", "")
                if tid in pending:
                    sub = pending[tid]
                    rc = block.get("content", "")
                    text = ""
                    if isinstance(rc, str):
                        text = rc
                    elif isinstance(rc, list):
                        text = " ".join(b.get("text", "") for b in rc if isinstance(b, dict))
                    if len(text) > 0:
                        results["claude"]["git_output"][sub].append(len(text))
                    del pending[tid]

# --- Codex ---
codex_transcripts = glob.glob(f"{HOME}/.codex/sessions/*/*/*/*.jsonl")

for path in codex_transcripts:
    results["codex"]["sessions"] += 1
    try:
        with open(path) as f:
            lines = f.readlines()
    except:
        continue

    pending_id = None
    pending_sub = None
    for line in lines:
        try:
            obj = json.loads(line.strip())
        except:
            continue

        payload = obj.get("payload", {})
        pt = payload.get("type", "")

        if pt == "function_call" and payload.get("name") == "shell":
            args = json.loads(payload.get("arguments", "{}"))
            cmd_parts = args.get("command", [])
            cmd = " ".join(cmd_parts) if isinstance(cmd_parts, list) else str(cmd_parts)
            results["codex"]["bash_total"] += 1
            if is_git_cmd(cmd):
                results["codex"]["git_total"] += 1
                sub = extract_git_subcmd(cmd)
                if sub in git_subcommands:
                    results["codex"]["git_cmds"][sub] += 1
                    pending_id = payload.get("call_id", payload.get("id", ""))
                    pending_sub = sub

        if pt == "function_call_output":
            output = payload.get("output", "")
            if isinstance(output, str) and pending_sub and len(output) > 0:
                results["codex"]["git_output"][pending_sub].append(len(output))
                pending_id = None
                pending_sub = None

# --- Cursor ---
cursor_transcripts = glob.glob(f"{HOME}/.cursor/projects/*/agent-transcripts/*.jsonl")

for path in cursor_transcripts:
    results["cursor"]["sessions"] += 1
    try:
        with open(path) as f:
            lines = f.readlines()
    except:
        continue

    pending = {}
    for line in lines:
        try:
            obj = json.loads(line.strip())
        except:
            continue

        msg = obj.get("message", obj)
        content = msg.get("content", [])
        if isinstance(content, str):
            continue
        if not isinstance(content, list):
            content = [content] if isinstance(content, dict) else []

        for block in content:
            if not isinstance(block, dict):
                continue

            if block.get("type") == "tool_use" and block.get("name") in ("Bash", "terminal", "run_terminal_command"):
                inp = block.get("input", {})
                cmd = inp.get("command", inp.get("cmd", ""))
                results["cursor"]["bash_total"] += 1
                if is_git_cmd(cmd):
                    results["cursor"]["git_total"] += 1
                    sub = extract_git_subcmd(cmd)
                    if sub in git_subcommands:
                        results["cursor"]["git_cmds"][sub] += 1
                        pending[block.get("id", "")] = sub

            if block.get("type") == "tool_result":
                tid = block.get("tool_use_id", "")
                if tid in pending:
                    sub = pending[tid]
                    rc = block.get("content", "")
                    text = rc if isinstance(rc, str) else ""
                    if isinstance(rc, list):
                        text = " ".join(b.get("text", "") for b in rc if isinstance(b, dict))
                    if len(text) > 0:
                        results["cursor"]["git_output"][sub].append(len(text))
                    del pending[tid]

# --- Pi ---
pi_transcripts = glob.glob(f"{HOME}/.pi/agent/sessions/*/*.jsonl")

for path in pi_transcripts:
    results["pi"]["sessions"] += 1
    try:
        with open(path) as f:
            lines = f.readlines()
    except:
        continue

    for line in lines:
        try:
            obj = json.loads(line.strip())
        except:
            continue

        msg = obj.get("message", {})
        content = msg.get("content", [])
        if not isinstance(content, list):
            continue

        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "toolCall" and block.get("name") == "bash":
                args = block.get("arguments", {})
                cmd = args.get("command", "")
                results["pi"]["bash_total"] += 1
                if is_git_cmd(cmd):
                    results["pi"]["git_total"] += 1
                    sub = extract_git_subcmd(cmd)
                    if sub in git_subcommands:
                        results["pi"]["git_cmds"][sub] += 1


# --- Report ---
print("=" * 70)
print("nit savings analysis - git usage across AI agent sessions")
print("=" * 70)

grand_sessions = 0
grand_bash = 0
grand_git = 0
grand_output_chars = 0

for agent in ["claude", "codex", "cursor", "pi"]:
    r = results[agent]
    if r["sessions"] == 0:
        continue
    grand_sessions += r["sessions"]
    grand_bash += r["bash_total"]
    grand_git += r["git_total"]

    total_output = sum(sum(v) for v in r["git_output"].values())
    grand_output_chars += total_output

    print(f"\n--- {agent} ---")
    print(f"  sessions: {r['sessions']}")
    print(f"  bash commands: {r['bash_total']}")
    print(f"  git commands: {r['git_total']} ({r['git_total']/max(r['bash_total'],1)*100:.1f}% of bash)")
    print()

    for sub in git_subcommands:
        count = r["git_cmds"][sub]
        if count == 0:
            continue
        outputs = r["git_output"][sub]
        if outputs:
            avg = sum(outputs) / len(outputs)
            total = sum(outputs)
            print(f"  git {sub:10s} | {count:4d} calls | avg {avg:>7,.0f} chars ({avg/4:>6,.0f} tok) | total {total:>10,} chars ({total//4:>8,} tok)")
        else:
            print(f"  git {sub:10s} | {count:4d} calls | (no output captured)")

print()
print("=" * 70)
print(f"TOTALS across all agents:")
print(f"  sessions analyzed: {grand_sessions:,}")
print(f"  total bash commands: {grand_bash:,}")
print(f"  total git commands: {grand_git:,} ({grand_git/max(grand_bash,1)*100:.1f}% of bash)")
print(f"  total git output: {grand_output_chars:,} chars (~{grand_output_chars//4:,} tokens)")
print("=" * 70)
