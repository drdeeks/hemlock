#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Wallet Setup and Configuration

Setup smart wallet or private key wallet for autonomous trading.

Usage:
    python wallet_setup.py --type smart_wallet --chain base
    python wallet_setup.py --type private_key --verify
    python wallet_setup.py --balance
"""

import argparse
import json
import os
from typing import Optional
from dataclasses import dataclass

# Chain configurations
CHAINS = {
    "base": {
        "chain_id": 8453,
        "name": "Base Mainnet",
        "rpc": "https://mainnet.base.org",
        "explorer": "https://basescan.org",
        "native": "ETH",
        "usdc": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    },
    "base_sepolia": {
        "chain_id": 84532,
        "name": "Base Sepolia",
        "rpc": "https://sepolia.base.org",
        "explorer": "https://sepolia.basescan.org",
        "native": "ETH",
        "usdc": "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
    },
    "polygon": {
        "chain_id": 137,
        "name": "Polygon Mainnet",
        "rpc": "https://polygon-rpc.com",
        "explorer": "https://polygonscan.com",
        "native": "MATIC",
        "usdc": "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359"
    },
    "arbitrum": {
        "chain_id": 42161,
        "name": "Arbitrum One",
        "rpc": "https://arb1.arbitrum.io/rpc",
        "explorer": "https://arbiscan.io",
        "native": "ETH",
        "usdc": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
    }
}


@dataclass
class WalletConfig:
    """Wallet configuration."""
    wallet_type: str  # smart_wallet, private_key
    address: Optional[str] = None
    chain: str = "base"
    paymaster_url: Optional[str] = None
    

def create_smart_wallet_config(chain: str = "base") -> dict:
    """
    Generate configuration for Coinbase Smart Wallet.
    
    Smart wallets use ERC-4337 account abstraction:
    - Gasless transactions via paymaster
    - Batch multiple operations
    - Social recovery
    - No private key management
    """
    chain_config = CHAINS.get(chain, CHAINS["base"])
    
    config = {
        "wallet": {
            "type": "smart_wallet",
            "provider": "base_account",
            "chain_id": chain_config["chain_id"],
            "chain_name": chain_config["name"],
            "rpc_url": chain_config["rpc"],
            "usdc_address": chain_config["usdc"],
            "setup_instructions": [
                "1. User authenticates via Base Account popup",
                "2. Smart wallet is created/connected automatically",
                "3. Transactions are signed in the wallet UI",
                "4. Paymaster sponsors gas (if configured)"
            ],
            "integration": {
                "sdk": "@base-org/account",
                "install": "npm install @base-org/account",
                "example": """
import { createBaseAccountSDK } from '@base-org/account';

const sdk = createBaseAccountSDK({
  appName: 'Trading Agents',
  appChainIds: [8453],
});

// Get provider for transactions
const provider = sdk.getProvider();

// Connect wallet
const { accounts } = await provider.request({
  method: 'wallet_connect',
  params: [{ version: '1' }]
});

// Send transaction
const tx = await provider.request({
  method: 'eth_sendTransaction',
  params: [{
    from: accounts[0].address,
    to: RECIPIENT,
    data: ENCODED_DATA
  }]
});
"""
            }
        }
    }
    
    # Add paymaster info if available
    paymaster_url = os.environ.get("PAYMASTER_URL")
    if paymaster_url:
        config["wallet"]["paymaster_url"] = paymaster_url
        config["wallet"]["gasless"] = True
    
    return config


def create_private_key_config(chain: str = "base") -> dict:
    """
    Generate configuration for private key wallet.
    
    For server-side autonomous operation where user approval
    isn't required for each transaction.
    
    ⚠️ SECURITY WARNING: Store private key securely!
    Use environment variable, never commit to code.
    """
    chain_config = CHAINS.get(chain, CHAINS["base"])
    
    # Check if private key is set
    private_key = os.environ.get("TRADING_PRIVATE_KEY")
    address = None
    
    if private_key:
        try:
            from eth_account import Account
            account = Account.from_key(private_key)
            address = account.address
        except ImportError:
            print("⚠️  Install web3: pip install web3")
        except Exception as e:
            print(f"⚠️  Invalid private key: {e}")
    
    config = {
        "wallet": {
            "type": "private_key",
            "chain_id": chain_config["chain_id"],
            "chain_name": chain_config["name"],
            "rpc_url": chain_config["rpc"],
            "usdc_address": chain_config["usdc"],
            "address": address,
            "env_var": "TRADING_PRIVATE_KEY",
            "setup_instructions": [
                "1. Generate or use existing Ethereum wallet",
                "2. Export private key from wallet",
                "3. Set environment variable: export TRADING_PRIVATE_KEY=0x...",
                "4. Fund wallet with ETH (gas) and USDC (trading)",
                "⚠️  NEVER commit private key to code or version control"
            ],
            "integration": {
                "example": """
from web3 import Web3
from eth_account import Account
import os

# Load credentials
private_key = os.environ['TRADING_PRIVATE_KEY']
account = Account.from_key(private_key)

