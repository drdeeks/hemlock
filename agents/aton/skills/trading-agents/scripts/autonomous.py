#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Autonomous Trading Agent

Runs continuous loop: scan → analyze → size → execute → monitor

Usage:
    python autonomous.py --mode paper
    python autonomous.py --mode live --interval 300
"""

import argparse
import json
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('autonomous_trading.log')
    ]
)
logger = logging.getLogger(__name__)

# Default config
DEFAULT_CONFIG = {
    "mode": "paper",
    "wallet": {
        "type": "smart_wallet",
        "provider": "base_account",
        "chain_id": 8453,
        "rpc_url": "https://mainnet.base.org"
    },
    "markets": {
        "prediction_markets": {
            "enabled": True,
            "platforms": ["polymarket"],
            "min_edge": 0.04,
            "max_position_pct": 0.05
        }
    },
    "risk": {
        "max_daily_loss_pct": 0.10,
        "max_position_pct": 0.15,
        "kelly_fraction": 0.25,
        "min_edge": 0.04
    },
    "bankroll": 1000.0
}


def load_config(config_path: str = "config.json") -> dict:
    """Load configuration from file or use defaults."""
    if os.path.exists(config_path):
        with open(config_path) as f:
            config = json.load(f)
            logger.info(f"Loaded config from {config_path}")
            return {**DEFAULT_CONFIG, **config}
    logger.warning(f"No config found at {config_path}, using defaults")
    return DEFAULT_CONFIG


def kelly_size(true_prob: float, market_price: float, bankroll: float, fraction: float = 0.25) -> float:
    """
    Calculate position size using Kelly Criterion.
    
    Args:
        true_prob: Estimated true probability (0-1)
        market_price: Current market price (0-1)
        bankroll: Total capital available
        fraction: Kelly fraction (0.25 = quarter-Kelly)
    
    Returns:
        Position size in dollars
    """
    if true_prob <= market_price:
        return 0.0
    
    edge = true_prob - market_price
    odds = (1 / market_price) - 1
    
    if odds <= 0:
        return 0.0
    
    kelly = (true_prob * odds - (1 - true_prob)) / odds
    
    # Apply fraction and caps
    size = kelly * fraction * bankroll
    max_size = bankroll * 0.15  # Max 15% per position
    
    return min(max(size, 0), max_size)


class TradingState:
    """Track trading state and P&L."""
    
    def __init__(self, state_path: str = "trading_state.json"):
        self.state_path = state_path
        self.positions = []
        self.trades = []
        self.daily_pnl = 0.0
        self.total_pnl = 0.0
        self.trade_count_today = 0
        self.last_reset = datetime.now().date().isoformat()
        self._load()
    
    def _load(self):
        if os.path.exists(self.state_path):
            with open(self.state_path) as f:
                data = json.load(f)
                self.positions = data.get("positions", [])
                self.trades = data.get("trades", [])
                self.daily_pnl = data.get("daily_pnl", 0.0)
                self.total_pnl = data.get("total_pnl", 0.0)
                self.trade_count_today = data.get("trade_count_today", 0)
                self.last_reset = data.get("last_reset", datetime.now().date().isoformat())
    
    def save(self):
        with open(self.state_path, 'w') as f:
            json.dump({
                "positions": self.positions,
                "trades": self.trades[-100:],  # Keep last 100 trades
                "daily_pnl": self.daily_pnl,
                "total_pnl": self.total_pnl,
                "trade_count_today": self.trade_count_today,
                "last_reset": self.last_reset
            }, f, indent=2, default=str)
    
    def reset_daily(self):
        today = datetime.now().date().isoformat()
        if today != self.last_reset:
            logger.info(f"Resetting daily stats. Yesterday P&L: ${self.daily_pnl:.2f}")
            self.daily_pnl = 0.0
            self.trade_count_today = 0
            self.last_reset = today
            self.save()
    
    def add_trade(self, trade: dict):
        trade["timestamp"] = datetime.now().isoformat()
        self.trades.append(trade)
        self.trade_count_today += 1
        self.save()
    
    def add_position(self, position: dict):
        position["opened_at"] = datetime.now().isoformat()
        self.positions.append(position)
        self.save()
    
    def close_position(self, position_id: str, pnl: float):
        self.positions = [p for p in self.positions if p.get("id") != position_id]
        self.daily_pnl += pnl
        self.total_pnl += pnl
        self.save()


class AutonomousTrader:
    """Main autonomous trading loop."""
    
    def __init__(self, config_path: str = "config.json"):
        self.config = load_config(config_path)
        self.state = TradingState()
        self.running = False
        self.mode = self.config.get("mode", "paper")
        self.bankroll = self.config.get("bankroll", 1000.0)
        
        logger.info(f"Initialized AutonomousTrader in {self.mode} mode")
        logger.info(f"Bankroll: ${self.bankroll:.2f}")
    
    def scan_opportunities(self) -> list:
        """Scan markets for trading opportunities."""
        opportunities = []
        
        # Scan prediction markets
        if self.config["markets"].get("prediction_markets", {}).get("enabled"):
            pm_opps = self._scan_prediction_markets()
            opportunities.extend(pm_opps)
        
        logger.info(f"Found {len(opportunities)} opportunities")
        return opportunities
    
    def _scan_prediction_markets(self) -> list:
        """Scan prediction markets for arbitrage."""
        opportunities = []
        platforms = self.config["markets"]["prediction_markets"].get("platforms", [])
        min_edge = self.config["markets"]["prediction_markets"].get("min_edge", 0.04)
        
        # Placeholder - in production, this would call actual APIs
        # For now, return simulated opportunities for testing
        logger.info(f"Scanning {platforms} for opportunities (min_edge={min_edge})")
        
        # Example simulated opportunity
        if self.mode == "paper":
            opportunities.append({
                "id": f"sim_{int(time.time())}",
                "platform": "polymarket",
                "market": "Example Market",
                "type": "math_arb",
                "edge": 0.05,
                "prob_sum": 0.95,
                "outcomes": [
                    {"name": "YES", "price": 0.48},
                    {"name": "NO", "price": 0.47}
                ],
                "volume": 1000000,
                "simulated": True
            })
        
        return [o for o in opportunities if o.get("edge", 0) >= min_edge]
    
    def analyze_opportunity(self, opportunity: dict) -> dict:
        """Run multi-agent analysis on opportunity."""
        logger.info(f"Analyzing opportunity: {opportunity.get('id')}")
        
        # For prediction markets, the "analysis" is mainly the edge calculation
        analysis = {
            "opportunity_id": opportunity["id"],
            "recommendation": "PASS",
            "confidence": 0.0,
            "position_size": 0.0,
            "reasoning": []
        }
        
        edge = opportunity.get("edge", 0)
        min_edge = self.config["risk"]["min_edge"]
        
        if edge < min_edge:
            analysis["reasoning"].append(f"Edge {edge:.1%} below minimum {min_edge:.1%}")
            return analysis
        
        # Check volume
        volume = opportunity.get("volume", 0)
        if volume < 100000:
            analysis["reasoning"].append(f"Volume ${volume:,} too low (min $100k)")
            return analysis
        
        # Calculate position size
        # For math arb, true_prob is effectively 1.0 (guaranteed profit)
        if opportunity.get("type") == "math_arb":
            true_prob = 1.0 - (0.02 * len(opportunity.get("outcomes", [])))  # Account for fees
            market_price = 1.0 - edge  # Effective price
        else:
            true_prob = opportunity.get("estimated_prob", 0.5)
            market_price = opportunity.get("market_price", 0.5)
        
        position_size = kelly_size(
            true_prob=true_prob,
            market_price=market_price,
            bankroll=self.bankroll,
            fraction=self.config["risk"]["kelly_fraction"]
        )
        
        # Apply position cap
        max_pos = self.bankroll * self.config["risk"]["max_position_pct"]
        position_size = min(position_size, max_pos)
        
        if position_size < 5:  # Minimum $5 trade
            analysis["reasoning"].append(f"Position size ${position_size:.2f} below minimum")
            return analysis
        
        analysis["recommendation"] = "TRADE"
        analysis["confidence"] = min(edge * 10, 1.0)  # Scale edge to confidence
        analysis["position_size"] = round(position_size, 2)
        analysis["reasoning"].append(f"Edge: {edge:.1%}")
        analysis["reasoning"].append(f"Volume: ${volume:,}")
        analysis["reasoning"].append(f"Position size: ${position_size:.2f}")
        
        return analysis
    
    def execute_trade(self, opportunity: dict, analysis: dict) -> Optional[dict]:
        """Execute a trade (paper or live)."""
        if analysis["recommendation"] != "TRADE":
            return None
        
        trade = {
            "id": f"trade_{int(time.time())}",
            "opportunity_id": opportunity["id"],
            "platform": opportunity.get("platform"),
            "market": opportunity.get("market"),
            "size": analysis["position_size"],
            "edge": opportunity.get("edge"),
            "mode": self.mode,
            "status": "pending"
        }
        
        if self.mode == "paper":
            logger.info(f"[PAPER] Would execute trade: {json.dumps(trade, indent=2)}")
            trade["status"] = "filled_paper"
            trade["fill_price"] = opportunity.get("outcomes", [{}])[0].get("price", 0)
        else:
            # Live execution would go here
            logger.info(f"[LIVE] Executing trade: {json.dumps(trade, indent=2)}")
            # trade = self._execute_live_trade(opportunity, analysis)
            trade["status"] = "live_execution_not_implemented"
        
        self.state.add_trade(trade)
        
        if trade["status"] in ["filled_paper", "filled"]:
            self.state.add_position({
                "id": trade["id"],
                "platform": trade["platform"],
                "market": trade["market"],
                "size": trade["size"],
                "entry_edge": trade["edge"]
            })
        
        return trade
    
    def check_risk_limits(self) -> bool:
        """Check if trading should continue based on risk limits."""
        # Daily loss limit
        max_daily_loss = self.bankroll * self.config["risk"]["max_daily_loss_pct"]
        if self.state.daily_pnl <= -max_daily_loss:
            logger.warning(f"Daily loss limit hit: ${self.state.daily_pnl:.2f}")
            return False
        
        # Max positions
        if len(self.state.positions) >= 10:
            logger.warning("Max positions (10) reached")
            return False
        
        # Max daily trades
        if self.state.trade_count_today >= 20:
            logger.warning("Max daily trades (20) reached")
            return False
        
        return True
    
    def run_once(self):
        """Run a single iteration of the trading loop."""
        logger.info("=" * 50)
        logger.info("Starting scan iteration")
        
        # Reset daily stats if needed
        self.state.reset_daily()
        
        # Check risk limits
        if not self.check_risk_limits():
            logger.info("Risk limits prevent trading")
            return
        
        # Scan for opportunities
        opportunities = self.scan_opportunities()
        
        for opp in opportunities:
            # Analyze each opportunity
            analysis = self.analyze_opportunity(opp)
            
            if analysis["recommendation"] == "TRADE":
                # Execute trade
                trade = self.execute_trade(opp, analysis)
                if trade:
                    logger.info(f"Trade executed: {trade['id']}")
    
    def start(self, interval: int = 300, max_iterations: Optional[int] = None):
        """Start the autonomous trading loop."""
        self.running = True
        iteration = 0
        
        logger.info(f"Starting autonomous trading loop (interval={interval}s)")
        
        try:
            while self.running:
                self.run_once()
                iteration += 1
                
                if max_iterations and iteration >= max_iterations:
                    logger.info(f"Reached max iterations ({max_iterations})")
                    break
                
                logger.info(f"Sleeping {interval}s until next scan...")
                time.sleep(interval)
                
        except KeyboardInterrupt:
            logger.info("Received interrupt, stopping...")
        finally:
            self.running = False
            logger.info("Trading loop stopped")
            logger.info(f"Final stats: Daily P&L=${self.state.daily_pnl:.2f}, Total P&L=${self.state.total_pnl:.2f}")
    
    def stop(self):
        """Stop the trading loop."""
        self.running = False


def main():
    parser = argparse.ArgumentParser(description="Autonomous Trading Agent")
    parser.add_argument("--mode", choices=["paper", "live"], default="paper",
                        help="Trading mode (default: paper)")
    parser.add_argument("--config", default="config.json",
                        help="Path to config file")
    parser.add_argument("--interval", type=int, default=300,
                        help="Scan interval in seconds (default: 300)")
    parser.add_argument("--once", action="store_true",
                        help="Run once and exit")
    parser.add_argument("--max-iterations", type=int,
                        help="Maximum iterations before stopping")
    
    args = parser.parse_args()
    
    # Override mode in config
    if os.path.exists(args.config):
        with open(args.config) as f:
            config = json.load(f)
        config["mode"] = args.mode
        with open(args.config, 'w') as f:
            json.dump(config, f, indent=2)
    
    trader = AutonomousTrader(config_path=args.config)
    trader.mode = args.mode
    
    if args.once:
        trader.run_once()
    else:
        trader.start(interval=args.interval, max_iterations=args.max_iterations)


if __name__ == "__main__":
    main()
