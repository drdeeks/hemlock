#!/usr/bin/env python3
"""
Backtest trading signals over historical data.

Usage:
    python backtest.py NVDA --start 2025-01-01 --end 2026-01-01
    python backtest.py AAPL --start 2025-06-01 --interval weekly
"""

import argparse
import json
from datetime import datetime, timedelta
from typing import Optional
import yfinance as yf
from analyze import analyze_stock, calculate_indicators


def generate_signals(ticker: str, start_date: str, end_date: str, interval: str = "weekly") -> list:
    """Generate trading signals for a date range."""
    signals = []
    
    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")
    
    # Determine step size
    if interval == "daily":
        step = timedelta(days=1)
    elif interval == "weekly":
        step = timedelta(weeks=1)
    else:  # monthly
        step = timedelta(weeks=4)
    
    current_dt = start_dt
    while current_dt <= end_dt:
        date_str = current_dt.strftime("%Y-%m-%d")
        
        try:
            indicators = calculate_indicators(ticker)
            
            # Simple signal logic based on technicals
            rsi = indicators.get('rsi', 50)
            macd_hist = indicators.get('macd_histogram', 0)
            trend = indicators.get('trend', 'neutral')
            
            # Generate signal
            if rsi < 30 and macd_hist > 0:
                signal = "BUY"
                confidence = min(0.9, (30 - rsi) / 30 + 0.5)
            elif rsi > 70 and macd_hist < 0:
                signal = "SELL"
                confidence = min(0.9, (rsi - 70) / 30 + 0.5)
            elif trend == "bullish" and macd_hist > 0:
                signal = "HOLD_LONG"
                confidence = 0.6
            elif trend == "bearish" and macd_hist < 0:
                signal = "HOLD_SHORT"
                confidence = 0.6
            else:
                signal = "HOLD"
                confidence = 0.5
            
            signals.append({
                "date": date_str,
                "signal": signal,
                "confidence": round(confidence, 2),
                "rsi": round(rsi, 1),
                "macd_hist": round(macd_hist, 4) if macd_hist else 0,
                "trend": trend,
                "price": indicators.get('price', 0)
            })
            
        except Exception as e:
            signals.append({
                "date": date_str,
                "signal": "ERROR",
                "error": str(e)
            })
        
        current_dt += step
    
    return signals


def calculate_returns(ticker: str, signals: list, initial_capital: float = 10000) -> dict:
    """Calculate hypothetical returns from signals."""
    if not signals:
        return {"error": "No signals to evaluate"}
    
    # Get actual price data
    stock = yf.Ticker(ticker)
    start = signals[0]['date']
    end = signals[-1]['date']
    hist = stock.history(start=start, end=end)
    
    if hist.empty:
        return {"error": "No price data available"}
    
    # Simulate trading
    capital = initial_capital
    shares = 0
    trades = []
    
    for signal in signals:
        if signal.get('signal') == "ERROR":
            continue
            
        date = signal['date']
        try:
            price = float(hist.loc[hist.index.strftime('%Y-%m-%d') == date, 'Close'].iloc[0])
        except (IndexError, KeyError):
            continue
        
        if signal['signal'] == "BUY" and shares == 0:
            shares = capital / price
            capital = 0
            trades.append({"date": date, "action": "BUY", "price": price, "shares": shares})
        
        elif signal['signal'] == "SELL" and shares > 0:
            capital = shares * price
            trades.append({"date": date, "action": "SELL", "price": price, "capital": capital})
            shares = 0
    
    # Close any open position at end
    if shares > 0:
        final_price = float(hist['Close'].iloc[-1])
        capital = shares * final_price
        trades.append({"date": end, "action": "CLOSE", "price": final_price, "capital": capital})
    
    # Calculate metrics
    total_return = (capital - initial_capital) / initial_capital * 100
    
    # Buy and hold comparison
    first_price = float(hist['Close'].iloc[0])
    last_price = float(hist['Close'].iloc[-1])
    buy_hold_return = (last_price - first_price) / first_price * 100
    
    return {
        "initial_capital": initial_capital,
        "final_capital": round(capital, 2),
        "total_return_pct": round(total_return, 2),
        "buy_hold_return_pct": round(buy_hold_return, 2),
        "outperformance": round(total_return - buy_hold_return, 2),
        "total_trades": len(trades),
        "trades": trades
    }


def main():
    parser = argparse.ArgumentParser(description="Backtest trading signals")
    parser.add_argument("ticker", help="Stock ticker symbol")
    parser.add_argument("--start", "-s", required=True, help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end", "-e", default=datetime.now().strftime("%Y-%m-%d"),
                        help="End date (YYYY-MM-DD)")
    parser.add_argument("--interval", "-i", choices=["daily", "weekly", "monthly"],
                        default="weekly", help="Signal interval")
    parser.add_argument("--capital", "-c", type=float, default=10000,
                        help="Initial capital")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    
    args = parser.parse_args()
    
    print(f"Backtesting {args.ticker} from {args.start} to {args.end}...")
    
    # Generate signals
    signals = generate_signals(args.ticker.upper(), args.start, args.end, args.interval)
    
    # Calculate returns
    returns = calculate_returns(args.ticker.upper(), signals, args.capital)
    
    result = {
        "ticker": args.ticker.upper(),
        "period": f"{args.start} to {args.end}",
        "interval": args.interval,
        "signals": signals,
        "returns": returns
    }
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"\n# Backtest Results: {args.ticker.upper()}")
        print(f"**Period**: {args.start} to {args.end}")
        print(f"**Interval**: {args.interval}")
        print(f"**Total Signals**: {len(signals)}")
        print()
        print("## Performance")
        print(f"- Initial Capital: ${returns['initial_capital']:,.2f}")
        print(f"- Final Capital: ${returns['final_capital']:,.2f}")
        print(f"- **Strategy Return**: {returns['total_return_pct']:+.2f}%")
        print(f"- Buy & Hold Return: {returns['buy_hold_return_pct']:+.2f}%")
        print(f"- **Outperformance**: {returns['outperformance']:+.2f}%")
        print(f"- Total Trades: {returns['total_trades']}")
        
        print("\n## Signal Distribution")
        from collections import Counter
        signal_counts = Counter(s['signal'] for s in signals if s.get('signal') != 'ERROR')
        for signal, count in signal_counts.most_common():
            print(f"- {signal}: {count}")


if __name__ == "__main__":
    main()
