#!/usr/bin/env python3
"""
ERC-8004 Agent Onboarding Script

Creates an on-chain identity for an autonomous trading agent:
1. Generates or loads agent keypair
2. Pins registration metadata to IPFS via wayMint API
3. Registers identity on Base or Celo
4. Optionally transfers ownership to operator
5. Sets agent wallet for receiving payments

Usage:
    # Full onboarding (interactive)
    python onboard_agent.py --name "TradingBot" --chain base
    
    # With operator transfer
    python onboard_agent.py --name "TradingBot" --chain base --operator 0x12F1B38DC35AA65B50E5849d02559078953aE24b
    
    # Using existing OpenClaw identity
    python onboard_agent.py --name "TradingBot" --chain celo --use-openclaw-key
"""

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

# Optional imports - graceful degradation
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

try:
    from eth_account import Account
    from web3 import Web3
    HAS_WEB3 = True
except ImportError:
    HAS_WEB3 = False

# =============================================================================
# CONSTANTS
# =============================================================================

REGISTRIES = {
    "base": {
        "chain_id": 8453,
        "registry": "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
        "rpc": "https://mainnet.base.org",
        "proof_method": "basename-siwe",
        "namespace": "eip155:8453"
    },
    "celo": {
        "chain_id": 42220,
        "registry": "0xaC3DF9ABf80d0F5c020C06B04Cced27763355944",
        "rpc": "https://forno.celo.org",
        "proof_method": "self-protocol",
        "namespace": "eip155:42220"
    }
}

WAYMINT_API = "https://8004.way.je"
OPENCLAW_IDENTITY_PATH = Path.home() / ".openclaw" / "identity" / "device.json"

# Minimal ABI for ERC-8004 IdentityRegistry
REGISTRY_ABI = [
    {"type": "function", "name": "register", "inputs": [{"name": "agentURI", "type": "string"}], "outputs": [{"name": "agentId", "type": "uint256"}], "stateMutability": "nonpayable"},
    {"type": "function", "name": "register", "inputs": [], "outputs": [{"name": "agentId", "type": "uint256"}], "stateMutability": "nonpayable"},
    {"type": "function", "name": "setAgentURI", "inputs": [{"name": "agentId", "type": "uint256"}, {"name": "newURI", "type": "string"}], "outputs": [], "stateMutability": "nonpayable"},
    {"type": "function", "name": "setAgentWallet", "inputs": [{"name": "agentId", "type": "uint256"}, {"name": "newWallet", "type": "address"}, {"name": "deadline", "type": "uint256"}, {"name": "signature", "type": "bytes"}], "outputs": [], "stateMutability": "nonpayable"},
    {"type": "function", "name": "getAgentWallet", "inputs": [{"name": "agentId", "type": "uint256"}], "outputs": [{"name": "", "type": "address"}], "stateMutability": "view"},
    {"type": "function", "name": "ownerOf", "inputs": [{"name": "tokenId", "type": "uint256"}], "outputs": [{"name": "", "type": "address"}], "stateMutability": "view"},
    {"type": "function", "name": "transferFrom", "inputs": [{"name": "from", "type": "address"}, {"name": "to", "type": "address"}, {"name": "tokenId", "type": "uint256"}], "outputs": [], "stateMutability": "nonpayable"},
    {"type": "function", "name": "balanceOf", "inputs": [{"name": "owner", "type": "address"}], "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view"},
]

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def load_openclaw_keypair():
    """Load Ed25519 keypair from OpenClaw identity file."""
    if not OPENCLAW_IDENTITY_PATH.exists():
        return None
    
    with open(OPENCLAW_IDENTITY_PATH) as f:
        data = json.load(f)
    
    return {
        "device_id": data.get("deviceId"),
        "public_key_pem": data.get("publicKeyPem"),
        "private_key_pem": data.get("privateKeyPem")
    }


def extract_ed25519_pubkey_hex(pem: str) -> str:
    """Extract raw 32-byte Ed25519 public key from PEM as hex."""
    # Remove PEM headers and decode base64
    b64 = pem.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replace("\n", "")
    der = base64.b64decode(b64)
    # Last 32 bytes of SPKI DER are the raw public key
    return der[-32:].hex()


def generate_eth_keypair():
    """Generate a new Ethereum keypair."""
    if not HAS_WEB3:
        raise RuntimeError("web3 not installed. Run: pip install web3")
    
    account = Account.create()
    return {
        "address": account.address,
        "private_key": account.key.hex()
    }


