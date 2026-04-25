---
name: agentmail-signup
description: "Use AgentMail to programmatically create accounts on third-party services. Handles inbox creation, signup forms, email verification via AgentMail API, and credential extraction. Use when signing up for any service that requires email verification (Pinata, GitHub, cloud providers, etc.)."
version: 1.0.0
metadata:
  hermes:
    tags: [email, automation, signup, agentmail]
    related_skills: [registering-agent-base-dev, pinata-erc-8004]
---

# AgentMail Service Signup

Programmatically sign up for third-party services using AgentMail as the email provider. This avoids needing a human email for agent infrastructure.

## When to Use

✅ **USE this skill when:**
- Signing up for a new service on behalf of an agent
- Service requires email verification (OTP or link)
- You need a throwaway/agent email without involving a human

❌ **DON'T use this skill when:**
- Service supports OAuth/API-only signup (GitHub, Google)
- You already have credentials stored in `.secrets/`
- The service has an agent-specific signup API

## Prerequisites

- AgentMail API key (stored in `.secrets/.agentmail-[agent-name]`)
- `agentmail` Python package installed
- Browser tool available (for web form filling)

## Python Environment Note

**Critical:** The `agentmail` package may install to a different Python than the project venv. Always use `python3.12` explicitly:

```bash
# Install (system Python 3.12)
pip install --break-system-packages agentmail

# Use it (NOT python3, which may point to venv's 3.11)
python3.12 -c "from agentmail import AgentMail; ..."
```

If you get `ModuleNotFoundError` after installing, check which Python got the package:
```bash
pip show agentmail  # check location
python3.12 -c "import agentmail"  # try 3.12
```

## Workflow

### Step 1: Create or get an inbox

```python
from agentmail import AgentMail

client = AgentMail(api_key="am_...")

# Create a new inbox for this signup
inbox = client.inboxes.create(client_id="service-name-signup")
# inbox.inbox_id -> "my-agent@agentmail.to"
```

Or list existing inboxes:
```python
inboxes = client.inboxes.list()
for i in inboxes.inboxes:
    print(i.inbox_id)  # e.g., "agent-allman@agentmail.to"
```

### Step 2: Sign up on the service

Use browser tools to fill the signup form:
- Navigate to the service's signup page
- Fill in name, email (use the AgentMail inbox address), password
- Generate a strong password: `python3.12 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits+'!@#$%^&') for _ in range(20)))"`
- Submit the form
- Save the password in `.secrets/` for later login

### Step 3: Fetch verification email

The service will send a verification email or OTP. Poll the inbox:

```python
import time
from agentmail import AgentMail

client = AgentMail(api_key="am_...")

# Wait for the email (poll up to 60s)
for attempt in range(12):
    msgs = client.inboxes.messages.list("agent-allman@agentmail.to", limit=5)
    for m in msgs.messages:
        # Filter by sender or subject
        if "pinata" in (m.from_ or "").lower() or "verify" in (m.subject or "").lower():
            # Get full message content
            full = client.inboxes.messages.get("agent-allman@agentmail.to", m.message_id)
            print(f"From: {full.from_}")
            print(f"Subject: {full.subject}")
            print(f"Text: {(full.text or '')[:500]}")
            # Extract verification link from text or html
    time.sleep(5)
    print(f"Attempt {attempt+1}: waiting for email...")
```

### Step 4: Complete verification

- If it's a **link**: Navigate to it in the browser
- If it's an **OTP code**: Fill it in the verification form
- Note: Verification links expire (usually 10 min) — act quickly

### Step 5: Store credentials

Save credentials in the agent's `.secrets/` directory:

```
.secrets/.service-name-access
```

Format:
```
SERVICE_API_KEY=xxx
SERVICE_API_SECRET=xxx
SERVICE_JWT=xxx
```

Set permissions:
```bash
chmod 600 .secrets/.service-name-access
```

## Browser Rate Limits

Pinata (and likely other Clerk-based auth) will rate-limit sign-in attempts. If you see "Too many requests":
- Wait 60-120 seconds before retrying
- Don't retry immediately — it resets the cooldown
- If persistent, the user can manually sign in and provide credentials

## Common Issues

### "Too many requests"
Rate limited by the service's auth provider (often Clerk). Wait 2+ minutes between attempts.

### Verification link opens to login page
The account was likely verified successfully — the redirect to login is normal. Try signing in with the credentials.

### Empty browser page after clicking verification link
The link may be a JS redirect. Wait 3 seconds then navigate to the service dashboard directly.

### `ModuleNotFoundError: agentmail`
Wrong Python version. Use `python3.12` explicitly, not `python3` (which may be venv's 3.11).

## Example: Full Pinata Signup

```bash
# 1. Install
pip install --break-system-packages agentmail

# 2. Create inbox + sign up + verify + get API key
python3.12 << 'EOF'
from agentmail import AgentMail
client = AgentMail(api_key="am_...")
inbox = client.inboxes.create(client_id="pinata-signup")
print(f"Use this email: {inbox.inbox_id}")
EOF

# 3. Use browser to fill signup form at app.pinata.cloud/auth/signup
# 4. Poll for verification email, click link
# 5. After onboarding, go to Developers > API Keys
# 6. Save JWT to .secrets/.pinata-access
```
