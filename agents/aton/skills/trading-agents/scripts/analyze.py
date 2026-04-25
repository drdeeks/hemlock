#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Trading Agents - Multi-agent stock analysis CLI

Usage:
    python analyze.py NVDA
    python analyze.py AAPL --date 2026-01-15
    python analyze.py TSLA --debug --rounds 2
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from typing import Optional
import yfinance as yf


def get_stock_data(ticker: str, start_date: str, end_date: str) -> dict:
    """Fetch OHLCV data from yfinance."""
    stock = yf.Ticker(ticker)
    hist = stock.history(start=start_date, end=end_date)
    if hist.empty:
        return {"error": f"No data found for {ticker}"}
    return {
        "ticker": ticker,
        "period": f"{start_date} to {end_date}",
        "data": hist.tail(10).to_dict(),
        "latest_close": float(hist['Close'].iloc[-1]),
        "change_pct": float((hist['Close'].iloc[-1] / hist['Close'].iloc[0] - 1) * 100)
    }


def get_fundamentals(ticker: str) -> dict:
    """Fetch fundamental data from yfinance."""
    stock = yf.Ticker(ticker)
    info = stock.info
    return {
        "ticker": ticker,
        "name": info.get("longName", ticker),
        "sector": info.get("sector", "Unknown"),
        "industry": info.get("industry", "Unknown"),
        "market_cap": info.get("marketCap"),
        "pe_ratio": info.get("trailingPE"),
        "forward_pe": info.get("forwardPE"),
        "pb_ratio": info.get("priceToBook"),
        "dividend_yield": info.get("dividendYield"),
        "revenue": info.get("totalRevenue"),
        "profit_margin": info.get("profitMargins"),
        "roe": info.get("returnOnEquity"),
        "debt_to_equity": info.get("debtToEquity"),
        "current_ratio": info.get("currentRatio"),
        "free_cash_flow": info.get("freeCashflow"),
        "52w_high": info.get("fiftyTwoWeekHigh"),
        "52w_low": info.get("fiftyTwoWeekLow"),
        "avg_volume": info.get("averageVolume"),
        "beta": info.get("beta"),
    }


def get_news(ticker: str) -> list:
    """Fetch recent news from yfinance."""
    stock = yf.Ticker(ticker)
    try:
        news_data = stock.news if hasattr(stock, 'news') else []
        if not news_data:
            return []
        return [
            {
                "title": n.get("title", n.get("content", {}).get("title", "")),
                "publisher": n.get("publisher", n.get("content", {}).get("provider", {}).get("displayName", "")),
                "link": n.get("link", n.get("content", {}).get("canonicalUrl", {}).get("url", "")),
                "published": n.get("providerPublishTime", "")
            }
            for n in news_data[:10]
        ]
    except Exception:
        return []


def calculate_indicators(ticker: str, lookback_days: int = 30) -> dict:
    """Calculate technical indicators."""
    stock = yf.Ticker(ticker)
    end_date = datetime.now()
    start_date = end_date - timedelta(days=lookback_days + 50)  # Extra for calculations
    hist = stock.history(start=start_date.strftime("%Y-%m-%d"), end=end_date.strftime("%Y-%m-%d"))
    
    if hist.empty or len(hist) < 20:
        return {"error": "Insufficient data for indicators"}
    
    close = hist['Close']
    
    # RSI
    delta = close.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    
    # MACD
    ema12 = close.ewm(span=12, adjust=False).mean()
    ema26 = close.ewm(span=26, adjust=False).mean()
    macd = ema12 - ema26
    signal = macd.ewm(span=9, adjust=False).mean()
    
    # Bollinger Bands
    sma20 = close.rolling(window=20).mean()
    std20 = close.rolling(window=20).std()
    bb_upper = sma20 + (std20 * 2)
    bb_lower = sma20 - (std20 * 2)
    
    # SMAs
    sma50 = close.rolling(window=50).mean() if len(close) >= 50 else close.rolling(window=20).mean()
    
    return {
        "ticker": ticker,
        "rsi": float(rsi.iloc[-1]) if not rsi.empty else None,
        "macd": float(macd.iloc[-1]) if not macd.empty else None,
        "macd_signal": float(signal.iloc[-1]) if not signal.empty else None,
        "macd_histogram": float((macd - signal).iloc[-1]) if not macd.empty else None,
        "bollinger_upper": float(bb_upper.iloc[-1]) if not bb_upper.empty else None,
        "bollinger_lower": float(bb_lower.iloc[-1]) if not bb_lower.empty else None,
        "bollinger_mid": float(sma20.iloc[-1]) if not sma20.empty else None,
        "sma_20": float(sma20.iloc[-1]) if not sma20.empty else None,
        "sma_50": float(sma50.iloc[-1]) if not sma50.empty else None,
        "price": float(close.iloc[-1]),
        "trend": "bullish" if float(close.iloc[-1]) > float(sma20.iloc[-1]) else "bearish",
        "rsi_signal": "overbought" if float(rsi.iloc[-1]) > 70 else ("oversold" if float(rsi.iloc[-1]) < 30 else "neutral"),
    }


