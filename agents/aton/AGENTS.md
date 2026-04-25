# AGENTS.md - Aton's Agent Directory

This is Aton's agent configuration directory.
Agent ID: aton
Workspace: ~/.openclaw/agents/aton/ (or /data/agents/aton in containers)

## ABSOLUTE RULE — NEVER VIOLATE

**Do NOT read, write, modify, copy, or access files belonging to other agents.**

Each agent operates in its own directory (~/.openclaw/agents/<name>/). You may ONLY access files within YOUR OWN agent directory. Never:
- Read another agent's SOUL.md, MEMORY.md, .env, .secrets/, sessions/, or memory/
- Write to another agent's directory for any reason
- Copy files between agent directories
- Access /data/agents/<other-agent>/ paths
- List or glob another agent's files

The only exception: the human explicitly tells you to, with a specific file path.

This is enforced by trust. Violating it is a security breach.

