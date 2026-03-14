#!/usr/bin/env python3
"""Analyze: do agents read files after seeing diffs?

Scans Claude Code session transcripts to answer:
- After a git diff, how often does the agent immediately Read a file?
- Does this pattern suggest the agent already needs more context regardless
  of how many context lines the diff provides?

If agents almost always read the file after diffing anyway, then context
lines in the diff are redundant - the agent will get full context from
the file read regardless.

Usage: python3 experiments/read-after-diff.py
"""

import json
import glob
import os

HOME = os.path.expanduser("~")
transcripts = glob.glob(f"{HOME}/.claude/projects/*/*.jsonl")
transcripts += glob.glob(f"{HOME}/.claude/projects/*/subagents/*.jsonl")

total_diffs = 0
diff_then_read = 0
diff_then_edit = 0
diff_then_other = 0
diff_then_diff = 0

# Track sequences of tool calls
for path in transcripts:
    try:
        with open(path) as f:
            lines = f.readlines()
    except:
        continue

    # Extract ordered list of tool calls from this session
    tool_sequence = []

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

            if block.get("type") == "tool_use":
                name = block.get("name", "")
                inp = block.get("input", {})

                if name == "Bash":
                    cmd = inp.get("command", "")
                    if "git diff" in cmd or "git show" in cmd:
                        tool_sequence.append(("diff", cmd))
                    elif "git " in cmd:
                        tool_sequence.append(("git_other", cmd))
                    else:
                        tool_sequence.append(("bash", cmd))
                elif name == "Read":
                    tool_sequence.append(("read", inp.get("file_path", "")))
                elif name == "Edit":
                    tool_sequence.append(("edit", inp.get("file_path", "")))
                elif name == "Write":
                    tool_sequence.append(("write", inp.get("file_path", "")))
                elif name == "Grep":
                    tool_sequence.append(("grep", ""))
                elif name == "Glob":
                    tool_sequence.append(("glob", ""))
                else:
                    tool_sequence.append(("other", name))

    # Analyze: what happens after each diff?
    for i, (tool_type, _) in enumerate(tool_sequence):
        if tool_type == "diff":
            total_diffs += 1
            if i + 1 < len(tool_sequence):
                next_type = tool_sequence[i + 1][0]
                if next_type == "read":
                    diff_then_read += 1
                elif next_type == "edit":
                    diff_then_edit += 1
                elif next_type == "diff":
                    diff_then_diff += 1
                else:
                    diff_then_other += 1

# Also look at broader window: within 3 tool calls after a diff
diff_read_within_3 = 0
diff_edit_within_3 = 0

for path in transcripts:
    try:
        with open(path) as f:
            lines = f.readlines()
    except:
        continue

    tool_sequence = []
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
            if block.get("type") == "tool_use":
                name = block.get("name", "")
                inp = block.get("input", {})
                if name == "Bash":
                    cmd = inp.get("command", "")
                    if "git diff" in cmd or "git show" in cmd:
                        tool_sequence.append("diff")
                    else:
                        tool_sequence.append("bash")
                elif name == "Read":
                    tool_sequence.append("read")
                elif name == "Edit":
                    tool_sequence.append("edit")
                else:
                    tool_sequence.append("other")

    for i, t in enumerate(tool_sequence):
        if t == "diff":
            window = tool_sequence[i+1:i+4]
            if "read" in window:
                diff_read_within_3 += 1
            if "edit" in window:
                diff_edit_within_3 += 1


print("=" * 60)
print("what happens after an agent runs git diff / git show?")
print("=" * 60)
print()
print(f"total diff/show calls analyzed: {total_diffs}")
print()
print("immediately next tool call:")
if total_diffs > 0:
    print(f"  Read  (file read):    {diff_then_read:4d}  ({diff_then_read/total_diffs*100:.1f}%)")
    print(f"  Edit  (file edit):    {diff_then_edit:4d}  ({diff_then_edit/total_diffs*100:.1f}%)")
    print(f"  Diff  (another diff): {diff_then_diff:4d}  ({diff_then_diff/total_diffs*100:.1f}%)")
    print(f"  Other:                {diff_then_other:4d}  ({diff_then_other/total_diffs*100:.1f}%)")

print()
print("within 3 tool calls after diff:")
if total_diffs > 0:
    print(f"  includes Read:  {diff_read_within_3:4d}  ({diff_read_within_3/total_diffs*100:.1f}%)")
    print(f"  includes Edit:  {diff_edit_within_3:4d}  ({diff_edit_within_3/total_diffs*100:.1f}%)")

print()
print("interpretation:")
if total_diffs > 0:
    read_pct = diff_then_read / total_diffs * 100
    if read_pct > 50:
        print("  agents read files after diffs most of the time.")
        print("  context lines in diffs are mostly redundant -")
        print("  the agent gets full file context from Read anyway.")
        print("  -> U0 would be safe, saving the most tokens.")
    elif read_pct > 25:
        print("  agents sometimes read files after diffs.")
        print("  context lines provide some value for the cases")
        print("  where the agent acts on the diff without reading.")
        print("  -> U1 is a reasonable compromise.")
    else:
        print("  agents rarely read files after diffs.")
        print("  the diff context lines are the primary source of")
        print("  surrounding code context for the agent.")
        print("  -> U3 (or at least U1) is important to keep.")
