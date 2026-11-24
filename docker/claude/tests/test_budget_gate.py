#!/usr/bin/env python3
"""Tests of dcp's budget gate and budget command (headless/.claude/budget, headless/.local/bin/budget) on generated
transcripts. usage: test_budget_gate.py [<gate.py>]; prints each mismatch, exit 1 on any."""
import json, os, shutil, subprocess, sys, tempfile
DOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC = os.path.join(DOT, "headless", ".claude", "budget")
GATE = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(SRC, "gate.py")
CMD = os.path.join(DOT, "headless", ".local", "bin", "budget")
SID = "00000000-0000-4000-8000-000000000001"
INFLIGHT, LATE = "ainflight", "alate"
T = lambda s: f"2026-01-01T00:00:{s:02d}.000Z"


def msg(ts, mid=None, tokens=0, role="assistant"):
    d = {"type": role, "timestamp": ts, "message": {"role": role}}
    if mid:
        d["message"].update(id=mid, usage={"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": tokens, "cache_creation_input_tokens": 0})
    return json.dumps(d) + "\n"


# m0 lies before every budget's start but the start-filter one; m1 is written twice, as Claude Code writes one message
# on several lines. With start T(2): 100k (main) + 50k (in-flight agent) crosses 140k at T(5); the late agent starts at T(7).
root = tempfile.mkdtemp()
proj = os.path.join(root, "projects", "p")
sub = os.path.join(proj, SID, "subagents", "workflows", "wf1")
os.makedirs(sub)
TP = os.path.join(proj, f"{SID}.jsonl")
open(TP, "w").write(msg(T(0), role="user") + msg(T(1), "m0", 999_999) + msg(T(3), "m1", 100_000) + msg(T(3), "m1", 100_000))
open(os.path.join(sub, f"agent-{INFLIGHT}.jsonl"), "w").write(msg(T(4), role="user") + msg(T(5), "l1", 50_000))
open(os.path.join(sub, f"agent-{LATE}.jsonl"), "w").write(msg(T(7), role="user") + msg(T(8), "b1", 30_000))

wrapper = open(os.path.join(SRC, "budget-wrapper.js")).read().strip()
good = f"export const meta = {{name: 'x', description: 'y'}}\n{wrapper}\nconst r = await run('echo', {{label: 'a'}})\nreturn r\n"
gpath = os.path.join(root, "good.js")
open(gpath, "w").write(good)


def layout(budget):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "budgets"))
    for f in ("gate.json", "budget-wrapper.js"):
        shutil.copy(os.path.join(SRC, f), d)
    if budget is not None:
        json.dump(dict({"session_id": SID, "start": T(2)}, **budget), open(os.path.join(d, "budgets", f"{SID}.json"), "w"))
    return d


