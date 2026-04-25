---
name: session-logs
description: Search and analyze your own session logs (older/parent conversations) using jq.
metadata: { "openclaw": { "emoji": "📜", "requires": { "bins": ["jq", "rg"] } } }
---

# session-logs

Search your complete conversation history stored in session JSONL files. Use this when a user references older/parent conversations or asks what was said before.

## Trigger

Use this skill when the user asks about prior chats, parent conversations, or historical context that isn't in memory files.

## Location

Session logs live at: `~/.openclaw/agents/<agentId>/sessions/` (use the `agent=<id>` value from the system prompt Runtime line).

- **`sessions.json`** - Index mapping session keys to session IDs
- **`<session-id>.jsonl`** - Full conversation transcript per session

## Structure

Each `.jsonl` file contains messages with:

- `type`: "session" (metadata) or "message"
- `timestamp`: ISO timestamp
- `message.role`: "user", "assistant", or "toolResult"
- `message.content[]`: Text, thinking, or tool calls (filter `type=="text"` for human-readable content)
- `message.usage.cost.total`: Cost per response

## Common Queries

### List all sessions by date and size

```bash
for f in ~/.openclaw/agents/<agentId>/sessions/*.jsonl; do
  date=$(head -1 "$f" | jq -r '.timestamp' | cut -dT -f1)
  size=$(ls -lh "$f" | awk '{print $5}')
  echo "$date $size $(basename $f)"
done | sort -r
```

### Find sessions from a specific day

```bash
for f in ~/.openclaw/agents/<agentId>/sessions/*.jsonl; do
  head -1 "$f" | jq -r '.timestamp' | grep -q "2026-01-06" && echo "$f"
done
```

### Extract user messages from a session

```bash
jq -r 'select(.message.role == "user") | .message.content[]? | select(.type == "text") | .text' <session>.jsonl
```

### Search for keyword in assistant responses

```bash
jq -r 'select(.message.role == "assistant") | .message.content[]? | select(.type == "text") | .text' <session>.jsonl | rg -i "keyword"
```

### Get total cost for a session

```bash
jq -s '[.[] | .message.usage.cost.total // 0] | add' <session>.jsonl
```

### Daily cost summary

```bash
for f in ~/.openclaw/agents/<agentId>/sessions/*.jsonl; do
  date=$(head -1 "$f" | jq -r '.timestamp' | cut -dT -f1)
  cost=$(jq -s '[.[] | .message.usage.cost.total // 0] | add' "$f")
  echo "$date $cost"
done | awk '{a[$1]+=$2} END {for(d in a) print d, "$"a[d]}' | sort -r
```

### Count messages and tokens in a session

```bash
jq -s '{
  messages: length,
  user: [.[] | select(.message.role == "user")] | length,
  assistant: [.[] | select(.message.role == "assistant")] | length,
  first: .[0].timestamp,
  last: .[-1].timestamp
}' <session>.jsonl
```

### Tool usage breakdown

```bash
jq -r '.message.content[]? | select(.type == "toolCall") | .name' <session>.jsonl | sort | uniq -c | sort -rn
```

### Search across ALL sessions for a phrase

```bash
rg -l "phrase" ~/.openclaw/agents/<agentId>/sessions/*.jsonl
```

## Hermes CLI Session Database (state.db)

For messages sent via the CLI or gateway (not openclaw), session data lives in `~/.hermes/state.db` — a SQLite database with FTS5 search.

### Tables

- **`sessions`** — columns: `id`, `source`, `user_id`, `model`, `started_at`, `ended_at`, `title`, etc.
- **`messages`** — columns: `id`, `session_id`, `role`, `content`, `tool_call_id`, `tool_calls`, `tool_name`, `timestamp`, `reasoning`, etc.

### Common Queries

```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/home/ubuntu/.hermes/state.db')
c = conn.cursor()

# List recent sessions
c.execute('SELECT id, source, started_at, title FROM sessions ORDER BY started_at DESC LIMIT 10')
for r in c.fetchall(): print(r)

# Search user messages for keywords
c.execute(\"SELECT session_id, substr(content, 1, 300), timestamp FROM messages WHERE role='user' AND content LIKE '%keyword%' ORDER BY timestamp DESC LIMIT 10\")
for r in c.fetchall(): print(r[0], r[2], r[1][:150])

# Get all messages in a session
c.execute(\"SELECT role, substr(content, 1, 200), timestamp FROM messages WHERE session_id='SESSION_ID' ORDER BY timestamp DESC\")
for r in c.fetchall(): print(f'[{r[0]}] {r[1][:100]}')

conn.close()
"
```

### When to use which

- **state.db** — CLI/gateway sessions, user messages from Telegram bots, current active sessions
- **openclaw sessions** — older/parent conversations, openclaw agent sessions
- **session_search tool** — quick keyword search across both (LLM-summarized)

## Tips

- Sessions are append-only JSONL (one JSON object per line)
- Large sessions can be several MB - use `head`/`tail` for sampling
- The `sessions.json` index maps chat providers (discord, whatsapp, etc.) to session IDs
- Deleted sessions have `.deleted.<timestamp>` suffix
- state.db has a WAL file (`state.db-wal`) — always query while the process is running or copy the whole directory

## Fast text-only hint (low noise)

```bash
jq -r 'select(.type=="message") | .message.content[]? | select(.type=="text") | .text' ~/.openclaw/agents/<agentId>/sessions/<id>.jsonl | rg 'keyword'
```