def format_report(data: dict, section: str) -> str:
    """Format data into a readable report section."""
    lines = [f"\n### {section}\n"]
    for key, value in data.items():
        if value is not None and key not in ['ticker', 'error']:
            if isinstance(value, float):
                lines.append(f"- **{key.replace('_', ' ').title()}**: {value:.2f}")
            elif isinstance(value, dict):
                continue  # Skip nested dicts in summary
            else:
                lines.append(f"- **{key.replace('_', ' ').title()}**: {value}")
    return "\n".join(lines)


def analyze_stock(
    ticker: str,
    analysis_date: Optional[str] = None,
    debug: bool = False,
    debate_rounds: int = 1
) -> dict:
    """
    Run multi-agent analysis on a stock.
    
    This is a simplified version that gathers data and formats it for LLM analysis.
    The actual agent orchestration happens via the OpenClaw subagent system.
    """
    if analysis_date:
        end_date = analysis_date
        start_dt = datetime.strptime(analysis_date, "%Y-%m-%d") - timedelta(days=30)
        start_date = start_dt.strftime("%Y-%m-%d")
    else:
        end_date = datetime.now().strftime("%Y-%m-%d")
        start_date = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")
    
    if debug:
        print(f"[DEBUG] Analyzing {ticker} for {end_date}")
    
    # Gather all data
    price_data = get_stock_data(ticker, start_date, end_date)
    fundamentals = get_fundamentals(ticker)
    indicators = calculate_indicators(ticker)
    news = get_news(ticker)
    
    if debug:
        print(f"[DEBUG] Price data: {price_data.get('latest_close', 'N/A')}")
        print(f"[DEBUG] RSI: {indicators.get('rsi', 'N/A')}")
        print(f"[DEBUG] News items: {len(news)}")
    
    # Build analysis context
    context = {
        "ticker": ticker,
        "date": end_date,
        "price_data": price_data,
        "fundamentals": fundamentals,
        "technical": indicators,
        "news": news,
        "debate_rounds": debate_rounds,
    }
    
    # Format for display/LLM consumption
    report = f"""
# Trading Analysis: {ticker}
**Date**: {end_date}
**Company**: {fundamentals.get('name', ticker)}
**Sector**: {fundamentals.get('sector', 'Unknown')} | **Industry**: {fundamentals.get('industry', 'Unknown')}

## Current Price
- **Latest Close**: ${price_data.get('latest_close', 'N/A'):.2f}
- **30-Day Change**: {price_data.get('change_pct', 0):.2f}%
- **52-Week Range**: ${fundamentals.get('52w_low', 0):.2f} - ${fundamentals.get('52w_high', 0):.2f}

{format_report(fundamentals, 'Fundamentals')}

{format_report(indicators, 'Technical Indicators')}

### Recent News
"""
    for n in news[:5]:
        report += f"- {n['title']} ({n['publisher']})\n"
    
    report += f"""

## Analysis Summary

**Technical Outlook**: {indicators.get('trend', 'Unknown').upper()}
- RSI ({indicators.get('rsi', 0):.1f}): {indicators.get('rsi_signal', 'neutral')}
- MACD Histogram: {'Bullish' if indicators.get('macd_histogram', 0) > 0 else 'Bearish'}
- Price vs SMA20: {'Above' if indicators.get('price', 0) > indicators.get('sma_20', 0) else 'Below'}

**Valuation**:
- P/E Ratio: {fundamentals.get('pe_ratio', 'N/A')}
- P/B Ratio: {fundamentals.get('pb_ratio', 'N/A')}
- Profit Margin: {fundamentals.get('profit_margin', 0)*100 if fundamentals.get('profit_margin') else 'N/A'}%

---
*Data sourced from yfinance. Not financial advice.*
"""
    
    return {
        "ticker": ticker,
        "date": end_date,
        "report": report,
        "data": context,
        "raw": {
            "price": price_data,
            "fundamentals": fundamentals,
            "technical": indicators,
            "news": news
        }
    }


def main():
    parser = argparse.ArgumentParser(
        description="Multi-agent stock analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python analyze.py NVDA
    python analyze.py AAPL --date 2026-01-15
    python analyze.py TSLA --debug --json
        """
    )
    parser.add_argument("ticker", help="Stock ticker symbol (e.g., NVDA, AAPL)")
    parser.add_argument("--date", "-d", help="Analysis date (YYYY-MM-DD), default: today")
    parser.add_argument("--debug", action="store_true", help="Show debug output")
    parser.add_argument("--json", action="store_true", help="Output raw JSON data")
    parser.add_argument("--rounds", type=int, default=1, help="Debate rounds (default: 1)")
    
    args = parser.parse_args()
    
    result = analyze_stock(
        ticker=args.ticker.upper(),
        analysis_date=args.date,
        debug=args.debug,
        debate_rounds=args.rounds
    )
    
    if args.json:
        print(json.dumps(result["data"], indent=2, default=str))
    else:
        print(result["report"])


if __name__ == "__main__":
    main()
