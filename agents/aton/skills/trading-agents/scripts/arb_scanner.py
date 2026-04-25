#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Prediction Market Arbitrage Scanner

Scan Polymarket, Kalshi, OpinionLaps for arbitrage opportunities.

Usage:
    python arb_scanner.py --platforms polymarket --min-edge 3.0
    python arb_scanner.py --platforms polymarket,kalshi --output arbs.json
"""

import argparse
import json
import time
from datetime import datetime
from typing import List, Dict, Optional
import requests
from dataclasses import dataclass, asdict
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


@dataclass
class Outcome:
    name: str
    price: float
    volume: float = 0


@dataclass
class Market:
    id: str
    platform: str
    title: str
    outcomes: List[Outcome]
    volume: float
    end_date: Optional[str] = None
    url: Optional[str] = None


@dataclass
class Arbitrage:
    id: str
    market_id: str
    platform: str
    title: str
    arb_type: str  # math_arb_buy, math_arb_sell, cross_market
    prob_sum: float
    edge_gross: float
    edge_net: float  # After fees
    outcomes: List[dict]
    volume: float
    risk_score: int  # 0-100, lower is better
    detected_at: str
    action: str  # What to do


def fetch_polymarket_markets() -> List[Market]:
    """
    Fetch markets from Polymarket.
    
    Note: Polymarket doesn't have a public API for market data.
    This uses web scraping or their GraphQL endpoint.
    """
    markets = []
    
    try:
        # Polymarket uses a GraphQL endpoint
        # This is a simplified example - actual implementation may vary
        url = "https://gamma-api.polymarket.com/markets"
        params = {
            "limit": 100,
            "active": True,
            "closed": False
        }
        
        response = requests.get(url, params=params, timeout=30)
        
        if response.status_code == 200:
            data = response.json()
            
            for item in data:
                try:
                    # Parse outcomes from tokens
                    outcomes = []
                    if "tokens" in item:
                        for token in item["tokens"]:
                            outcomes.append(Outcome(
                                name=token.get("outcome", "Unknown"),
                                price=float(token.get("price", 0)),
                                volume=float(token.get("volume", 0) or 0)
                            ))
                    
                    if outcomes:
                        markets.append(Market(
                            id=item.get("id", ""),
                            platform="polymarket",
                            title=item.get("question", "Unknown"),
                            outcomes=outcomes,
                            volume=float(item.get("volume", 0) or 0),
                            end_date=item.get("endDate"),
                            url=f"https://polymarket.com/market/{item.get('slug', '')}"
                        ))
                except Exception as e:
                    logger.debug(f"Error parsing market: {e}")
                    continue
                    
    except requests.RequestException as e:
        logger.error(f"Error fetching Polymarket: {e}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    
    logger.info(f"Fetched {len(markets)} markets from Polymarket")
    return markets


def fetch_kalshi_markets() -> List[Market]:
    """
    Fetch markets from Kalshi.
    
    Kalshi has a public API but requires authentication for trading.
    Market data is publicly available.
    """
    markets = []
    
    try:
        # Kalshi public API endpoint
        url = "https://trading-api.kalshi.com/trade-api/v2/markets"
        params = {
            "limit": 100,
            "status": "open"
        }
        
        response = requests.get(url, params=params, timeout=30)
        
        if response.status_code == 200:
            data = response.json()
            
            for item in data.get("markets", []):
                try:
                    # Kalshi markets are binary (yes/no)
                    yes_price = item.get("yes_bid", 0) / 100  # Kalshi uses cents
                    no_price = item.get("no_bid", 0) / 100
                    
                    outcomes = [
                        Outcome(name="YES", price=yes_price),
                        Outcome(name="NO", price=no_price)
                    ]
                    
                    markets.append(Market(
                        id=item.get("ticker", ""),
                        platform="kalshi",
                        title=item.get("title", "Unknown"),
                        outcomes=outcomes,
                        volume=float(item.get("volume", 0) or 0),
                        end_date=item.get("close_time"),
                        url=f"https://kalshi.com/markets/{item.get('ticker', '')}"
                    ))
                except Exception as e:
                    logger.debug(f"Error parsing Kalshi market: {e}")
                    continue
                    
    except requests.RequestException as e:
        logger.error(f"Error fetching Kalshi: {e}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    
    logger.info(f"Fetched {len(markets)} markets from Kalshi")
    return markets


def detect_math_arbitrage(market: Market, fee_rate: float = 0.02) -> Optional[Arbitrage]:
    """
    Detect math arbitrage (probability sum != 100%).
    
    Buy-side arb: prob_sum < 100% → buy all outcomes, guaranteed profit
    Sell-side arb: prob_sum > 100% → sell all outcomes (riskier, needs capital)
    """
    prices = [o.price for o in market.outcomes]
    prob_sum = sum(prices)
    
    # Skip if no valid prices
    if not prices or prob_sum == 0:
        return None
    
    # Calculate fees (assume taker for each leg)
    num_legs = len(market.outcomes)
    total_fee = fee_rate * num_legs
    
    # Buy-side arb: sum < 1.0
    if prob_sum < 1.0:
        edge_gross = 1.0 - prob_sum
        edge_net = edge_gross - total_fee
        
        if edge_net > 0:
            # Risk score based on volume and edge size
            risk_score = calculate_risk_score(market, edge_net, "buy")
            
            return Arbitrage(
                id=f"arb_{market.platform}_{market.id}_{int(time.time())}",
                market_id=market.id,
                platform=market.platform,
                title=market.title,
                arb_type="math_arb_buy",
                prob_sum=prob_sum,
                edge_gross=edge_gross,
                edge_net=edge_net,
                outcomes=[asdict(o) for o in market.outcomes],
                volume=market.volume,
                risk_score=risk_score,
                detected_at=datetime.utcnow().isoformat(),
                action=f"BUY all {num_legs} outcomes. Net edge: {edge_net:.2%}"
            )
    
    # Sell-side arb: sum > 1.0
    elif prob_sum > 1.0:
        edge_gross = prob_sum - 1.0
        edge_net = edge_gross - total_fee
        
        if edge_net > 0:
            risk_score = calculate_risk_score(market, edge_net, "sell")
            
            return Arbitrage(
                id=f"arb_{market.platform}_{market.id}_{int(time.time())}",
                market_id=market.id,
                platform=market.platform,
                title=market.title,
                arb_type="math_arb_sell",
                prob_sum=prob_sum,
                edge_gross=edge_gross,
                edge_net=edge_net,
                outcomes=[asdict(o) for o in market.outcomes],
                volume=market.volume,
                risk_score=risk_score,
                detected_at=datetime.utcnow().isoformat(),
                action=f"SELL all {num_legs} outcomes. Net edge: {edge_net:.2%}. ⚠️ Requires collateral"
            )
    
    return None


def calculate_risk_score(market: Market, edge: float, side: str) -> int:
    """
    Calculate risk score (0-100, lower is better).
    
    Factors:
    - Volume (higher = lower risk)
    - Edge size (very high edge = suspicious)
    - Number of outcomes
    - Side (sell is riskier than buy)
    """
    score = 50  # Base score
    
    # Volume factor (lower volume = higher risk)
    if market.volume < 10000:
        score += 30
    elif market.volume < 100000:
        score += 15
    elif market.volume > 1000000:
        score -= 15
    
    # Edge factor (very high edge is suspicious)
    if edge > 0.15:
        score += 25  # Likely stale data or error
    elif edge > 0.10:
        score += 10
    elif edge < 0.03:
        score += 5  # Too small to be worth it
    
    # Number of outcomes (more = more complexity)
    num_outcomes = len(market.outcomes)
    if num_outcomes > 3:
        score += (num_outcomes - 3) * 5
    
    # Side factor
    if side == "sell":
        score += 20  # Sell arbs are riskier
    
    return max(0, min(100, score))


def scan_markets(platforms: List[str], min_edge: float = 0.03) -> List[Arbitrage]:
    """Scan specified platforms for arbitrage opportunities."""
    all_markets = []
    
    for platform in platforms:
        if platform == "polymarket":
            all_markets.extend(fetch_polymarket_markets())
        elif platform == "kalshi":
            all_markets.extend(fetch_kalshi_markets())
        else:
            logger.warning(f"Unknown platform: {platform}")
    
    logger.info(f"Total markets to scan: {len(all_markets)}")
    
    # Detect arbitrage
    opportunities = []
    for market in all_markets:
        arb = detect_math_arbitrage(market)
        if arb and arb.edge_net >= min_edge:
            opportunities.append(arb)
    
    # Sort by edge (best first)
    opportunities.sort(key=lambda x: x.edge_net, reverse=True)
    
    logger.info(f"Found {len(opportunities)} opportunities with edge >= {min_edge:.1%}")
    return opportunities


def format_opportunity(arb: Arbitrage) -> str:
    """Format arbitrage opportunity for display."""
    lines = [
        f"\n{'='*60}",
        f"🎯 {arb.title}",
        f"Platform: {arb.platform} | Type: {arb.arb_type}",
        f"Prob Sum: {arb.prob_sum:.2%} | Edge: {arb.edge_net:.2%} (gross: {arb.edge_gross:.2%})",
        f"Volume: ${arb.volume:,.0f} | Risk Score: {arb.risk_score}/100",
        f"",
        "Outcomes:"
    ]
    
    for outcome in arb.outcomes:
        lines.append(f"  - {outcome['name']}: {outcome['price']:.2%}")
    
    lines.append(f"")
    lines.append(f"ACTION: {arb.action}")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Prediction Market Arbitrage Scanner")
    parser.add_argument("--platforms", default="polymarket",
                        help="Comma-separated platforms (polymarket,kalshi)")
    parser.add_argument("--min-edge", type=float, default=0.03,
                        help="Minimum edge percentage (default: 0.03 = 3%%)")
    parser.add_argument("--output", "-o", help="Output JSON file")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--watch", action="store_true", help="Continuous monitoring")
    parser.add_argument("--interval", type=int, default=300,
                        help="Watch interval in seconds (default: 300)")
    
    args = parser.parse_args()
    
    platforms = [p.strip() for p in args.platforms.split(",")]
    
    def run_scan():
        logger.info(f"Scanning {platforms} for arbitrage (min_edge={args.min_edge:.1%})")
        opportunities = scan_markets(platforms, args.min_edge)
        
        if args.output:
            with open(args.output, 'w') as f:
                json.dump([asdict(o) for o in opportunities], f, indent=2)
            logger.info(f"Saved {len(opportunities)} opportunities to {args.output}")
        
        if args.json:
            print(json.dumps([asdict(o) for o in opportunities], indent=2))
        else:
            if opportunities:
                print(f"\n🔍 Found {len(opportunities)} arbitrage opportunities:\n")
                for opp in opportunities[:10]:  # Show top 10
                    print(format_opportunity(opp))
            else:
                print("\n❌ No arbitrage opportunities found above threshold")
        
        return opportunities
    
    if args.watch:
        logger.info(f"Starting continuous monitoring (interval: {args.interval}s)")
        seen_ids = set()
        
        try:
            while True:
                opportunities = run_scan()
                
                # Alert on new opportunities
                for opp in opportunities:
                    if opp.id not in seen_ids:
                        logger.info(f"🆕 NEW: {opp.title} - Edge: {opp.edge_net:.2%}")
                        seen_ids.add(opp.id)
                
                time.sleep(args.interval)
                
        except KeyboardInterrupt:
            logger.info("Monitoring stopped")
    else:
        run_scan()


if __name__ == "__main__":
    main()
