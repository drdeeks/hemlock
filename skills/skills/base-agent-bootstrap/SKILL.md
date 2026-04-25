---
name: base-agent-bootstrap
description: 'Complete end-to-end setup for a Base agent: builder code registration,
  ERC-8021 attribution (viem), Pinata IPFS account via AgentMail, and workspace secrets
  organization. Use when setting up a new agent on Base with onchain attribution.'
version: 1.0.0
metadata:
  hermes:
    tags:
    - base
    - builder-code
    - erc-8021
    - pinata
    - agentmail
    - onboarding
    related_skills:
    - registering-agent-base-dev
    - pinata-erc-8004
    - multi-agent-workspace-setup
author: openclaw
license: MIT
---
# Base Agent Bootstrap

End-to-end setup for a new agent on Base with builder code attribution, Pinata IPFS, and proper secrets management.

## Prerequisites

- A wallet for the agent (dedicated, not personal)
- Workspace under `~/hermes-agent/workspaces/<agent-id>/`

## Step 1: Register Builder Code

Use `curl` (NOT `urllib` — it gets 403 on `api.base.dev`):

```bash
curl -s -X POST "https://api.base.dev/v1/agents/builder-codes" \
  -H "Content-Type: application/json" \
  -d '{"wallet_address": "0xYOUR_WALLET"}'
```

Response: `{"builderCode":"bc_xxxxxxxx", "walletAddress":"0x..."}`

Save to `src/constants/builderCode.ts` and `builderCode.ts` at project root.

**Gotcha:** If the API returns 403, retry with `curl`. The `urllib` Python approach consistently fails.

## Step 2: Wire ERC-8021 Attribution (viem)

Install: `npm i ox viem`

Create `src/walletClient.ts`:

```typescript
import { createWalletClient, http } from "viem"
import { base } from "viem/chains"
import { privateKeyToAccount } from "viem/accounts"
import { Attribution } from "ox/erc8021"
import { BUILDER_CODE } from "./constants/builderCode"

const DATA_SUFFIX = Attribution.toDataSuffix({ codes: [BUILDER_CODE] })
const account = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`)

export const walletClient = createWalletClient({
  account,
  chain: base,
  transport: http(),
  dataSuffix: DATA_SUFFIX,
})
```

Every transaction via `walletClient` automatically carries the builder code.

## Step 3: Set Up Pinata via AgentMail

### 3a: Create AgentMail inbox

```python
# Requires python3.12 explicitly (hermes venv is 3.11)
python3.12 -c "
from agentmail import AgentMail
client = AgentMail(api_key='YOUR_AGENTMAIL_KEY')
inbox = client.inboxes.create(client_id='agent-<id>-pinata')
print(inbox.inbox_id)
"
```

### 3b: Sign up for Pinata

1. Navigate to `https://app.pinata.cloud/auth/signup`
2. Fill form with AgentMail inbox address
3. Check inbox for verification link via AgentMail API
4. **Open verification link immediately** (expires in 10 minutes)
5. Complete onboarding, select Free plan
6. Go to Developers > API Keys, copy JWT

**Gotcha:** Pinata rate-limits aggressively. Wait 60-120s between sign-in attempts.

### 3c: Verify JWT works

```bash
curl -s -X GET "https://api.pinata.cloud/data/testAuthentication" \
  -H "Authorization: Bearer YOUR_JWT"
```

### 3d: Get gateway URL

```bash
curl -s -X GET "https://api.pinata.cloud/v3/ipfs/gateways" \
  -H "Authorization: Bearer YOUR_JWT"
```

Domain is in `data.rows[0].domain` → full URL: `https://DOMAIN.mypinata.cloud`

## Step 4: Organize Secrets

Per multi-agent workspace conventions:

```
.secrets/                          # mode 700
├── .wallet                        # mode 600 — PRIVATE_KEY + WALLET_ADDRESS
├── .pinata-access                 # mode 600 — PINATA_JWT, API_KEY, API_SECRET, GATEWAY_URL
└── .agentmail-agent-<id>          # mode 600 — AGENTMAIL_API_KEY, INBOX
```

`.env` should only have a comment referencing how to source them:
```bash
# source .secrets/.pinata-access && source .secrets/.agentmail-agent-<id> && source .secrets/.wallet
```

## Step 5: Update agent.json

Update `builderCode` and `builder_code_enforcement` sections with the new code and wallet.

## Verification

- [ ] `builderCode.ts` exists with correct code
- [ ] `src/walletClient.ts` compiles
- [ ] Pinata JWT passes testAuthentication
- [ ] `.secrets/` has mode 700, files have mode 600
- [ ] `agent.json` has updated builder code
- [ ] Systemd service `WorkingDirectory` points to workspace

## Pitfalls

- **urllib vs curl**: `api.base.dev` returns 403 via Python urllib; always use curl
- **Python version**: hermes venv is 3.11, agentmail needs 3.12 — use `python3.12` explicitly
- **Rate limits**: Pinata sign-in is rate-limited; space attempts 60-120s apart
- **Verification expiry**: Email verification links expire in 10 minutes — act fast
- **Re-registration**: If `builderCode.ts` exists, do NOT re-register (generates new code, breaks existing one)

