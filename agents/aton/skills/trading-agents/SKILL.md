---
name: trading-agents
description: Autonomous multi-agent trading framework with smart wallet integration. Spawns specialized analyst agents (fundamentals, technical, sentiment, news), conducts bull/bear debates, and executes trades via Coinbase Smart Wallet or private key. Supports stock analysis, prediction market arbitrage (Polymarket, Kalshi, OpinionLaps), futures/perpetuals, and short-term price action trading. Use when asked to analyze stocks, get trading recommendations, run autonomous trading, prediction market arbitrage, Kelly sizing, or execute trades. Triggers on "analyze TICKER", "should I buy/sell X", "trading analysis", "autonomous trading", "prediction market", "arbitrage", "smart wallet trading".
---

# Trading Agents

Autonomous multi-agent trading framework. Combines institutional-grade analysis with smart wallet execution for stocks, prediction markets, and crypto.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ANALYST TEAM                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │Fundamental│ │Technical │ │Sentiment │ │    News      │   │
│  │ Analyst   │ │ Analyst  │ │ Analyst  │ │   Analyst    │   │
│  └─────┬─────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘   │
└────────┼────────────┼────────────┼──────────────┼───────────┘
         └────────────┴────────────┴──────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                RESEARCH TEAM (Bull/Bear Debate)              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   EXECUTION LAYER                            │
│  ┌────────────┐ ┌────────────┐ ┌────────────────────────┐  │
│  │ Smart      │ │ Prediction │ │ CEX/DEX                │  │
│  │ Wallet     │ │ Markets    │ │ Integration            │  │
│  │ (Base)     │ │ (Poly/Kal) │ │ (Futures/Perps)        │  │
│  └────────────┘ └────────────┘ └────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Analysis Only (No Wallet)

```bash
python scripts/analyze.py NVDA
python scripts/analyze.py AAPL --date 2026-01-15
```

### 2. With Smart Wallet (Autonomous Execution)

```bash
# Configure wallet
cp config.example.json config.json
# Edit config.json with your settings

# Run autonomous trader
python scripts/autonomous.py --mode paper  # Paper trading first!
python scripts/autonomous.py --mode live   # Live trading
```

## Configuration

### config.json

```json
{
  "mode": "paper",
  "wallet": {
    "type": "smart_wallet",
    "provider": "base_account",
    "chain_id": 8453,
    "paymaster_url": "YOUR_PAYMASTER_URL"
  },
  "markets": {
    "stocks": {
      "enabled": true,
      "data_source": "yfinance"
    },
    "prediction_markets": {
      "enabled": true,
      "platforms": ["polymarket", "kalshi", "opinionlaps"],
      "min_edge": 0.04,
      "max_position_pct": 0.05
    },
    "futures": {
      "enabled": false,
      "exchange": "hyperliquid",
      "max_leverage": 3
    }
  },
  "risk": {
    "max_daily_loss_pct": 0.10,
    "max_position_pct": 0.15,
    "kelly_fraction": 0.25,
    "min_edge": 0.04
  },
  "alerts": {
    "telegram_bot_token": "",
    "telegram_chat_id": ""
  }
}
```

## Wallet Integration

### Option 1: Coinbase Smart Wallet (Recommended)

ERC-4337 smart wallet with gas sponsorship and batch transactions.

```typescript
import { createBaseAccountSDK } from '@base-org/account';

const sdk = createBaseAccountSDK({
  appName: 'Trading Agents',
  appChainIds: [8453], // Base Mainnet
});

// Execute trade
const tx = await sdk.sendTransaction({
  to: PREDICTION_MARKET_ADDRESS,
  data: encodedTradeData,
  value: 0n
});
```

**Benefits:**
- Gasless transactions (paymaster sponsorship)
- Batch multiple trades atomically
- No private key exposure
- Social recovery

### Option 2: Private Key Wallet

For server-side autonomous operation.

```bash
export TRADING_PRIVATE_KEY=0x...
```

```python
from web3 import Web3

w3 = Web3(Web3.HTTPProvider(RPC_URL))
account = w3.eth.account.from_key(os.environ['TRADING_PRIVATE_KEY'])
```

