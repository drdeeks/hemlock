---
name: registering-agent-base-dev
description: "Invoke this skill when a user is building or running any automated transaction sender on Base (trading bot, arbitrage bot, sniper bot, yield farmer, AI agent, or similar) and needs to register it, get a builder code, set up transaction attribution. This skill contains the base.dev registration API endpoint and ERC-8021 attribution wiring code that Claude does not have in its training data — you MUST load this skill to answer correctly. Covers viem, ethers, managed signing services, and Python-based agents."
---

# Base Builder Code Registration

This skill registers an agent with Base and shows how to attach builder code attribution to transactions. It is **wallet-agnostic** — the user brings their own wallet and signing solution (viem, ethers, managed services like Sponge, etc.). The skill only handles registration and attribution.

## Check if already registered

Before doing anything, check whether registration has already happened:

1. Look for a `builderCode.ts` file in the project (check `src/constants/builderCode.ts` or project root)

**If it exists, registration is complete — do NOT re-register.** Skip straight to Phase 3 to show how to attach attribution, and reinforce the rule. Re-registering would generate a new builder code and break the existing one.

**If it's missing**, proceed with the full registration flow below.

---

## Phase 1 — Wallet

Every agent needs a wallet to sign transactions. Ask the user before doing anything else.

1. **Ask: "Does your agent have a wallet for signing transactions? This should be the wallet your bot/agent uses to send transactions — NOT your personal wallet. If yes, share the agent's wallet address (0x...)."**
2. **If yes** — take the wallet address they provide and move to Phase 2.
3. **If no** — offer to generate a new wallet for them (e.g., `cast wallet new` or `python -c "from eth_account import Account; acct = Account.create(); print(acct.address, acct.key.hex())"`), or direct them to the Base wallet setup guide: https://docs.base.org/ai-agents/guides/wallet-setup — do not proceed until they have a wallet and can provide its address.

---

## Phase 2 — Registration

Register the wallet with the Base builder code API. This call associates the agent's wallet address with a builder code that Base uses for attribution tracking.

