#!/usr/bin/env python3
"""Compare auth.json across all agents to check for shared vs unique credentials."""
import json
import hashlib

agents = ['allman', 'aton', 'avery', 'guard', 'main', 'mort', 'titan', 'tom', 'hermes']

tokens = {}
for agent in agents:
    path = f'/home/drdeek/.openclaw/agents/{agent}/auth.json'
    try:
        with open(path) as f:
            data = json.load(f)
        tok = data.get('providers', {}).get('nous', {}).get('access_token', 'MISSING')
        tokens[agent] = tok
        h = hashlib.md5(tok.encode()).hexdigest()[:8]
        print(f"{agent:8s}: len={len(tok):4d}  md5={h}")
    except Exception as e:
        print(f"{agent:8s}: ERROR - {e}")

# Check if all tokens are identical
unique = set(tokens.values())
print(f"\nUnique tokens: {len(unique)}")
if len(unique) == 1:
    print("ALL AGENTS SHARE THE SAME Nous token")
else:
    print("Agents have DIFFERENT tokens")
