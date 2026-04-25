# Session Notes — Roast or Toast Snap

## Status: MID-BUILD (context reset)

**User wants a SNAP, NOT a Mini App.** They explicitly corrected this. Do NOT suggest Mini Apps.

**Project: "Roast or Toast"**
- AI-generated ruthless roasts based on real Farcaster data (profile, casts, bio, followers) via Neynar API
- Toast = over-embellished sarcastic "good for you" backhanded compliment
- Either way user gets roasted — that's the joke
- Social/viral: people share screenshots of roasts

**Build state:** Had package.json, tsconfig, wrangler.toml. Was about to integrate Neynar API fetch + AI roast generation.

**Credentials:**
- NEYNAR_API_KEY — stored in .secrets/
- NEYNAR_APP_UUID — from .secrets/credentials.json
- Deploy API key — from earlier Neynar setup

**User's vibe:** Creative, impatient, wants things that "turn heads." Doesn't want boring. Wants to iterate fast. Frustrated by over-explanation and circular progress.
