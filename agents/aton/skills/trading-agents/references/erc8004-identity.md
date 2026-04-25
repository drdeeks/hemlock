# ERC-8004 Agent Identity

On-chain agent identity standard for trustless agent economies.

## Overview

ERC-8004 provides:
- **Identity Registry** — ERC-721 NFT representing agent identity
- **Reputation Registry** — On-chain feedback and scoring
- **Validation Registry** — Third-party verification hooks

## Contract Addresses

| Chain | Chain ID | Registry Address |
|-------|----------|------------------|
| Base Mainnet | 8453 | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| Celo Mainnet | 42220 | `0xaC3DF9ABf80d0F5c020C06B04Cced27763355944` |

## Agent Identifier Format

```
agentRegistry: {namespace}:{chainId}:{registryAddress}
agentId: uint256 (ERC-721 tokenId)

Example: eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
Agent #42 on Base Mainnet
```

## Registration File Schema

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  "name": "my-agent",
  "description": "What I do",
  "image": "ipfs://... or https://...",
  "services": [
    { "name": "MCP", "endpoint": "https://...", "version": "2025-06-18" },
    { "name": "A2A", "endpoint": "https://...", "version": "0.3.0" },
    { "name": "trading", "endpoint": "autonomous" }
  ],
  "x402Support": false,
  "active": true,
  "registrations": [
    { 
      "agentId": 42, 
      "agentRegistry": "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432" 
    }
  ],
  "supportedTrust": ["reputation"]
}
```

## Key Functions

### Registration

```solidity
// Register with metadata URI
function register(string agentURI) external returns (uint256 agentId);

// Register empty (set URI later)
function register() external returns (uint256 agentId);

// Update URI
function setAgentURI(uint256 agentId, string newURI) external;
```

### Agent Wallet

The `agentWallet` is where the agent receives payments. Requires signature proof.

```solidity
// Set wallet (requires EIP-712 signature from newWallet)
function setAgentWallet(
    uint256 agentId, 
    address newWallet, 
    uint256 deadline, 
    bytes signature
) external;

// Read wallet
function getAgentWallet(uint256 agentId) external view returns (address);

// Clear wallet
function unsetAgentWallet(uint256 agentId) external;
```

### Metadata

```solidity
function setMetadata(uint256 agentId, string key, bytes value) external;
function getMetadata(uint256 agentId, string key) external view returns (bytes);
```

### Ownership (ERC-721)

```solidity
function ownerOf(uint256 tokenId) external view returns (address);
function transferFrom(address from, address to, uint256 tokenId) external;
```

## wayMint API

Base URL: `https://8004.way.je`

### Pin Metadata

```bash
curl -X POST https://8004.way.je/api/pin \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-agent",
    "description": "What I do",
    "services": [{"name": "trading", "endpoint": "autonomous"}]
  }'

# Response: { "cid": "bafy..." }
# Use as: ipfs://bafy...
```

### Lookup Agent

```bash
# By chain and ID
GET https://8004.way.je/api/agent/base/42
GET https://8004.way.je/api/agent/celo/17

# By owner
GET https://8004.way.je/api/owner/0x1234...
```

### Certificate URL

```
https://8004.way.je/agent/{chain}:{agentId}

Examples:
https://8004.way.je/agent/base:42
https://8004.way.je/agent/celo:17
```

## Onboarding Flow

### 1. Generate or Load Keypair

```python
from eth_account import Account

# New keypair
account = Account.create()
print(f"Address: {account.address}")
print(f"Private Key: {account.key.hex()}")

# Or load existing
account = Account.from_key(os.environ["AGENT_PRIVATE_KEY"])
```

### 2. Pin Metadata to IPFS

```python
import requests

resp = requests.post("https://8004.way.je/api/pin", json={
    "name": "TradingBot",
    "description": "Autonomous prediction market trader",
    "services": [{"name": "trading", "endpoint": "autonomous"}]
})
cid = resp.json()["cid"]
agent_uri = f"ipfs://{cid}"
```

### 3. Register On-Chain

```python
from web3 import Web3

w3 = Web3(Web3.HTTPProvider("https://mainnet.base.org"))
registry = w3.eth.contract(address=REGISTRY_ADDRESS, abi=REGISTRY_ABI)

tx = registry.functions.register(agent_uri).build_transaction({
    "from": account.address,
    "nonce": w3.eth.get_transaction_count(account.address),
    "gas": 300000,
    "gasPrice": w3.eth.gas_price,
    "chainId": 8453
})

signed = account.sign_transaction(tx)
tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
```

### 4. Transfer Ownership (Optional)

```python
# Transfer to operator wallet
tx = registry.functions.transferFrom(
    account.address,
    "0x12F1B38DC35AA65B50E5849d02559078953aE24b",  # drdeeks.base.eth
    agent_id
).build_transaction({...})
```

## Ed25519 Self-Registration (Celo)

For agents with OpenClaw Ed25519 identity:

```bash
python onboard_agent.py --name "MyAgent" --chain celo --use-openclaw-key
```

This uses the keypair at `~/.openclaw/identity/device.json` and the wayMint self-registration API.

## Quick Start

```bash
# Install dependencies
pip install web3 requests

# Register new agent on Base
python scripts/onboard_agent.py \
  --name "TradingBot" \
  --chain base \
  --description "Autonomous prediction market trader"

# With ownership transfer to operator
python scripts/onboard_agent.py \
  --name "TradingBot" \
  --chain base \
  --operator 0x12F1B38DC35AA65B50E5849d02559078953aE24b

# Lookup existing agent
python scripts/onboard_agent.py --chain base --lookup 42
```

## Resources

- ERC-8004 Spec: https://eips.ethereum.org/EIPS/eip-8004
- wayMint: https://8004.way.je
- wayMint Skill: https://8004.way.je/skill.md