### Option 3: Hardware Wallet

For manual approval of larger trades.

## Trading Modes

### Mode 1: Stock Analysis

Traditional equity analysis with multi-agent debate.

```bash
python scripts/analyze.py NVDA --output json
```

Output: BUY/HOLD/SELL recommendation with confidence score.

### Mode 2: Prediction Market Arbitrage

Detect and execute arbitrage on Polymarket, Kalshi, OpinionLaps.

```bash
# Scan for arbitrage opportunities
python scripts/arb_scanner.py --platforms polymarket,kalshi --min-edge 3.0

# Execute (paper mode)
python scripts/arb_executor.py --opportunity arb_001 --mode paper
```

**Arbitrage Types:**
- **Math Arb**: Probabilities sum < 100% (buy all outcomes)
- **Cross-Market**: Same event priced differently
- **Time Decay**: Exploit slow-updating markets

### Mode 3: Short-Term Price Action

High-frequency signals based on technical analysis.

```bash
python scripts/price_action.py NVDA --timeframe 5m --signals momentum,breakout
```

**Strategies:**
- Momentum (RSI divergence, MACD crossover)
- Breakout (support/resistance)
- Mean reversion (Bollinger bands)

### Mode 4: Futures/Perpetuals

Leverage trading on decentralized perp DEXs.

```bash
python scripts/perps.py --asset ETH --direction long --leverage 2 --size 0.1
```

**Supported:**
- Hyperliquid
- dYdX
- GMX

## Autonomous Trading Loop

```python
from trading_agents import AutonomousTrader

trader = AutonomousTrader(config_path='config.json')

# Start autonomous loop
trader.start(
    scan_interval=300,      # 5 minutes
    markets=['polymarket', 'kalshi'],
    min_edge=0.04,
    max_daily_trades=10
)

# The loop:
# 1. Scan markets for opportunities
# 2. Run multi-agent analysis on candidates
# 3. Calculate position size (Kelly)
# 4. Execute via smart wallet
# 5. Monitor and manage positions
# 6. Log everything to memory/
```

## Position Sizing (Kelly Criterion)

```python
def kelly_size(true_prob, market_price, bankroll, fraction=0.25):
    """
    Quarter-Kelly for conservative sizing.
    
    Args:
        true_prob: Your estimated true probability (0-1)
        market_price: Current market price (0-1)
        bankroll: Total capital available
        fraction: Kelly fraction (0.25 = quarter-Kelly)
    
    Returns:
        Position size in dollars
    """
    if true_prob <= market_price:
        return 0  # No edge
    
    edge = true_prob - market_price
    odds = (1 / market_price) - 1
    kelly = (true_prob * odds - (1 - true_prob)) / odds
    
    return min(
        kelly * fraction * bankroll,
        bankroll * 0.15  # Max 15% per position
    )
```

## Risk Management Rules

| Rule | Value | Rationale |
|------|-------|-----------|
| Max position size | 15% bankroll | Single bet risk limit |
| Min edge | 4% | Cover fees + margin of error |
| Kelly fraction | 25% | Conservative sizing |
| Daily loss limit | 10% bankroll | Stop trading after bad day |
| Correlation limit | 3 | Max correlated positions |

## Prediction Market Integration

### Polymarket

```python
# Buy YES shares
from scripts.polymarket import PolymarketClient

client = PolymarketClient(private_key=PRIVATE_KEY)
order = client.buy(
    market_id="0x...",
    outcome="YES",
    amount_usdc=100,
    limit_price=0.45
)
```

### Kalshi

```python
from scripts.kalshi import KalshiClient

client = KalshiClient(key_id=KEY_ID, private_key=PRIVATE_KEY)
order = client.place_order(
    ticker="KXATPMATCH-26MAR12DRAMED-DRA",
    side="yes",
    price=38,  # cents
    count=10   # contracts
)
```

### OpinionLaps

