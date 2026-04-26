#!/usr/bin/env python3
"""
Batch analysis for multiple tickers.

Usage:
    python batch_analyze.py NVDA AAPL TSLA MSFT
    python batch_analyze.py --watchlist tech
    python batch_analyze.py --file tickers.txt --output results.json
"""

import argparse
import json
import sys
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from analyze import analyze_stock

WATCHLISTS = {
    "tech": ["NVDA", "AAPL", "MSFT", "GOOGL", "META", "AMZN", "TSLA"],
    "finance": ["JPM", "BAC", "GS", "MS", "WFC", "C"],
    "healthcare": ["UNH", "JNJ", "PFE", "ABBV", "MRK", "LLY"],
    "energy": ["XOM", "CVX", "COP", "SLB", "EOG"],
    "mag7": ["NVDA", "AAPL", "MSFT", "GOOGL", "META", "AMZN", "TSLA"],
}


def analyze_batch(
    tickers: list,
    analysis_date: str = None,
    max_workers: int = 4,
    debug: bool = False
) -> dict:
    """Analyze multiple tickers in parallel."""
    results = {}
    errors = []
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_ticker = {
            executor.submit(analyze_stock, ticker, analysis_date, debug): ticker
            for ticker in tickers
        }
        
        for future in as_completed(future_to_ticker):
            ticker = future_to_ticker[future]
            try:
                result = future.result()
                results[ticker] = result
                print(f"✓ {ticker}")
            except Exception as e:
                errors.append({"ticker": ticker, "error": str(e)})
                print(f"✗ {ticker}: {e}")
    
    return {
        "date": analysis_date or datetime.now().strftime("%Y-%m-%d"),
        "tickers_analyzed": len(results),
        "errors": errors,
        "results": results
    }


def generate_summary(batch_results: dict) -> str:
    """Generate a summary report from batch results."""
    lines = [
        f"# Batch Analysis Summary",
        f"**Date**: {batch_results['date']}",
        f"**Tickers Analyzed**: {batch_results['tickers_analyzed']}",
        "",
        "| Ticker | Price | 30D Change | RSI | Trend | P/E |",
        "|--------|-------|------------|-----|-------|-----|"
    ]
    
    for ticker, data in batch_results['results'].items():
        raw = data.get('raw', {})
        price = raw.get('price', {}).get('latest_close', 0)
        change = raw.get('price', {}).get('change_pct', 0)
        rsi = raw.get('technical', {}).get('rsi', 0)
        trend = raw.get('technical', {}).get('trend', 'N/A')
        pe = raw.get('fundamentals', {}).get('pe_ratio', 'N/A')
        
        lines.append(
            f"| {ticker} | ${price:.2f} | {change:+.1f}% | {rsi:.0f} | {trend} | {pe} |"
        )
    
    if batch_results['errors']:
        lines.extend([
            "",
            "## Errors",
            *[f"- {e['ticker']}: {e['error']}" for e in batch_results['errors']]
        ])
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Batch stock analysis")
    parser.add_argument("tickers", nargs="*", help="Ticker symbols")
    parser.add_argument("--watchlist", "-w", choices=list(WATCHLISTS.keys()),
                        help="Use predefined watchlist")
    parser.add_argument("--file", "-f", help="File with tickers (one per line)")
    parser.add_argument("--date", "-d", help="Analysis date (YYYY-MM-DD)")
    parser.add_argument("--output", "-o", help="Output JSON file")
    parser.add_argument("--workers", type=int, default=4, help="Parallel workers")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--json", action="store_true", help="Output JSON only")
    
    args = parser.parse_args()
    
    # Collect tickers from all sources
    tickers = list(args.tickers) if args.tickers else []
    
    if args.watchlist:
        tickers.extend(WATCHLISTS[args.watchlist])
    
    if args.file:
        with open(args.file) as f:
            tickers.extend([line.strip().upper() for line in f if line.strip()])
    
    # Remove duplicates while preserving order
    tickers = list(dict.fromkeys(tickers))
    
    if not tickers:
        parser.error("No tickers specified. Use positional args, --watchlist, or --file")
    
    print(f"Analyzing {len(tickers)} tickers...")
    results = analyze_batch(tickers, args.date, args.workers, args.debug)
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        print(f"\nResults saved to {args.output}")
    
    if args.json:
        print(json.dumps(results, indent=2, default=str))
    else:
        print("\n" + generate_summary(results))


if __name__ == "__main__":
    main()
