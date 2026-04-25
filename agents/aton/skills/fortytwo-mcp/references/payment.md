# x402 Payment — EIP-712 ReceiveWithAuthorization

## Canonical helper

Use this as the source-of-truth implementation for building `payment-signature`.

Before signing, query the token contract on the selected network and use its actual:

- `name()`
- `version()`
- `decimals()`

Do not hardcode `"USD Coin"` or other mainnet assumptions. Some testnet USDC deployments return
`name() = "USDC"`, and using the wrong EIP-712 domain values will produce an invalid signature.

## Resolve token metadata on-chain

```python
from web3 import Web3

ERC20_META_ABI = [
    {"name": "name", "outputs": [{"type": "string"}], "inputs": [], "stateMutability": "view", "type": "function"},
    {"name": "version", "outputs": [{"type": "string"}], "inputs": [], "stateMutability": "view", "type": "function"},
    {"name": "decimals", "outputs": [{"type": "uint8"}], "inputs": [], "stateMutability": "view", "type": "function"},
]


def load_token_metadata(rpc_url: str, usdc_address: str) -> tuple[str, str, int]:
    w3 = Web3(Web3.HTTPProvider(rpc_url))
    token = w3.eth.contract(
        address=Web3.to_checksum_address(usdc_address),
        abi=ERC20_META_ABI,
    )
    return (
        token.functions.name().call(),
        token.functions.version().call(),
        token.functions.decimals().call(),
    )
```

For the current Fortytwo USDC flow, `decimals` is expected to be `6`, so `1000000 = 1.0 USDC`.

```python
import base64
import json
import secrets
import time
from eth_account import Account


def build_payment_signature(
    private_key: str,
    chain_id: int,
    usdc_name: str,
    usdc_version: str,
    usdc_address: str,
    accept: dict,  # one item from payment-required.accepts
) -> str:
    account = Account.from_key(private_key)

    nonce = "0x" + secrets.token_hex(32)
    valid_after = 0
    valid_before = int(time.time()) + int(accept["maxTimeoutSeconds"])

    typed_data = {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "ReceiveWithAuthorization": [
                {"name": "from", "type": "address"},
                {"name": "to", "type": "address"},
                {"name": "value", "type": "uint256"},
                {"name": "validAfter", "type": "uint256"},
                {"name": "validBefore", "type": "uint256"},
                {"name": "nonce", "type": "bytes32"},
            ],
        },
        "primaryType": "ReceiveWithAuthorization",
        "domain": {
            "name": usdc_name,
            "version": usdc_version,
            "chainId": chain_id,
            "verifyingContract": usdc_address,
        },
        "message": {
            "from": account.address,
            "to": accept["payTo"],
            "value": int(accept["amount"]),
            "validAfter": valid_after,
            "validBefore": valid_before,
            "nonce": nonce,
        },
    }

    signed = account.sign_typed_data(full_message=typed_data)
    r_hex = "0x" + signed.r.to_bytes(32, "big").hex()
    s_hex = "0x" + signed.s.to_bytes(32, "big").hex()

    payment_sig = {
        "x402Version": 2,
        "scheme": "exact",
        "network": accept["network"],  # e.g. "eip155:8453" (Base) or "eip155:143" (Monad)
        "payload": {
            "client": account.address,
            "maxAmount": str(int(accept["amount"])),
            "validAfter": str(valid_after),
            "validBefore": str(valid_before),
            "nonce": nonce,
            "v": int(signed.v),
            "r": r_hex,
            "s": s_hex,
        },
    }

    return base64.b64encode(
        json.dumps(payment_sig, separators=(",", ":")).encode()
    ).decode()
```

## Key Rules

- `nonce` — single-use `bytes32`, generate a fresh value for each payment
- `validBefore` — must be in the future at settle time (typically `now + 300`)
- `amount` is passed as a string in `maxAmount`, parsed as int
- `amount` / `maxAmount` are in the token's smallest unit; for USDC, `1000000 = 1.0 USDC`
- `network` in `payment_sig` must match `accepts[n].network`
- `domain.name` and `domain.version` must come from the token contract on the chosen chain