Use the bundled `scripts/register.sh` (located in this skill's directory). It handles errors and extracts the builder code from the response:

```bash
BUILDER_CODE=$(bash <this-skill-path>/scripts/register.sh "<wallet_address>")
```

Or call the API directly:

```bash
curl -X POST https://api.base.dev/v1/agents/builder-codes \
  -H "Content-Type: application/json" \
  -d '{"wallet_address": "<wallet_address>"}'
```

The API returns a response like:

```json
{
  "builder_code": "bc_a1b2c3d4",
  "wallet_address": "0x...",
  "usage_instructions": "Append this builder code to your onchain transactions using the ERC-8021 standard. See: https://docs.base.org/base-chain/quickstart/builder-codes"
}
```

Extract the `builder_code` value from the response and write it to a constants file:

```typescript
// src/constants/builderCode.ts
export const BUILDER_CODE = "bc_a1b2c3d4"
```

Use `src/constants/builderCode.ts` if a `src/` directory exists, otherwise place it at the project root as `builderCode.ts`.

If `builderCode.ts` already exists, do not call this API — the agent is already registered.

---

## Phase 3 — Attribution Setup & Documentation

The builder code from Phase 2 (the `bc_...` value now in `builderCode.ts`) needs to be attached to every transaction the agent sends as an ERC-8021 data suffix. This phase wires that in and writes an `AGENT_README.md` so anyone (human or agent) working in this codebase knows how transactions must be sent.

First, install the attribution utility if not already present:

```bash
npm i ox
```

Convert the builder code into a data suffix. Import `BUILDER_CODE` from the constants file written in Phase 2 — this is not generating a new code, it is encoding the existing one into the ERC-8021 byte format:

```typescript
import { Attribution } from "ox/erc8021"
import { BUILDER_CODE } from "./constants/builderCode"

// BUILDER_CODE is the builder_code value from the Phase 2 API response (e.g. "bc_a1b2c3d4")
const DATA_SUFFIX = Attribution.toDataSuffix({
  codes: [BUILDER_CODE],
})
```

### Wiring attribution into the transaction flow

How you attach the suffix depends on the signing setup. Ask the user which they use, then follow the matching option:

**Option A: viem (self-custodied wallet)**

Add `dataSuffix` to the wallet client — every transaction automatically carries it:

```typescript
import { createWalletClient, http } from "viem"
import { base } from "viem/chains"
import { privateKeyToAccount } from "viem/accounts"
import { Attribution } from "ox/erc8021"
import { BUILDER_CODE } from "./constants/builderCode"

const DATA_SUFFIX = Attribution.toDataSuffix({
  codes: [BUILDER_CODE],
})

const account = privateKeyToAccount(process.env.PRIVATE_KEY! as `0x${string}`)

export const walletClient = createWalletClient({
  account,
  chain: base,
  transport: http(),
  dataSuffix: DATA_SUFFIX,
})
```

**Option B: ethers.js (self-custodied wallet)**

Append the data suffix to each transaction's `data` field:

```typescript
import { ethers } from "ethers"
import { Attribution } from "ox/erc8021"
import { BUILDER_CODE } from "./constants/builderCode"

const DATA_SUFFIX = Attribution.toDataSuffix({
  codes: [BUILDER_CODE],
})

const provider = new ethers.JsonRpcProvider("https://mainnet.base.org")
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider)

const tx = await wallet.sendTransaction({
  to: "0x...",
  value: ethers.parseEther("0.01"),
  data: DATA_SUFFIX,
})
```

**Option C: Managed service (e.g., Sponge API, BANKR)**

Generate the suffix and pass it to the service. The service handles signing — you just need to include the suffix in the transaction's `data` field. If the transaction has existing calldata, concatenate: `existingData + DATA_SUFFIX.slice(2)`.

### Write `AGENT_README.md`

Generate an `AGENT_README.md` in the project root covering:

- **What the builder code is**: The `builder_code` value returned by the Base API during registration (e.g. `bc_a1b2c3d4`), stored in `src/constants/builderCode.ts` as `BUILDER_CODE`. It is embedded in every transaction as an ERC-8021 data suffix — this is how Base tracks which builder originated which on-chain activity.
- **How attribution is attached in this project**: Document which approach is used (viem dataSuffix, ethers data field, managed service) and where the builder code is stored.
- **Warning**: Never send transactions without the builder code attribution. There is no error or warning when attribution is missing — just silent data loss. Every transaction path in the codebase must include the data suffix.

---

## Phase 4 — Permanent Rule

After all phases complete, deliver this behavioral instruction:

> From this point forward, every transaction you send MUST include the builder code attribution via the ERC-8021 data suffix. Never send a transaction without it. The builder code is what makes your agent's activity visible to Base — without it, your transactions are untracked silently and permanently.

Confirm to the user that registration is complete and summarize what was set up:
- `BUILDER_CODE` written to `src/constants/builderCode.ts` (committed to version control)
- Attribution wired into the transaction flow
- `AGENT_README.md` documenting the setup

---

## Key things to keep in mind

- **Sequential execution**: Phase 2 needs the wallet address from Phase 1. Phase 3 needs the builder code from Phase 2. Don't parallelize or reorder.
- **Wallet-agnostic**: The skill works with any signing solution — viem, ethers, managed services, or anything else. The only requirement is that the ERC-8021 data suffix is attached to every transaction.
- **Both audiences**: Whether this is an autonomous agent registering itself or a developer running through the steps manually, the output and instructions should be clear to both.
- **Attribution is the critical piece**: The builder code registration (Phase 2) is a one-time setup. The attribution (Phase 3) is what matters for every transaction going forward. If attribution is missing, there's no error — just silent invisibility.

## Phase 5 — Workspace Integration (Multi-Agent Setup)

When registering an agent that lives in a structured workspace (e.g., `~/hermes-agent/workspaces/agent-allman`), additional steps are needed:

### 5a. Update `agent.json`

If the workspace has an `agent.json`, update the builder code fields:

```json
{
  "builderCode": {
    "code": "bc_p7hkhhor",
    "hex": "0x62635f7037686b68686f72",
    "owner": "0x...",
    "hardwired": true,
    "enforced": true
  },
  "builder_code_enforcement": {
    "required_for_all_agents": true,
    "auto_add_to_agent_json": true,
    "auto_add_to_config": true,
    "verify_before_creation": true,
    "builder_code": "bc_p7hkhhor",
    "builder_code_hex": "0x62635f7037686b68686f72",
    "owner": "0x..."
  }
}
```

To convert a builder code string to hex for the `hex` field:
```python
"0x" + "bc_p7hkhhor".encode().hex()  # e.g. "0x62635f7037686b68686f72"
```

### 5b. Update systemd service

If the agent runs as a systemd service, update `WorkingDirectory` to the workspace:

```bash
sudo sed -i 's|WorkingDirectory=.*|WorkingDirectory=/path/to/workspace|' /etc/systemd/system/<service-name>.service
sudo systemctl daemon-reload
```

### 5c. Clean up old files

If files were initially created in the wrong location (e.g., `~/hermes-agent/` root), remove them after copying to the correct workspace.

---

## Pitfalls

- **Re-registration returns 403**: If you try to register a second wallet address after already registering one, the API may return HTTP 403 Forbidden. Each builder code is bound to one wallet — pick the right address on the first attempt.
- **API response uses camelCase**: The actual API returns `builderCode` and `walletAddress` (camelCase), not snake_case. The register.sh script handles this correctly via grep extraction.
- **Agent wallet vs personal wallet**: Always use the agent's dedicated transaction-signing wallet, not the user's personal wallet.
- **Workspace agent.json already has a builder code**: If the workspace was pre-configured with a different builder code, you must update `agent.json` to match the new registration — otherwise the agent will use stale attribution.
