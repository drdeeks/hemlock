# MEMORY.md - Aton's Long-Term Memory

## Agent Identity
- **Name:** Aton 🤖
- **Role:** Creative Developer
- **Created:** 2026-03-14
- **Workspace:** `/data/agents/aton/`
- **Model:** xiaomi/mimo-v2-pro (Nous)
- **Platform:** Telegram bot, DM with Dr Deeks (ID: 6537959619)

## Dr Deeks (Primary User)
- System admin, technical, direct/no-nonsense communication style
- Values efficiency, transparency, honesty over sugarcoating
- Manages multi-agent fleet: Tom, Avery, Titan, Mort, Aton
- Timezone: UTC

## Active Projects

### Pass or Yass (Farcaster Snap)
- **URL:** https://pass-or-yass-v4.host.neynar.app
- **Type:** Tinder-style swipe app for Farcaster profiles (Pass/Yass)
- **Stack:** Hono server + Turso DB, deployed to Neynar hosting
- **Neynar API:** 265457D2-C11E-47F4-824D-8E4B29F5C1A9
- **Project ID:** b198ac59-e4f8-41d1-a9d3-55a218a4e7d7
- **Deploy API key:** 98d46c2c-42c2-4521-8d6d-b6f34c895533
- **Features:**
  - 3 swipes/user/day, midnight UTC reset
  - Profile qualification: 6mo+ age, Neynar ≥0.420, follower ratio, 10+ posts (3+ original), <20 deleted casts
  - Excludes friends (immediate connections) to prevent manipulation
  - Gate screen: ambiguous Pass?/Yass buttons classify initial personality
  - Background analysis for social scoring (not yet implemented)
- **Source:** `projects/pass-or-yass/`
- **Status:** Deployed, functional on Neynar free tier (user/bulk only)

### Base Builder Code
- Code: `bc_26ulyc23`
- Owner: `0x12F1B38DC35AA65B50E5849d02559078953aE24b`
- Hardwired + enforced

## Environment
- Docker container (nikolaik/python-nodejs:python3.11-nodejs20)
- HERMES_HOME=/data/agents/aton
- ~ resolves to /root — always use $HERMES_HOME or relative paths
- Never write to /tmp (lost on restart)
- Never chmod 700 (caused catastrophic past data loss — use 755/644 only)
- Skills at skills/ relative to workspace

## Key Lessons
- /tmp files get wiped on container restart — always write to workspace paths
- chmod 700 locks user out of their own files — NEVER use it
- Neynar free tier only supports user/bulk endpoint — no trending/feed/casts
- Session logs contain recovery data for lost projects