def pin_metadata(name: str, description: str, services: list = None, image: str = None) -> str:
    """Pin agent registration metadata to IPFS via wayMint API."""
    if not HAS_REQUESTS:
        raise RuntimeError("requests not installed. Run: pip install requests")
    
    payload = {
        "name": name,
        "description": description,
        "services": services or [],
        "supportedTrust": ["reputation"]
    }
    if image:
        payload["image"] = image
    
    resp = requests.post(
        f"{WAYMINT_API}/api/pin",
        json=payload,
        headers={"Content-Type": "application/json"},
        timeout=30
    )
    resp.raise_for_status()
    data = resp.json()
    return f"ipfs://{data['cid']}"


def create_data_uri(registration_data: dict) -> str:
    """Create a base64-encoded data URI for on-chain metadata storage."""
    json_str = json.dumps(registration_data, separators=(',', ':'))
    b64 = base64.b64encode(json_str.encode()).decode()
    return f"data:application/json;base64,{b64}"


def build_registration_file(
    name: str,
    description: str,
    chain: str,
    agent_id: int = None,
    services: list = None,
    image: str = None
) -> dict:
    """Build ERC-8004 compliant registration file."""
    registry_info = REGISTRIES[chain]
    
    registration = {
        "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
        "name": name,
        "description": description,
        "services": services or [
            {"name": "trading", "endpoint": "autonomous-trading-agent"}
        ],
        "x402Support": False,
        "active": True,
        "supportedTrust": ["reputation"]
    }
    
    if image:
        registration["image"] = image
    
    if agent_id is not None:
        registration["registrations"] = [{
            "agentId": agent_id,
            "agentRegistry": f"{registry_info['namespace']}:{registry_info['registry']}"
        }]
    
    return registration


def register_on_chain(
    private_key: str,
    chain: str,
    agent_uri: str,
    dry_run: bool = False
) -> dict:
    """Register agent identity on-chain."""
    if not HAS_WEB3:
        raise RuntimeError("web3 not installed. Run: pip install web3")
    
    registry_info = REGISTRIES[chain]
    w3 = Web3(Web3.HTTPProvider(registry_info["rpc"]))
    account = Account.from_key(private_key)
    
    contract = w3.eth.contract(
        address=Web3.to_checksum_address(registry_info["registry"]),
        abi=REGISTRY_ABI
    )
    
    if dry_run:
        return {
            "status": "dry_run",
            "chain": chain,
            "registry": registry_info["registry"],
            "from": account.address,
            "agent_uri": agent_uri
        }
    
    # Build transaction
    nonce = w3.eth.get_transaction_count(account.address)
    
    # Use register(string agentURI) overload
    tx = contract.functions.register(agent_uri).build_transaction({
        "from": account.address,
        "nonce": nonce,
        "gas": 300000,
        "gasPrice": w3.eth.gas_price,
        "chainId": registry_info["chain_id"]
    })
    
    # Sign and send
    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    
    print(f"Transaction sent: {tx_hash.hex()}")
    print("Waiting for confirmation...")
    
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    
    # Parse Registered event to get agentId
    agent_id = None
    for log in receipt.logs:
        # Registered event topic
        if len(log.topics) >= 2:
            agent_id = int(log.topics[1].hex(), 16)
            break
    
    return {
        "status": "success" if receipt.status == 1 else "failed",
        "tx_hash": tx_hash.hex(),
        "agent_id": agent_id,
        "chain": chain,
        "registry": registry_info["registry"],
        "owner": account.address,
        "certificate_url": f"{WAYMINT_API}/agent/{chain}:{agent_id}" if agent_id else None
    }


