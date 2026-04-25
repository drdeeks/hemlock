---
name: debug-tracer
description: Systematic upstream/downstream issue tracing for any failure — HTTP errors, load failures, CORS, network, auth, signing, UI state, backend validation. Use when debugging any "load failed", silent error, unexpected response, broken flow, or integration issue. Forces full-path diagnosis before attempting any fix. Prevents blind patching.
---

# Debug Tracer

**One rule: trace before you fix. Never patch without confirmed root cause.**

---

## The Protocol

### Step 1 — Capture the exact failure

Before touching any code, get the exact error:
- HTTP status code (200/400/401/403/404/422/500/502/CORS)
- Browser console output (network tab + console errors)
- Backend logs if accessible
- Exact request payload that triggered it

If you don't have the exact error, **get it first**. Ask the user, check logs, run a curl.

### Step 2 — Identify the failure layer

Map the request path end-to-end:

```
User action
  → Browser/UI state (React/JS)
    → Fetch/XHR call
      → CORS preflight (OPTIONS)
        → Backend receipt
          → Middleware (auth, validation)
            → Business logic
              → External service (DB, blockchain, email)
                → Response
                  → UI rendering
```

Identify **which layer** the failure occurs at. One of:

| Layer | Signals |
|-------|---------|
| UI state | Wrong value passed, stale ref, React state timing |
| Network | `fetch failed`, `ERR_NETWORK`, timeout |
| CORS | Missing `access-control-allow-origin` on OPTIONS response |
| Auth | 401, 403, invalid token/signature |
| Validation | 400, 422, schema mismatch |
| Backend logic | 500, wrong business rule |
| External service | Blockchain revert, email bounce, 3rd party 4xx/5xx |

### Step 3 — Reproduce the exact failure with a minimal test

Test **that single layer** in isolation:

```bash
# Test CORS preflight
curl -sI -X OPTIONS <url> \
  -H "Origin: <frontend-origin>" \
  -H "Access-Control-Request-Method: POST" \
  | grep -i "access-control"

# Test backend directly (bypass browser/CORS)
curl -s -X POST <url> \
  -H "Content-Type: application/json" \
  -d '<exact-payload>' | jq .

# Test signature verification
node -e "const {ethers}=require('ethers'); console.log(ethers.verifyMessage('<msg>','<sig>'))"
```

If the isolated test **passes**, the problem is upstream (browser/CORS/network).
If it **fails**, the problem is in that layer or downstream.

### Step 4 — Binary search the path

Split the path in half. Test the midpoint. Narrow from there. Never assume.

```
Failure at UI → check state values before fetch
Failure at network → check CORS preflight response headers
Failure at backend receipt → check what payload arrived (add logging)
Failure at validation → check exact field names and types
Failure at external → check service-specific error codes
```

### Step 5 — Fix the confirmed root cause once

Only after Step 3/4 confirms the exact failure layer:
- Make the minimal change that fixes that specific layer
- Do not make additional "defensive" changes to unrelated layers
- Test again with the same isolated test from Step 3

### Step 6 — Verify end-to-end

Run the full flow once after the fix to confirm the patch resolved the root cause and didn't break anything else.

---

## Common Failure Patterns

### "Load failed" / fetch error in browser
**Always check CORS first.** Run:
```bash
curl -sI -X OPTIONS <backend-url>/<endpoint> \
  -H "Origin: <frontend-url>" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type" \
  | grep -i "access-control-allow-origin"
```
If empty → CORS is the problem. Fix: add `ALLOWED_ORIGINS` env var on backend.

### "Invalid signature" / wallet verification failure
Test the exact message + signature before touching UI code:
```bash
node -e "const {ethers}=require('ethers'); console.log(ethers.verifyMessage('<message>','<signature>').toLowerCase() === '<address>'.toLowerCase())"
```

### Stale state / wrong value sent
Add a `console.log(payload)` before the fetch. Confirm the value being sent is what you expect. Don't guess — log it.

### "Works on desktop, fails on mobile"
- Check CORS preflight (mobile browsers always send it, desktop sometimes caches it)
- Check wallet provider differences (injected vs WalletConnect)
- Check network timing (mobile is slower, promises may resolve differently)

---

## What NOT to Do

- Do not change unrelated code while fixing a confirmed issue
- Do not add "defensive" changes without evidence they're needed
- Do not make the same fix in multiple places without understanding why
- Do not guess at root causes — verify them
- Do not move to the next layer without eliminating the current one
