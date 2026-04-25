# Kelly Criterion Position Sizing

Mathematical framework for optimal bet sizing based on edge and probability.

## The Formula

```
f* = (p * b - q) / b

where:
  f* = fraction of bankroll to bet
  p  = probability of winning
  q  = probability of losing (1 - p)
  b  = odds received on the bet (net odds, e.g., 2:1 = 2)
```

## Simplified for Prediction Markets

For a binary market where you buy at price `c` with true probability `p`:

```
edge = p - c
odds = (1/c) - 1
kelly = (p * odds - (1-p)) / odds
      = (p - c) / (1 - c)
      = edge / (1 - c)
```

## Example Calculation

**Scenario:**
- True probability: 60%
- Market price: 50¢ (50%)
- Bankroll: $1,000

**Calculation:**
```
edge = 0.60 - 0.50 = 0.10 (10% edge)
kelly = 0.10 / (1 - 0.50) = 0.10 / 0.50 = 0.20 (20%)
position = $1,000 × 0.20 = $200
```

## Fractional Kelly

Full Kelly is mathematically optimal but has high variance. Use fractional Kelly for smoother equity curves:

| Fraction | Risk Level | Typical Use |
|----------|------------|-------------|
| 100% | Aggressive | Never recommended |
| 50% | Moderate | Experienced traders |
| 25% | Conservative | **Recommended** |
| 10% | Very conservative | Risk-averse |

**Quarter-Kelly example:**
```
full_kelly = 20%
quarter_kelly = 20% × 0.25 = 5%
position = $1,000 × 0.05 = $50
```

## Position Size Caps

Always apply hard caps regardless of Kelly:

```python
def safe_kelly(true_prob, market_price, bankroll, kelly_fraction=0.25):
    if true_prob <= market_price:
        return 0  # No edge
    
    edge = true_prob - market_price
    kelly = edge / (1 - market_price)
    
    # Apply fraction
    size = kelly * kelly_fraction * bankroll
    
    # Hard caps
    MAX_POSITION_PCT = 0.15  # 15% max per position
    MIN_POSITION = 5.0       # $5 minimum
    
    size = min(size, bankroll * MAX_POSITION_PCT)
    size = max(size, 0) if size >= MIN_POSITION else 0
    
    return round(size, 2)
```

## Multiple Correlated Bets

When bets are correlated (e.g., multiple sports bets on same game), reduce each position:

```
adjusted_kelly = kelly / num_correlated_bets
```

Or use portfolio optimization:
```
max_correlated_exposure = bankroll * 0.20  # 20% max
per_bet = max_correlated_exposure / num_bets
```

## Edge Estimation Uncertainty

Your "true probability" is an estimate. Account for uncertainty:

```
# If 70% confident in your probability estimate
confidence = 0.70
adjusted_kelly = kelly * confidence
```

## Math Arbitrage Sizing

For guaranteed arbitrage (buy all outcomes when sum < 100%):

```python
def arb_position_size(prob_sum, outcomes, bankroll, kelly_fraction=0.25):
    """
    For math arb, return is guaranteed but small.
    
    prob_sum < 1.0: Buy all outcomes
    Return = (1 / prob_sum) - 1
    """
    if prob_sum >= 1.0:
        return 0
    
    # Guaranteed return
    gross_return = (1 / prob_sum) - 1
    
    # Subtract fees (2% per leg)
    fee_rate = 0.02
    net_return = gross_return - (fee_rate * len(outcomes))
    
    if net_return <= 0:
        return 0
    
    # For guaranteed returns, Kelly says bet heavily
    # But cap at 15% per trade
    kelly = net_return  # Edge = return when p=1
    
    size = min(
        kelly * kelly_fraction * bankroll,
        bankroll * 0.15
    )
    
    return round(size, 2)
```

## Allocation Across Outcomes

For multi-outcome arbitrage, allocate to guarantee equal profit:

```python
def allocate_across_outcomes(total_size, outcomes):
    """
    Allocate total_size across outcomes for equal profit.
    
    outcomes: list of (name, price) tuples
    """
    total_inv_price = sum(1/p for _, p in outcomes)
    
    allocation = {}
    for name, price in outcomes:
        # Weight by inverse price
        weight = (1/price) / total_inv_price
        allocation[name] = round(total_size * weight, 2)
    
    return allocation
```

**Example:**
```
outcomes = [("YES", 0.48), ("NO", 0.47)]
total_size = $100

# Inverse prices: 1/0.48 = 2.08, 1/0.47 = 2.13
# Sum = 4.21
# YES weight = 2.08/4.21 = 49.4%
# NO weight = 2.13/4.21 = 50.6%

allocation = {"YES": $49.40, "NO": $50.60}
```

## Kelly for Futures/Leverage

With leverage, adjust Kelly to account for increased risk:

```
leveraged_kelly = kelly / leverage

# Example: 5× leverage
kelly = 10%
safe_size = 10% / 5 = 2% of capital
```

## Common Mistakes

1. **Overestimating edge** — Your model isn't perfect
2. **Full Kelly betting** — Too much variance
3. **Ignoring fees** — They compound
4. **Correlated bets** — Reduce exposure
5. **No hard caps** — Always have max position limits

## Recommended Settings

```json
{
  "kelly_fraction": 0.25,
  "max_position_pct": 0.15,
  "min_edge": 0.04,
  "min_position": 5.0,
  "max_correlated_positions": 3,
  "max_daily_loss_pct": 0.10
}
```