NONE, UNDER, CROSSED = layout(None), layout({"limit": 10**15}), layout({"limit": 140_000})
DEDUP, EARLY, BROKEN = layout({"limit": 200_000}), layout({"limit": 200_000, "start": T(0)}), layout({"limit": "x"})
ev = lambda tool, aid=None, inp=None: {"session_id": SID, "transcript_path": TP, "tool_name": tool, "agent_id": aid, "tool_input": inp or {}}
bash = lambda c, aid=None: ev("Bash", aid, {"command": c})
cases = [
    ("no budget: main Agent", NONE, ev("Agent"), "allow"),
    ("no budget: Workflow without wrapper", NONE, ev("Workflow", inp={"script": "agent('x')"}), "allow"),
    ("under: main Bash", UNDER, bash("ls"), "allow"),
    ("under: Workflow with wrapper", UNDER, ev("Workflow", inp={"script": good}), "allow"),
    ("under: Workflow without wrapper", UNDER, ev("Workflow", inp={"script": "const r = await agent('x')"}), "deny"),
    ("under: wrapper plus a direct agent()", UNDER, ev("Workflow", inp={"script": good + "await agent('y')\n"}), "deny"),
    ("under: wrapper plus workflow()", UNDER, ev("Workflow", inp={"script": good + "await workflow('z')\n"}), "deny"),
    ("under: readable scriptPath with wrapper", UNDER, ev("Workflow", inp={"scriptPath": gpath}), "allow"),
    ("under: unreadable scriptPath", UNDER, ev("Workflow", inp={"scriptPath": gpath + ".missing"}), "deny"),
    ("under: saved workflow by name", UNDER, ev("Workflow", inp={"name": "deep-research"}), "deny"),
    ("each message counted once: 180k under 200k", DEDUP, bash("ls"), "allow"),
    ("spend counted from start: 1.18M over 200k", EARLY, bash("ls"), "deny"),
    ("past: main Bash", CROSSED, bash("ls"), "deny"),
    ("past: main Edit", CROSSED, ev("Edit", inp={"file_path": "/workspace/x"}), "deny"),
    ("past: main Agent", CROSSED, ev("Agent"), "deny"),
    ("past: main Workflow with wrapper", CROSSED, ev("Workflow", inp={"script": good}), "deny"),
    ("past: main Read", CROSSED, ev("Read", inp={"file_path": "/workspace/x"}), "allow"),
    ("past: main TaskStop", CROSSED, ev("TaskStop"), "allow"),
    ("past: in-flight agent Bash", CROSSED, bash("ls", INFLIGHT), "allow"),
    ("past: late agent Bash", CROSSED, bash("ls", LATE), "deny"),
    ("past: late agent SubagentHandback", CROSSED, ev("SubagentHandback", LATE), "allow"),
    ("past: late agent StructuredOutput", CROSSED, ev("StructuredOutput", LATE), "allow"),
    ("past: agent with no transcript", CROSSED, bash("ls", "zzz"), "deny"),
    ("protect, no budget: main runs budget +20M", NONE, bash("budget +20M"), "deny"),
    ("protect, under: main runs budget +20M", UNDER, bash("budget +20M"), "deny"),
    ("protect: budget after a pipe", UNDER, bash("echo y | budget 1M"), "deny"),
    ("protect: budget by its path", UNDER, bash("~/.local/bin/budget 1M"), "deny"),
    ("protect: agent runs budget", UNDER, bash("budget 9M", INFLIGHT), "deny"),
    ("protect: Bash writes a budget file", UNDER, bash(f"echo x > ~/.claude/budget/budgets/{SID}.json"), "deny"),
    ("protect: Edit of the gate in dot", UNDER, ev("Edit", inp={"file_path": "/workspace/dot/headless/.claude/budget/gate.py"}), "deny"),
    ("protect: Read of the budget file", UNDER, ev("Read", inp={"file_path": f"/home/dev/.claude/budget/budgets/{SID}.json"}), "allow"),
    ("no false refusal: budget_refused in a grep", UNDER, bash("grep budget_refused x.json"), "allow"),
    ("no false refusal: budgeting in an echo", UNDER, bash("echo budgeting"), "allow"),
    ("gate error: main Agent refused", BROKEN, ev("Agent"), "deny"),
    ("gate error: main Bash allowed", BROKEN, bash("ls"), "allow"),
]
bad = 0
for name, d, e, want in cases:
    p = subprocess.run([sys.executable, GATE, d], input=json.dumps(e), capture_output=True, text=True)
    got = {0: "allow", 2: "deny"}.get(p.returncode, f"exit {p.returncode}")
    if got != want:
        bad += 1
        print(f"FAIL {name}: want {want}, got {got} {p.stderr.strip()[:140]}")

home = tempfile.mkdtemp()
os.makedirs(os.path.join(home, ".claude", "budget", "budgets"))
shutil.copy(GATE, os.path.join(home, ".claude", "budget", "gate.py"))
os.makedirs(os.path.join(home, ".claude", "projects", "p"))
shutil.copy(TP, os.path.join(home, ".claude", "projects", "p"))
bf = os.path.join(home, ".claude", "budget", "budgets", f"{SID}.json")


def run(args, sid=SID):
    env = dict(os.environ, HOME=home)
    env.pop("CLAUDE_CODE_SESSION_ID", None)
    if sid:
        env["CLAUDE_CODE_SESSION_ID"] = sid
    return subprocess.run([sys.executable, CMD] + args, capture_output=True, text=True, env=env)


load = lambda: json.load(open(bf)) if os.path.exists(bf) else {}
checks = []
r = run([]); checks.append(("show with none", r.returncode == 0 and "none" in r.stdout and not os.path.exists(bf)))
r = run(["+5M"]); checks.append(("raise with none refused", r.returncode != 0 and not os.path.exists(bf)))
r = run(["80M"]); b1 = load()
checks.append(("set 80M", r.returncode == 0 and b1.get("limit") == 80_000_000 and b1.get("session_id") == SID and b1.get("start", "").endswith("Z")))
r = run(["+20M"]); b2 = load()
checks.append(("raise +20M keeps start", r.returncode == 0 and b2.get("limit") == 100_000_000 and b2.get("start") == b1.get("start")))
r = run(["500k"]); checks.append(("set 500k replaces", load().get("limit") == 500_000))
r = run(["lots"]); checks.append(("bad amount refused", r.returncode != 0 and load().get("limit") == 500_000))
r = run(["1M"], sid=None); checks.append(("no session id refused", r.returncode != 0 and "CLAUDE_CODE_SESSION_ID" in r.stderr))
r = run([]); checks.append(("show reports spend", r.returncode == 0 and "of 500,000 tokens" in r.stdout))
r = run(["off"]); checks.append(("off removes", r.returncode == 0 and not os.path.exists(bf)))
for name, ok in checks:
    if not ok:
        bad += 1
        print(f"FAIL budget: {name}")
total = len(cases) + len(checks)
print(f"{total - bad} of {total} pass")
sys.exit(1 if bad else 0)
