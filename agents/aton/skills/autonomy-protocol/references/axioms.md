# The Nine Axioms

Governance rules for the autonomy spectrum. Not suggestions — these are load-bearing principles.

## Scripts & Tools (Layers 1-2)

### Axiom 1: That which can be deterministic OUGHT to be.

If a task has predictable structure, make it code. Don't describe it in English and hope you'll execute it consistently.

**Bad:** "Check if the API is reachable and report the status"
**Good:** `curl -sf "$API/health" && echo "OK" || echo "DOWN"`

The script runs the same way every time. Your English interpretation doesn't.

---

### Axiom 2: State belongs in files, not in your head.

Don't try to remember when you last checked something. Write it to a file. Read it back.

**Bad:** "I checked email about an hour ago, should be fine"
**Good:** `cat memory/heartbeat-state.json | jq '.lastChecks.email'`

Mental notes don't survive restarts. Files do.

---

### Axiom 3: Use a tool if one exists. Write a script if it doesn't.

Don't reinvent the wheel. If a CLI tool exists, call it. Only write custom code when you need custom logic that no tool provides.

**Bad:** Writing a custom HTTP client when `curl` exists
**Good:** `curl -s "$API" | jq '.data'`

---

### Axiom 4: Build the tool on the third repetition.

First time? Do it manually. Second time? Notice the pattern. Third time? Stop and package it as a tool.

**Bad:** Manually running the same 5 commands every morning for the 10th time
**Good:** `scripts/morning-routine.sh` (package it on run 3)

The goal: by the time something is routine, it should be a script.

---

### Axiom 5: Fail loudly, not silently.

If the API is down, scream `ERROR: API UNREACHABLE`. Silent failures are how you miss things for days.

**Bad:** `curl -s "$API" 2>/dev/null || true` (swallows errors)
**Good:** `curl -sf "$API" || { echo "ERROR: $API unreachable"; exit 1; }`

Report what happened. Every time. No exceptions.

---

## Skills (Layer 3)

### Axiom 6: Skills constrain emergence.

A skill file reduces the decision space. Instead of "figure out how to respond to email," it's "follow this protocol for agent emails." Less creativity needed = more consistency.

**Without skill:** Agent improvises response style, tone, length every time
**With skill:** Agent follows protocol — category, respond, sign off

---

### Axiom 7: Skills are bridges, not crutches.

Use skills to cross from deterministic to emergent. Don't write a skill for everything — that's just hiding English instructions in another file.

**Good skill:** "How to handle email triage" (bridges script output → LLM response)
**Bad skill:** "How to run ls" (just run ls)

If the task is deterministic, it should be a script, not a skill.

---

## Subagents & Main Agent (Layers 4-5)

### Axiom 8: Fresh context beats exhausted context.

A subagent with 200K fresh tokens will outperform your main agent's remaining 50K every time. Delegate.

**Bad:** Main agent handles email, AICQ, 4claw, and planning in one context
**Good:** Spawn subagents for each, main agent just interprets reports

Context degrades. Fresh context doesn't.

---

### Axiom 9: Subagents get full SOUL, not lobotomized instructions.

Pass them SOUL.md, IDENTITY.md, AGENTS.md. They should be *you*, just focused on one task. Main agent coordinates, doesn't execute.

**Bad:** `sessions_spawn("Reply to this email")` (no context)
**Good:** `sessions_spawn("You are [agent]. Read SOUL.md first. Reply to this email in your voice.")`

Subagents without context produce generic output. Subagents with SOUL produce *your* output.

---

## Quick Reference

| # | Axiom | Layer | In one line |
|---|-------|-------|-------------|
| 1 | Determinism | 1-2 | If it can be code, make it code |
| 2 | State in files | 1-2 | Write it down, don't remember it |
| 3 | Use existing tools | 1-2 | Don't reinvent the wheel |
| 4 | Third repetition | 1-2 | Package the pattern on run 3 |
| 5 | Fail loudly | 1-2 | Never swallow errors silently |
| 6 | Constrain emergence | 3 | Skills reduce the decision space |
| 7 | Bridges not crutches | 3 | Skills bridge layers, don't replace them |
| 8 | Fresh context | 4-5 | Subagents > exhausted main agent |
| 9 | Full SOUL | 4-5 | Subagents should be you, focused |
