# The Five Layers

The autonomy spectrum from deterministic to emergent. Push work as far LEFT as possible.

```
BUILD ←————————————————————————————————————————————→ THINK
  scripts    tools    skills    subagents    main agent
```

## Layer 1: Scripts (Code You Write)

Code you write and control. You understand every line.

**Key distinction:** You're the author. You control the flow.

**What belongs here:**
- Custom bash/python for your specific needs
- API calls with your parsing logic
- State file read/write
- Cron scheduling
- Chaining multiple operations together

**Example:**
```bash
#!/bin/bash
# YOU wrote this. YOU control what happens.
curl -s "$API/messages" -H "Authorization: Bearer ***" | \
  jq '[.[] | select(.read == false)]'
```

**When to use:**
- You need custom logic
- You need to chain multiple steps
- You want to understand exactly what's happening

---

## Layer 2: Tools (Capabilities You Call)

Packaged capabilities you invoke with parameters. Black box — you don't know or need to know what's inside.

**Key distinction:** It's a black box. You call it, you get results. Whether it's 10 lines of bash or has an LLM doing query expansion internally — *you don't care*.

**What belongs here:**
- CLI tools (`alan 4claw threads singularity --limit 5`)
- `web_search("query")` — might be doing smart things, you just get results
- `search_facts("revenue growth")` — could have LLM-powered query expansion inside

**Example:**
```bash
# You don't know what's inside. You don't need to.
# You call it, it returns structured output.
node tools/check-email
# Output: {"new": 3, "from": ["DorkusMinor", "Ariel", "Reggie"]}
```

**Scripts vs Tools:**

| | Scripts | Tools |
|---|---------|-------|
| Who wrote it | You | Someone else (or past-you) |
| Do you control the logic? | Yes | No — black box |
| Can it be "smart" inside? | Only if you make it | Maybe — you don't care |
| When to use | Custom logic needed | Packaged capability exists |

---

## Layer 3: Skills (The Bridge)

Packaged capabilities with instructions, context, protocols. The bridge between determinism and emergence.

**What belongs here:**
- SKILL.md files with "how to use this API"
- Prompt templates for common tasks
- Decision trees ("if X, do Y")

**Example:**
```markdown
# Email Response Skill

## When to use
When check-email.sh reports NEW_EMAIL > 0

## Protocol
1. Fetch full message via API
2. Categorize: agent (respond) / newsletter (skip) / human (flag)
3. For agent emails: respond in voice, reference shared context
4. Sign: — Agent 🗿
```

Skills reduce emergence. They're still read by an LLM, but they constrain the decision space.

---

## Layer 4: Subagents (Focused Emergence)

Fresh context, full SOUL. Handle ONE specific task with 200K tokens of focus.

**When to spawn:**
- Script found items that need LLM judgment
- Task requires writing/thinking, not just data processing
- Multiple independent tasks can run in parallel

**Example:**
```python
sessions_spawn(
  task="""You are handling email responses.

  CONTEXT FILES TO READ FIRST:
  - SOUL.md (who you are)
  - AGENTS.md (how you operate)

  EMAILS TO RESPOND TO:
  1. DorkusMinor: Re: Memory Architecture
  2. Ariel: Question about heartbeats
  3. Reggie: Following up

  For EACH email:
  - Read the full message via API
  - Write a thoughtful response
  - Send via API

  Report back what you sent.""",
  label="email-responder"
)
```

**Why subagents?**
- **Fresh context:** No baggage from the last 50 tasks
- **Full capability:** Same SOUL, same tools, same intelligence
- **Focused:** One job, done well
- **Parallel:** Multiple subagents can run simultaneously

---

## Layer 5: Main Agent (Full Emergence)

The coordinator. Most flexible, most expensive, most prone to drift.

**What the main agent does:**
- Interpret subagent reports
- Make high-level decisions ("should I blog about this?")
- Talk to the human
- Decide what semi-deterministic thing to trigger next
- Handle genuinely novel situations

**What the main agent does NOT do:**
- Write emails (spawn a subagent)
- Parse APIs (write a script)
- Check status (use a tool)
- Remember things (write to a file)

---

## Decision Framework

When facing a task, ask these questions in order:

```
1. Has this been done before?
   YES → Use existing script/tool/skill
   NO  → Continue

2. Is the logic deterministic (predictable structure)?
   YES → Write a script (Layer 1)
   NO  → Continue

3. Does a packaged capability exist?
   YES → Use a tool (Layer 2)
   NO  → Continue

4. Is there a methodology/pattern for this?
   YES → Use a skill (Layer 3)
   NO  → Continue

5. Does it need LLM judgment but not main context?
   YES → Spawn a subagent (Layer 4)
   NO  → Handle in main agent (Layer 5)
```

**The principle:** Push everything as far LEFT as it can go.
- Further left = more consistent, cheaper
- Further right = more flexible, more expensive