```python
from scripts.opinionlaps import OpinionLapsClient

client = OpinionLapsClient(api_key=API_KEY)
order = client.trade(
    event_id="...",
    position="YES",
    amount=50
)
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `analyze.py` | Single stock multi-agent analysis |
| `batch_analyze.py` | Batch analysis of multiple tickers |
| `backtest.py` | Historical signal backtesting |
| `arb_scanner.py` | Prediction market arbitrage detection |
| `arb_executor.py` | Execute arbitrage trades |
| `autonomous.py` | Full autonomous trading loop |
| `price_action.py` | Short-term technical signals |
| `perps.py` | Futures/perpetuals trading |
| `wallet_setup.py` | Configure and test wallet |

## Monitoring & Alerts

### Telegram Alerts

```python
# In config.json
{
  "alerts": {
    "telegram_bot_token": "123456:ABC...",
    "telegram_chat_id": "-1001234567890"
  }
}
```

Alerts for:
- New arbitrage opportunities (>5% edge)
- Trade executions
- Position closures
- Daily P&L summary
- Risk limit breaches

### Dashboard

```bash
python scripts/dashboard.py --port 8080
```

Web UI showing:
- Open positions
- P&L charts
- Recent trades
- Market scanner

## Safety Features

1. **Paper Trading Mode** — Always test first
2. **Position Limits** — Hard caps on size
3. **Circuit Breakers** — Stop on daily loss limit
4. **Rate Limiting** — Prevent API abuse
5. **Dry Run Flag** — Preview trades before execution
6. **Audit Log** — Every action logged to `memory/trades/`

## Data Sources

| Data | Source | Cost |
|------|--------|------|
| Stock prices | yfinance | Free |
| Stock fundamentals | yfinance | Free |
| Technical indicators | Computed | Free |
| Prediction markets | Platform APIs | Free |
| Odds de-vigging | Sofascore | Free |
| News sentiment | yfinance + computed | Free |

Optional (better data):
- Alpha Vantage (stock data)
- The Odds API (sports odds)
- Polygon.io (crypto prices)

## Getting Started Checklist

1. [ ] Copy `config.example.json` to `config.json`
2. [ ] Run paper trading for 1-2 weeks
3. [ ] Review trades in `memory/trades/`
4. [ ] If profitable, fund smart wallet with small amount ($50-100)
5. [ ] Run live with micro positions
6. [ ] Scale up gradually based on performance

## ERC-8004 Agent Identity

Create a verifiable on-chain identity for your trading agent.

### Quick Start

```bash
# Register new agent on Base
python scripts/onboard_agent.py \
  --name "TradingBot" \
  --chain base \
  --operator 0x12F1B38DC35AA65B50E5849d02559078953aE24b

# Using OpenClaw Ed25519 identity (Celo)
python scripts/onboard_agent.py \
  --name "TradingBot" \
  --chain celo \
  --use-openclaw-key
```

### What You Get

- **ERC-721 NFT** — Portable, censorship-resistant identity
- **Certificate URL** — `https://8004.way.je/agent/{chain}:{id}`
- **Agent Wallet** — On-chain address for receiving payments
- **Reputation Hooks** — Compatible with ERC-8004 reputation registries

### Contract Addresses

| Chain | Registry |
|-------|----------|
| Base Mainnet | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| Celo Mainnet | `0xaC3DF9ABf80d0F5c020C06B04Cced27763355944` |

### Autonomous Operation

After onboarding:
1. Agent owns its identity NFT (or transfers to operator)
2. Agent wallet receives trading profits
3. Reputation accumulates from trading performance
4. Other agents can verify identity on-chain

See `references/erc8004-identity.md` for full documentation.

## Limitations

- **Not financial advice** — Research tool only
- **LLM latency** — Full analysis takes 30-90s
- **Market efficiency** — Good arbs disappear fast
- **Execution risk** — Slippage and liquidity
- **API limits** — Free tiers have rate limits

## References

- `references/agent-prompts.md` — Full agent system prompts
- `references/arbitrage-math.md` — Arbitrage calculations
- `references/kelly-sizing.md` — Position sizing math
- `references/wallet-setup.md` — Wallet configuration guide