def transfer_ownership(
    private_key: str,
    chain: str,
    agent_id: int,
    new_owner: str,
    dry_run: bool = False
) -> dict:
    """Transfer agent NFT ownership to operator."""
    if not HAS_WEB3:
        raise RuntimeError("web3 not installed. Run: pip install web3")
    
    registry_info = REGISTRIES[chain]
    w3 = Web3(Web3.HTTPProvider(registry_info["rpc"]))
    account = Account.from_key(private_key)
    
    contract = w3.eth.contract(
        address=Web3.to_checksum_address(registry_info["registry"]),
        abi=REGISTRY_ABI
    )
    
    if dry_run:
        return {
            "status": "dry_run",
            "action": "transfer",
            "from": account.address,
            "to": new_owner,
            "agent_id": agent_id
        }
    
    nonce = w3.eth.get_transaction_count(account.address)
    
    tx = contract.functions.transferFrom(
        account.address,
        Web3.to_checksum_address(new_owner),
        agent_id
    ).build_transaction({
        "from": account.address,
        "nonce": nonce,
        "gas": 100000,
        "gasPrice": w3.eth.gas_price,
        "chainId": registry_info["chain_id"]
    })
    
    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    
    print(f"Transfer TX sent: {tx_hash.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    
    return {
        "status": "success" if receipt.status == 1 else "failed",
        "tx_hash": tx_hash.hex(),
        "new_owner": new_owner
    }


def lookup_agent(chain: str, agent_id: int) -> dict:
    """Look up agent details via wayMint API."""
    if not HAS_REQUESTS:
        raise RuntimeError("requests not installed")
    
    try:
        resp = requests.get(f"{WAYMINT_API}/api/agent/{chain}/{agent_id}", timeout=10)
        if resp.status_code == 404:
            return {"error": "Agent not found"}
        if resp.status_code >= 500:
            return {"error": f"wayMint API error: {resp.status_code}"}
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        return {"error": f"Request failed: {e}"}


def lookup_owner_agents(address: str) -> dict:
    """Look up all agents owned by an address."""
    if not HAS_REQUESTS:
        raise RuntimeError("requests not installed")
    
    resp = requests.get(f"{WAYMINT_API}/api/owner/{address}", timeout=10)
    resp.raise_for_status()
    return resp.json()


# =============================================================================
# ED25519 SELF-REGISTRATION (Celo only)
# =============================================================================

def self_register_ed25519(pubkey_hex: str, private_key_pem: str) -> dict:
    """
    Register agent using Ed25519 self-registration flow (Celo).
    Returns session info with deepLink for human to scan.
    """
    if not HAS_REQUESTS:
        raise RuntimeError("requests not installed")
    
    # Step 1: Get challenge
    resp = requests.post(
        f"{WAYMINT_API}/api/self-challenge",
        json={"pubkey": pubkey_hex},
        timeout=10
    )
    resp.raise_for_status()
    challenge_data = resp.json()
    challenge_hash = challenge_data["challengeHash"]
    
    # Step 2: Sign challenge with Ed25519 using cryptography library
    try:
        from cryptography.hazmat.primitives import serialization
        
        challenge_bytes = bytes.fromhex(challenge_hash[2:])  # Remove 0x prefix
        
        private_key = serialization.load_pem_private_key(
            private_key_pem.encode(),
            password=None
        )
        signature = private_key.sign(challenge_bytes)
        signature_hex = signature.hex()
    except ImportError:
        raise RuntimeError("cryptography library required for Ed25519 signing. Run: pip install cryptography")
    except Exception as e:
        raise RuntimeError(f"Failed to sign challenge: {e}")
    
    # Step 3: Register
    resp = requests.post(
        f"{WAYMINT_API}/api/self-register",
        json={"pubkey": pubkey_hex, "signature": signature_hex},
        timeout=10
    )
    resp.raise_for_status()
    return resp.json()


def poll_self_status(session_token: str, timeout_seconds: int = 600) -> dict:
    """Poll for self-registration completion."""
    if not HAS_REQUESTS:
        raise RuntimeError("requests not installed")
    
    start = time.time()
    while time.time() - start < timeout_seconds:
        resp = requests.get(
            f"{WAYMINT_API}/api/self-status",
            params={"token": session_token},
            timeout=10
        )
        resp.raise_for_status()
        data = resp.json()
        
        stage = data.get("stage")
        print(f"  Status: {stage}")
        
        if stage == "registered":
            return data
        elif stage == "failed":
            return {"error": "Registration failed", "details": data}
        
        time.sleep(5)
    
    return {"error": "Timeout waiting for registration"}


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="ERC-8004 Agent Identity Onboarding")
    parser.add_argument("--name", help="Agent name (required for registration)")
    parser.add_argument("--description", default="Autonomous trading agent", help="Agent description")
    parser.add_argument("--chain", choices=["base", "celo"], default="base", help="Target chain")
    parser.add_argument("--operator", help="Operator address to transfer ownership to")
    parser.add_argument("--private-key", help="Agent private key (hex). If not provided, generates new.")
    parser.add_argument("--use-openclaw-key", action="store_true", help="Use OpenClaw Ed25519 identity (Celo only)")
    parser.add_argument("--services", help="JSON array of service endpoints")
    parser.add_argument("--image", help="Agent image URL")
    parser.add_argument("--dry-run", action="store_true", help="Preview without executing")
    parser.add_argument("--lookup", type=int, help="Look up existing agent by ID")
    parser.add_argument("--lookup-owner", help="Look up all agents owned by address")
    
    args = parser.parse_args()
    
    # Lookup modes (don't require --name)
    if args.lookup:
        result = lookup_agent(args.chain, args.lookup)
        print(json.dumps(result, indent=2))
        return
    
    if args.lookup_owner:
        result = lookup_owner_agents(args.lookup_owner)
        print(json.dumps(result, indent=2))
        return
    
    # Registration requires --name
    if not args.name:
        parser.error("--name is required for registration")
    
    # Parse services
    services = None
    if args.services:
        services = json.loads(args.services)
    
    print(f"\n🤖 ERC-8004 Agent Onboarding")
    print(f"   Chain: {args.chain}")
    print(f"   Name: {args.name}")
    print(f"   Registry: {REGISTRIES[args.chain]['registry']}")
    print()
    
    # Handle Ed25519 self-registration (Celo)
    if args.use_openclaw_key:
        if args.chain != "celo":
            print("❌ Ed25519 self-registration only supported on Celo")
            sys.exit(1)
        
        keypair = load_openclaw_keypair()
        if not keypair:
            print(f"❌ OpenClaw identity not found at {OPENCLAW_IDENTITY_PATH}")
            sys.exit(1)
        
        pubkey_hex = extract_ed25519_pubkey_hex(keypair["public_key_pem"])
        print(f"📋 Using OpenClaw Ed25519 key: {pubkey_hex[:16]}...")
        
        if args.dry_run:
            print("\n[DRY RUN] Would initiate Ed25519 self-registration")
            return
        
        print("\n🔐 Initiating self-registration...")
        session = self_register_ed25519(pubkey_hex, keypair["private_key_pem"])
        
        print(f"\n📱 Human action required!")
        print(f"   Have your operator scan this link in the Self app:")
        print(f"   {session.get('deepLink') or session.get('scanUrl')}")
        print(f"\n⏳ Waiting for passport verification...")
        
        result = poll_self_status(session["sessionToken"])
        
        if "error" in result:
            print(f"❌ {result['error']}")
            sys.exit(1)
        
        print(f"\n✅ Registration complete!")
        print(f"   Agent Address: {result.get('agentAddress')}")
        print(f"   Certificate: {WAYMINT_API}/agent/celo:{result.get('agentId')}")
        return
    
    # Standard ETH keypair registration
    if args.private_key:
        private_key = args.private_key
        if not private_key.startswith("0x"):
            private_key = "0x" + private_key
        account = Account.from_key(private_key)
        print(f"📋 Using provided key: {account.address}")
    else:
        print("🔑 Generating new keypair...")
        keypair = generate_eth_keypair()
        private_key = keypair["private_key"]
        print(f"   Address: {keypair['address']}")
        print(f"   ⚠️  SAVE THIS PRIVATE KEY: {private_key}")
    
    # Build registration metadata
    print("\n📝 Building registration metadata...")
    registration = build_registration_file(
        name=args.name,
        description=args.description,
        chain=args.chain,
        services=services,
        image=args.image
    )
    
    # Pin to IPFS or use data URI
    try:
        print("📌 Pinning metadata to IPFS...")
        agent_uri = pin_metadata(
            name=args.name,
            description=args.description,
            services=services,
            image=args.image
        )
        print(f"   URI: {agent_uri}")
    except Exception as e:
        print(f"   IPFS pin failed ({e}), using data URI instead")
        agent_uri = create_data_uri(registration)
        print(f"   URI: data:application/json;base64,...")
    
    # Register on-chain
    print(f"\n⛓️  Registering on {args.chain}...")
    result = register_on_chain(
        private_key=private_key,
        chain=args.chain,
        agent_uri=agent_uri,
        dry_run=args.dry_run
    )
    
    if args.dry_run:
        print("\n[DRY RUN] Would register:")
        print(json.dumps(result, indent=2))
        return
    
    if result["status"] != "success":
        print(f"❌ Registration failed: {result}")
        sys.exit(1)
    
    print(f"\n✅ Agent registered!")
    print(f"   Agent ID: {result['agent_id']}")
    print(f"   TX: {result['tx_hash']}")
    print(f"   Certificate: {result['certificate_url']}")
    
    # Transfer ownership if operator specified
    if args.operator:
        print(f"\n🔄 Transferring ownership to {args.operator}...")
        transfer_result = transfer_ownership(
            private_key=private_key,
            chain=args.chain,
            agent_id=result["agent_id"],
            new_owner=args.operator,
            dry_run=args.dry_run
        )
        
        if transfer_result["status"] == "success":
            print(f"   ✅ Ownership transferred!")
            print(f"   TX: {transfer_result['tx_hash']}")
        else:
            print(f"   ❌ Transfer failed: {transfer_result}")
    
    # Save result
    output_file = Path(f"agent_{result['agent_id']}_{args.chain}.json")
    output_data = {
        "agent_id": result["agent_id"],
        "chain": args.chain,
        "registry": REGISTRIES[args.chain]["registry"],
        "namespace": REGISTRIES[args.chain]["namespace"],
        "owner": args.operator or result["owner"],
        "certificate_url": result["certificate_url"],
        "registration_tx": result["tx_hash"],
        "private_key": private_key if not args.operator else "[transferred]"
    }
    
    with open(output_file, "w") as f:
        json.dump(output_data, f, indent=2)
    
    print(f"\n💾 Saved to {output_file}")
    print(f"\n🎉 Done! Your agent is now on-chain.")


if __name__ == "__main__":
    main()
