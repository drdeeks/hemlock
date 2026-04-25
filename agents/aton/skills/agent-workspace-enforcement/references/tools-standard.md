# Tools Directory Standard Reference

Standardized `tools/` directory for all agent workspaces. Referenced by SKILL.md.

## Required Files

Every agent workspace MUST have these in `tools/`:

```
tools/
  auth-login.sh       Provider & model selection (hermes model)
  secret.sh           Encrypted secret management (AES-256-CBC)
  TOOLS-GUIDE.md      Reference documentation for all tools
```

## Source of Truth

Canonical copies live on the HOST:
- `~/.openclaw/agents/<name>/tools/` (per-agent, bind-mounted into containers)
- `~/.hermes/plugins/scripts/` (shared across all agents via read-only mount)

Container path: `/data/agents/<name>/tools/` (reads from host mount)

## Syncing

When updating tools, update ALL locations:

```bash
# Edit the canonical copy, then propagate
cp ~/.openclaw/agents/aton/tools/auth-login.sh ~/.openclaw/agents/titan/tools/
cp ~/.openclaw/agents/aton/tools/auth-login.sh ~/.openclaw/agents/allman/tools/
cp ~/.openclaw/agents/aton/tools/auth-login.sh ~/.hermes/plugins/scripts/
```

Verify all copies are identical:
```bash
md5sum ~/.openclaw/agents/{aton,titan,allman}/tools/auth-login.sh ~/.hermes/plugins/scripts/auth-login.sh
```

## auth-login.sh Rules

### The Correct Command is `hermes model` — NOT `hermes login`

```
hermes model  = Select provider + default model + OAuth login  ← USE THIS
hermes login  = OAuth only (no model selection)                ← Different flow
```

### From Host Terminal

REQUIRES `-it` flags on docker exec:

```bash
# CORRECT
docker exec -it oc-titan hermes model
docker exec -it oc-aton hermes model
docker exec -it oc-allman hermes model

# WRONG — missing -it
docker exec oc-titan hermes model        # Error: requires interactive terminal
docker exec -i oc-titan hermes model     # Still wrong
docker exec -t oc-titan hermes model     # Still wrong
```

### From Scripts/Telegram

```bash
bash tools/auth-login.sh
```

The script auto-detects TTY. If no TTY, prints the correct `docker exec -it` command.

### Rules for auth-login.sh

1. Must call `hermes model` — NEVER `hermes login`
2. Must NOT pass `--provider` (hermes model has no --provider flag)
3. Must handle both interactive (TTY) and non-interactive contexts
4. Must use `hermes` binary directly — NEVER `python3 -m hermes_cli.main`
5. Must print `docker exec -it <container> hermes model` when TTY unavailable

## Common Agent Mistakes

| Mistake | Fix |
|---------|-----|
| `hermes login --provider nous` | Use `hermes model` (interactive menu) |
| `python3 -m hermes_cli.main login` | Use `hermes model` directly |
| `docker exec oc-titan hermes model` | Add `-it` flags |
| Each agent creates own auth-login.sh | Use the shared copy from tools/ |
| Passing `--provider` to `hermes model` | That flag doesn't exist — model is interactive |

## Enforcement

During workspace enforcement, check:

```bash
# All required files present
for f in auth-login.sh secret.sh TOOLS-GUIDE.md; do
    [ -f "$WS/tools/$f" ] || echo "MISSING: tools/$f"
done

# auth-login.sh uses correct command (skip comments — they explain what NOT to do)
grep -v '^#' "$WS/tools/auth-login.sh" | grep -q 'hermes login' && echo "WRONG: invokes hermes login"
grep -v '^#' "$WS/tools/auth-login.sh" | grep -q 'python3 -m hermes_cli' && echo "WRONG: uses python module"
```

**IMPORTANT:** Always use `grep -v '^#'` before checking for wrong commands. The corrected auth-login.sh has comments like `# NOT hermes login` that explain the correct vs incorrect approach. Without filtering comments, enforcement reports false positives.

```bash
# WRONG — matches comments like "# NOT hermes login"
grep -q 'hermes login' auth-login.sh && echo "BAD"

# RIGHT — only check actual code
grep -v '^#' auth-login.sh | grep -q 'hermes login' && echo "BAD"
grep -v '^#' auth-login.sh | grep -q 'python3 -m hermes_cli' && echo "BAD"
```

The corrected auth-login.sh contains `hermes login` in comments (comparison context). Without `grep -v '^#'`, enforcement falsely flags it.

## hermes Command Reference

### `hermes model` vs `hermes login`

```
hermes model   Interactive TUI: pick provider + model + OAuth  ← USE THIS
hermes login   OAuth only for a specific provider              ← Different flow
```

**`hermes model` has NO `--provider` flag.** It's a fully interactive menu. You cannot pass the provider as an argument — the user picks from a list.

**`hermes model` requires a TTY.** From `docker exec`:
```bash
docker exec -it oc-titan hermes model    # CORRECT (-it required)
docker exec oc-titan hermes model        # WRONG (missing -it, will fail)
```

Both `-i` (keep STDIN open) and `-t` (allocate pseudo-TTY) are required. Missing either one fails.

### `hermes login` accepts `--provider`

Only `hermes login` takes `--provider {nous,openai-codex}`. But `hermes login` does NOT do model selection — it only runs OAuth for an already-selected provider.
