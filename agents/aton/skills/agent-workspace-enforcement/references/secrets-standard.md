# Secrets Standard Reference

Encrypted secret management for all agent workspaces. Referenced by SKILL.md.

## Overview

Secrets are stored as AES-256-CBC encrypted JSON files in `$HERMES_HOME/.secrets/`.
All access goes through `scripts/secret.sh` — never read `.secrets/` files directly.

## File Structure

```
.secrets/
  .secret-key              Auto-generated encryption key (chmod 600)
  .<name>.json.enc         Encrypted secret files (chmod 600)
  .<name>.json             Plaintext (temporary, deleted after encrypt)
```

## Commands

```bash
bash tools/secret.sh get <name> [key]         # Get a value
bash tools/secret.sh list                      # List all secret names
bash tools/secret.sh set <name> <key> <value>  # Set/update a secret
bash tools/secret.sh has <name> [key]          # Check if exists
bash tools/secret.sh delete <name>             # Delete entirely
bash tools/secret.sh init                      # Re-generate encryption key
bash tools/secret.sh migrate                   # Convert plaintext → encrypted
```

## Examples

```bash
# Flat secrets
bash tools/secret.sh get neynar api_key
bash tools/secret.sh set github token "ghp_abc123"

# Nested secrets (dot notation)
bash tools/secret.sh set telegram bot.token "123456:ABC..."
bash tools/secret.sh set telegram bot.chat_id "-1001234"
bash tools/secret.sh get telegram bot.token

# Check existence
bash tools/secret.sh has neynar
bash tools/secret.sh has neynar api_key

# List all
bash tools/secret.sh list

# Delete
bash tools/secret.sh delete old_secret
```

## Secret Format

All secrets are JSON objects. Dot notation accesses nested keys:

```
# .neynar.json.enc (decrypted):
{
  "api_key": "NEYNAR_API_DOCS",
  "signer_uuid": "xxxxx-xxxxx"
}

# .telegram.json.enc (decrypted):
{
  "bot": {
    "token": "123456:ABC...",
    "chat_id": "-1001234"
  }
}
```

## Common Secret Names

| Name | Keys | Purpose |
|------|------|---------|
| `neynar` | `api_key`, `signer_uuid` | Farcaster API |
| `github` | `token` | GitHub PAT |
| `telegram` | `bot.token`, `bot.chat_id` | Telegram bot |
| `openai` | `api_key` | OpenAI API |
| `nous` | `api_key`, `portal_key` | Nous Research |
| `farcaster` | `fid`, `mnemonic`, `signer` | Farcaster agent |

## Rules

1. **ALWAYS** use `secret.sh` to read/write. NEVER `cat .secrets/.*` directly.
2. Secrets are `.json` format only. Use dot notation for nested keys.
3. The `.secret-key` file is auto-generated. Back it up separately.
4. `chmod 600` is allowed ONLY for `.secret-key` and `.json.enc` files.
5. `chmod 700` is NEVER allowed anywhere.
6. Run `secret.sh migrate` to convert any legacy plaintext secrets to encrypted.
7. Each agent has its own `.secrets/` — secrets are NOT shared between agents.

## Enforcement Checks

During workspace enforcement, verify:

```bash
# .secrets/ exists
[ -d "$HERMES_HOME/.secrets" ] || mkdir -p "$HERMES_HOME/.secrets"

# No plaintext .json left behind (should all be .json.enc after migration)
find "$HERMES_HOME/.secrets" -name "*.json" ! -name ".secret-key" -type f

# No chmod 700 on anything
find "$HERMES_HOME/.secrets" -type f -perm 700

# No world-readable secrets
find "$HERMES_HOME/.secrets" -type f -perm /o+r
```

## From Inside Containers

Secrets path inside containers: `/data/agents/<name>/.secrets/`

```bash
# From host
docker exec oc-aton bash tools/secret.sh get neynar api_key

# From inside container
bash $HERMES_HOME/tools/secret.sh get neynar api_key
# or
bash tools/secret.sh get neynar api_key  # if in $HERMES_HOME
```

## Troubleshooting

**"Secret 'X' not found"**
```bash
bash tools/secret.sh list    # See what's available
bash tools/secret.sh has X   # Check specific
```

**"ERROR: Key X not found in Y"**
The key path doesn't exist in the secret. List keys:
```bash
bash tools/secret.sh get Y    # Shows top-level keys
```

**Encryption key lost**
Must re-create all secrets. Run:
```bash
bash tools/secret.sh init
# Then re-set each secret
```

**Legacy plaintext secrets**
```bash
bash tools/secret.sh migrate   # Converts all .json → .json.enc
```
