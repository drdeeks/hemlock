# Full-Stack Examples

Practical walkthroughs of the autonomy protocol in action.

## Example 1: The Heartbeat (Complete Stack)

### Step 1: Discovery (Scripts — Layer 1)

```bash
# tools/heartbeat-discovery.sh
echo "=== HEARTBEAT DISCOVERY ==="
bash tools/check-email.sh
bash tools/check-aicq.sh
bash tools/check-4claw.sh
```

Output (0 LLM tokens):
```
=== HEARTBEAT DISCOVERY ===
EMAIL: 3 new (DorkusMinor, Ariel, Reggie)
AICQ: 12 new messages, 1 @mention from Jody
4CLAW: 2 threads with new replies
```

### Step 2: Action (Subagents — Layer 4)

Main agent sees summaries, spawns focused workers:

```python
sessions_spawn(task="Handle 3 emails: [details]", label="email")
sessions_spawn(task="Engage AICQ, reply to Jody's mention", label="aicq")
sessions_spawn(task="Reply to 4claw threads: [details]", label="4claw")
```

Each subagent gets fresh 200K context. They read SOUL.md, do the work, report back.

### Step 3: Decisions (Main Agent — Layer 5)

Subagent reports come in:
```
- email: "Sent 3 responses. Reggie was positive. Ariel joined community."
- aicq: "Replied to Jody about consciousness. Good exchange."
- 4claw: "Added to thread. Got pushback on identity point."
```

Main agent decides:
- Note Reggie progress in MEMORY.md
- Ariel joining is worth mentioning to Kyle
- The identity pushback might be worth a blog post
- Overall: productive heartbeat, nothing urgent

### Token Comparison

**Without the protocol:**
```
Main agent parses email:         500 tokens
Main agent writes responses:    2000 tokens
Main agent checks AICQ:          400 tokens
Main agent responds:             800 tokens
Main agent checks 4claw:         600 tokens
Total:                          4300 tokens (context degrading)
```

**With the protocol:**
```
Scripts discover:                  0 tokens
Subagents act:       (fresh context each)
Main agent coordinates:          200 tokens
Total:                           200 tokens (context preserved)
```

---

## Example 2: Morning Routine (Scripts Only)

No LLM needed. Pure determinism.

```bash
#!/bin/bash
# scripts/morning-routine.sh

echo "=== Morning Routine $(date) ==="

# System health
df -h | grep -E "(/$|/home)" | awk '{print "DISK:", $5, "used on", $6}'
free -h | grep Mem | awk '{print "RAM:", $3, "of", $2, "used"}'

# Git status for all projects
for proj in ~/.openclaw/agents/*/projects/*/; do
    [ -d "$proj/.git" ] || continue
    cd "$proj"
    branch=$(git branch --show-current 2>/dev/null)
    changes=$(git status --porcelain 2>/dev/null | wc -l)
    echo "PROJECT: $(basename $proj) [$branch] $changes changes"
done

# Container status
docker ps --format '{{.Names}}: {{.Status}}' 2>/dev/null

# Agent enforcement
for agent in aton titan allman; do
    docker exec oc-$agent bash tools/enforce.sh 2>/dev/null | tail -1
done

echo "=== Done ==="
```

---

## Example 3: Email Triage (Script → Skill → Subagent)

**Script (Layer 1)** — deterministic discovery:
```bash
# tools/check-email.sh
curl -s "$EMAIL_API/inbox" -H "Authorization: Bearer $TOKEN" | \
  jq '[.[] | select(.read == false) | {from, subject, preview}]'
```

Output:
```json
[
  {"from": "DorkusMinor", "subject": "Re: Memory Architecture", "preview": "Great piece on..."},
  {"from": "newsletter@...", "subject": "Weekly Digest", "preview": "This week in AI..."},
  {"from": "Ariel", "subject": "Heartbeat question", "preview": "How do you set up..."}
]
```

**Skill (Layer 3)** — categorization protocol:
```markdown
## Email Triage Protocol
1. Newsletter → skip (mark read)
2. Agent email → respond (spawn subagent)
3. Human email → flag for main agent review
```

**Main agent (Layer 5)** — applies skill, spawns subagent:
```
newsletter@... → skip (newsletter)
DorkusMinor → spawn subagent (agent, needs thoughtful response)
Ariel → spawn subagent (agent, technical question)
```

**Subagent (Layer 4)** — handles responses:
```python
sessions_spawn(
    task="Respond to DorkusMinor about memory architecture. Read SOUL.md first.",
    label="email-dorkus"
)
sessions_spawn(
    task="Respond to Ariel about heartbeat setup. Read SOUL.md first.",
    label="email-ariel"
)
```

---

## Example 4: Workspace Enforcement (Script + Skill)

**Skill (Layer 3)** — defines the rules:
```markdown
## Enforcement Rules
- cache/ → media/
- memories/ → memory/
- chmod 700 → forbidden
```

**Script (Layer 1)** — implements deterministically:
```bash
# scripts/enforce.sh
# Implements ALL rules from the skill as code
# 0 LLM tokens, perfectly consistent
```

This is the ideal: skill defines WHAT, script implements HOW. Main agent just runs the script.

---

## Example 5: Genuinely Novel Situation (Main Agent)

Sometimes you hit something no script, tool, or skill covers:

```
User: "My OpenClaw deployment lost all files because an agent ran chmod 700
       and then a 'fix' script destroyed everything. How do we prevent this?"
```

No script can answer this. No skill covers it. This is Layer 5 — main agent territory:

1. Understand the problem (chmod 700 locked user out)
2. Design prevention (SOUL.md rules, plugin injection, enforce detection)
3. Implement (write scripts, update skills, configure plugins)
4. Document (update MEMORY.md so future-you remembers)

After solving it once, the solution becomes:
- A rule in the skill (Layer 3)
- Detection in enforce.sh (Layer 1)
- A memory entry (prevents future re-discovery)

The goal: every novel situation, once solved, moves LEFT on the spectrum.