# Connect to chain
w3 = Web3(Web3.HTTPProvider(RPC_URL))

# Build transaction
tx = {
    'from': account.address,
    'to': RECIPIENT,
    'value': 0,
    'data': ENCODED_DATA,
    'gas': 200000,
    'gasPrice': w3.eth.gas_price,
    'nonce': w3.eth.get_transaction_count(account.address)
}

# Sign and send
signed = account.sign_transaction(tx)
tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
"""
            }
        }
    }
    
    return config


def check_balance(address: str, chain: str = "base") -> dict:
    """Check wallet balance for ETH and USDC."""
    try:
        from web3 import Web3
    except ImportError:
        return {"error": "Install web3: pip install web3"}
    
    chain_config = CHAINS.get(chain, CHAINS["base"])
    w3 = Web3(Web3.HTTPProvider(chain_config["rpc"]))
    
    if not w3.is_connected():
        return {"error": f"Cannot connect to {chain_config['name']}"}
    
    # Get ETH balance
    eth_balance = w3.eth.get_balance(address)
    eth_balance_formatted = w3.from_wei(eth_balance, 'ether')
    
    # Get USDC balance
    usdc_balance = 0
    try:
        usdc_abi = [{"constant":True,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}]
        usdc_contract = w3.eth.contract(address=chain_config["usdc"], abi=usdc_abi)
        usdc_balance = usdc_contract.functions.balanceOf(address).call()
        usdc_balance = usdc_balance / 10**6  # USDC has 6 decimals
    except Exception as e:
        usdc_balance = f"Error: {e}"
    
    return {
        "address": address,
        "chain": chain_config["name"],
        "balances": {
            chain_config["native"]: float(eth_balance_formatted),
            "USDC": usdc_balance
        }
    }


def generate_config_file(wallet_type: str, chain: str, output: str = "config.json"):
    """Generate a complete config file."""
    
    if wallet_type == "smart_wallet":
        wallet_config = create_smart_wallet_config(chain)
    else:
        wallet_config = create_private_key_config(chain)
    
    full_config = {
        "mode": "paper",
        **wallet_config,
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
        "bankroll": 1000.0,
        "alerts": {
            "telegram_bot_token": "",
            "telegram_chat_id": ""
        }
    }
    
    with open(output, 'w') as f:
        json.dump(full_config, f, indent=2)
    
    print(f"✅ Config written to {output}")
    return full_config


def main():
    parser = argparse.ArgumentParser(description="Wallet Setup for Trading Agents")
    parser.add_argument("--type", choices=["smart_wallet", "private_key"], default="smart_wallet",
                        help="Wallet type (default: smart_wallet)")
    parser.add_argument("--chain", choices=list(CHAINS.keys()), default="base",
                        help="Blockchain network (default: base)")
    parser.add_argument("--output", default="config.json",
                        help="Output config file path")
    parser.add_argument("--balance", metavar="ADDRESS",
                        help="Check balance for address")
    parser.add_argument("--verify", action="store_true",
                        help="Verify private key from environment")
    parser.add_argument("--show-chains", action="store_true",
                        help="Show supported chains")
    
    args = parser.parse_args()
    
    if args.show_chains:
        print("\nSupported Chains:")
        print("-" * 50)
        for name, config in CHAINS.items():
            print(f"\n{name}:")
            print(f"  Chain ID: {config['chain_id']}")
            print(f"  Name: {config['name']}")
            print(f"  RPC: {config['rpc']}")
            print(f"  Native: {config['native']}")
        return
    
    if args.balance:
        print(f"\nChecking balance for {args.balance} on {args.chain}...")
        result = check_balance(args.balance, args.chain)
        print(json.dumps(result, indent=2))
        return
    
    if args.verify:
        private_key = os.environ.get("TRADING_PRIVATE_KEY")
        if not private_key:
            print("❌ TRADING_PRIVATE_KEY not set in environment")
            return
        try:
            from eth_account import Account
            account = Account.from_key(private_key)
            print(f"✅ Valid private key")
            print(f"   Address: {account.address}")
            
            # Check balance
            result = check_balance(account.address, args.chain)
            if "error" not in result:
                print(f"   {args.chain} balances: {result['balances']}")
        except Exception as e:
            print(f"❌ Invalid private key: {e}")
        return
    
    # Generate config
    print(f"\n🔧 Setting up {args.type} wallet on {args.chain}")
    print("-" * 50)
    
    config = generate_config_file(args.type, args.chain, args.output)
    
    print("\n📋 Next Steps:")
    for i, step in enumerate(config["wallet"]["setup_instructions"], 1):
        print(f"   {step}")
    
    if args.type == "smart_wallet":
        print("\n💡 Smart Wallet Benefits:")
        print("   - Gasless transactions (with paymaster)")
        print("   - No private key management")
        print("   - Batch multiple operations")
        print("   - Social recovery options")
    else:
        print("\n⚠️  Private Key Security:")
        print("   - Never commit to version control")
        print("   - Use environment variables only")
        print("   - Consider hardware wallet for large amounts")


if __name__ == "__main__":
    main()
