#!/usr/bin/env python3
"""PreToolUse budget gate. usage: gate.py <budget-dir>  (the hook event on stdin)
<budget-dir>/gate.json: the protected paths and command, the reads the main session keeps past the limit, the calls an
agent may end with. <budget-dir>/budgets/<session>.json: {"session_id", "start", "limit", "context_limit"}, written
only by the owner's `budget` command; absent: no limit. Refused at any spend: a call, other than Read, that names a
protected path or runs the protected command; a Workflow call whose script lacks budget-wrapper.js verbatim or calls
agent()/workflow() outside it; with a context cap, the main session's Agent and Workflow calls once its last message
is larger than the cap. Past the crossing (the first message at which spend since start reaches the limit): every
main-session call but the reads, and every call of an agent whose transcript starts at or after the crossing. A gate
error refuses Agent and Workflow and allows the rest."""
import glob, json, os, re, sys
KINDS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
CONTEXT = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
AGENT_MSG = ("this agent started after the limit was reached. Do not retry. End now: reply exactly BUDGET-REFUSED, "
             "or, if you must return structured output, return it with budget_refused set to true and every required field minimal.")


def spend(main, start, limit):
    sub = main[:-len(".jsonl")] + "/subagents"
    msgs, first = {}, {}
    for f in [main] + glob.glob(sub + "/**/agent-*.jsonl", recursive=True):
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = d.get("timestamp") or ""
            if ts and os.path.basename(f) not in first:
                first[os.path.basename(f)] = ts
            m = d.get("message") if isinstance(d.get("message"), dict) else {}
            u = m.get("usage")
            if not u or ts < start:
                continue
            tot = sum(u.get(k) or 0 for k in KINDS)
            if tot > msgs.get(m.get("id"), ("", 0))[1]:
                msgs[m.get("id")] = (ts, tot)
    cum, cross = 0, None
    for ts, tot in sorted(msgs.values()):
        cum += tot
        if cross is None and limit is not None and cum >= limit:
            cross = ts
    return cum, cross, first


def context(main):
    """The main session's context: the input of its latest message, cached or not."""
    last = ("", 0)
    for line in open(main, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        u = m.get("usage")
        if u and (d.get("timestamp") or "") >= last[0]:
            last = (d.get("timestamp") or "", sum(u.get(k) or 0 for k in CONTEXT))
    return last[1]


def protected(tool, inp, cfg):
    if tool == "Read":
        return None
    text = json.dumps(inp)
    for p in cfg["protected_paths"]:
        if p in text:
            return f"the call names {p}, which only the owner changes"
    cmd = inp.get("command", "") if isinstance(inp.get("command"), str) else ""
    if re.search(r"(^|[\s;&|()`$'\"])" + re.escape(cfg["protected_command"]) + r"(\s|$|[;&|)'\"])", cmd):
        return f"the call runs `{cfg['protected_command']}`, which only the owner runs"
    return None


def wrapper_refusal(inp, wrapper):
    s = inp.get("script")
    if s is None and inp.get("scriptPath"):
        try:
            s = open(inp["scriptPath"], encoding="utf-8").read()
        except OSError:
            s = None
    if s is None:
        return "the gate checks only a script passed inline or by a readable scriptPath"
    if wrapper not in s:
        return "the script lacks the budget wrapper (budget-wrapper.js, verbatim)"
    if re.search(r"\b(agent|workflow)\s*\(", s.replace(wrapper, "")):
        return "the script calls agent() or workflow() outside the wrapper's run()"
    return None


def decide(ev, b, cfg, wrapper):
    tool, aid, inp = ev.get("tool_name"), ev.get("agent_id"), ev.get("tool_input") or {}
    p = protected(tool, inp, cfg)
    if p:
        return "deny", f"BUDGET: {p}."
    if b is None:
        return "allow", ""
    if aid is None and tool in ("Agent", "Workflow") and b.get("context_limit"):
        size = context(ev["transcript_path"])
        if size > b["context_limit"]:
            return "deny", (f"BUDGET: the main context is {size} tokens, over this session's cap of {b['context_limit']}; "
                            "write the next brief and stop, so that a fresh session continues from it.")
    cum, cross, first = spend(ev["transcript_path"], b["start"], b.get("limit"))
    head = f"BUDGET: {cum} of {b.get('limit')} tokens spent"
    if tool == "Workflow":
        w = wrapper_refusal(inp, wrapper)
        if w:
            return "deny", f"{head}; {w}."
    if not cross:
        return "allow", ""
    if aid is None:
        if tool not in cfg["main_read"]:
            return "deny", f"{head}; past the limit the main session may only read; stop and wait for the owner."
        return "allow", ""
    if tool in cfg["agent_end"]:
        return "allow", ""
    start = first.get(f"agent-{aid}.jsonl")
    if start is None or start >= cross:
        return "deny", f"{head}; {AGENT_MSG}"
    return "allow", ""


def main(argv):
    d = argv[0]
    ev = json.load(sys.stdin)
    tool, sid = ev.get("tool_name"), ev.get("session_id") or ""
    bpath = os.path.join(d, "budgets", f"{os.path.basename(sid)}.json")
    try:
        cfg = json.load(open(os.path.join(d, "gate.json")))
        b = json.load(open(bpath)) if os.path.exists(bpath) else None
        verdict, why = decide(ev, b, cfg, open(os.path.join(d, "budget-wrapper.js"), encoding="utf-8").read().strip())
    except Exception as e:
        verdict = "deny" if tool in ("Agent", "Workflow") else "allow"
        why = f"BUDGET GATE ERROR {type(e).__name__}: {e}; Agent and Workflow are refused until the owner fixes it."
    if verdict == "deny":
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
