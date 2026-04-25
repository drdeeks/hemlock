# Wallet Setup Guide

Configure smart wallet or private key for autonomous trading execution.

## Option 1: Coinbase Smart Wallet (Recommended)

ERC-4337 account abstraction wallet with best security and UX.

### Benefits

- **No private key management** — Keys secured by passkeys/biometrics
- **Gasless transactions** — Paymaster sponsors gas fees
- **Batch operations** — Execute multiple trades atomically
- **Social recovery** — Recover wallet without seed phrase
- **Multi-chain** — Base, Ethereum, Arbitrum, Polygon, etc.

### Setup

```typescript
// Install SDK
npm install @base-org/account

// Initialize
import { createBaseAccountSDK } from '@base-org/account';

const sdk = createBaseAccountSDK({
  appName: 'Trading Agents',
  appLogoUrl: 'https://yourapp.com/logo.png',
  appChainIds: [8453], // Base Mainnet
});

// Get provider
const provider = sdk.getProvider();

// Connect (user authenticates via popup)
const { accounts } = await provider.request({
  method: 'wallet_connect',
  params: [{ version: '1' }]
});

const address = accounts[0].address;
console.log(`Connected: ${address}`);
```

### Executing Trades

```typescript
// Single transaction
const tx = await provider.request({
  method: 'eth_sendTransaction',
  params: [{
    from: address,
    to: PREDICTION_MARKET_ADDRESS,
    data: encodeFunctionData({
      abi: MARKET_ABI,
      functionName: 'buy',
      args: [marketId, outcomeIndex, amount]
    })
  }]
});

// Batch transactions (atomic)
const batch = await provider.request({
  method: 'wallet_sendCalls',
  params: [{
    version: '1.0',
    from: address,
    calls: [
      { to: MARKET_1, data: buyData1 },
      { to: MARKET_2, data: buyData2 }
    ]
  }]
});
```

### Paymaster (Gasless)

To enable gasless transactions, configure a paymaster:

```typescript
const sdk = createBaseAccountSDK({
  appName: 'Trading Agents',
  appChainIds: [8453],
  paymasterUrl: process.env.PAYMASTER_URL
});
```

**Paymaster providers:**
- Coinbase (free tier available)
- Pimlico
- Alchemy
- Stackup

### When to Use Smart Wallet

✅ **User-facing applications** — Best UX
✅ **Web/mobile apps** — Popup authentication
✅ **Security-critical** — No key exposure
✅ **Batch operations** — Arbitrage execution

❌ **Server-side bots** — Requires user interaction
❌ **High-frequency trading** — Popup latency

---

## Option 2: Private Key Wallet

Direct Ethereum wallet for server-side autonomous operation.

### When to Use

✅ **Server-side bots** — No user interaction needed
✅ **High-frequency trading** — Instant execution
✅ **Autonomous operation** — 24/7 trading

❌ **Large amounts** — Security risk
❌ **User-facing apps** — Poor UX

### Setup

```bash
# Generate new wallet (do this ONCE, save securely)
python -c "from eth_account import Account; a=Account.create(); print(f'Address: {a.address}\\nPrivate Key: {a.key.hex()}')"

# Set environment variable
export TRADING_PRIVATE_KEY=0x...
```

### Python Usage

```python
import os
from web3 import Web3
from eth_account import Account

# Load wallet
private_key = os.environ['TRADING_PRIVATE_KEY']
account = Account.from_key(private_key)
print(f"Wallet: {account.address}")

# Connect to Base
w3 = Web3(Web3.HTTPProvider('https://mainnet.base.org'))

# Build transaction
tx = {
    'from': account.address,
    'to': PREDICTION_MARKET_ADDRESS,
    'value': 0,
    'data': encoded_function_call,
    'gas': 200000,
    'gasPrice': w3.eth.gas_price,
    'nonce': w3.eth.get_transaction_count(account.address),
    'chainId': 8453
}

# Sign and send
signed = account.sign_transaction(tx)
tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
print(f"TX: {tx_hash.hex()}")

# Wait for confirmation
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
print(f"Status: {'✓' if receipt.status == 1 else '✗'}")
```

### Security Best Practices

1. **Never commit private key to code**
2. **Use environment variables only**
3. **Limit funds in hot wallet** — Only what's needed for trading
4. **Separate wallets** — Different wallets for different purposes
5. **Monitor for unusual activity**
6. **Consider hardware wallet** — For large amounts

### Recommended Wallet Structure

```
Main Wallet (cold storage)
├── Large holdings
├── Hardware wallet (Ledger/Trezor)
└── Manual transactions only

Trading Wallet (hot)
├── Small balance ($100-1000)
├── Private key in env var
├── Automated trading
└── Auto-refill from main wallet
```

---

## Option 3: Hardware Wallet (Hybrid)

For manual approval of larger trades while keeping some automation.

### Setup with Ledger

```bash
# Install ledger support
pip install ledger-py

# Or use Frame as a signer
# Frame: https://frame.sh
```

### Use Case

1. Bot scans for opportunities
2. Bot sends alert with opportunity details
3. Human reviews and approves
4. Human signs with hardware wallet
5. Bot monitors execution

---

## Funding the Wallet

### Base Mainnet

1. **Get ETH for gas**
   - Bridge from Ethereum via Base Bridge
   - Or buy on exchange and withdraw to Base

2. **Get USDC for trading**
   - Most prediction markets use USDC
   - Bridge from Ethereum or buy on DEX

### Addresses

| Chain | USDC Address |
|-------|--------------|
| Base Mainnet | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Base Sepolia | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Polygon | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` |
| Arbitrum | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |

### Faucets (Testnet)

- **Base Sepolia ETH:** https://www.alchemy.com/faucets/base-sepolia
- **USDC (testnet):** Use test USDC contracts

---

## Configuration File

```json
{
  "wallet": {
    "type": "smart_wallet",
    "provider": "base_account",
    "chain_id": 8453,
    "rpc_url": "https://mainnet.base.org",
    "paymaster_url": "YOUR_PAYMASTER_URL"
  }
}
```

Or for private key:

```json
{
  "wallet": {
    "type": "private_key",
    "chain_id": 8453,
    "rpc_url": "https://mainnet.base.org",
    "env_var": "TRADING_PRIVATE_KEY"
  }
}
```

---

## Verifying Setup

```bash
# Smart wallet
node scripts/verify-wallet.js

# Private key
python scripts/wallet_setup.py --verify --chain base

# Check balance
python scripts/wallet_setup.py --balance 0xYOUR_ADDRESS --chain base
```

Expected output:
```
✅ Wallet connected
Address: 0x...
Chain: Base Mainnet (8453)
Balances:
  ETH: 0.05
  USDC: 150.00
```
