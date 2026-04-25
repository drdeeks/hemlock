# Pass or Yass — Farcaster Snap

## Architecture
- **Hub API** (snapchain-api.neynar.com) — FREE — for discovering active users via casts
- **REST API** (api.neynar.com/v2) — /user/bulk only (free tier) — for hydrating user profiles
- **Hono server** on Neynar hosting, in-memory data store

## Discovery Flow
1. Start with seed FIDs (80 well-known accounts)
2. **Hub API**: `castsByFid` on seed users → extract mentions + reply targets
3. Merge discovered FIDs with seeds, shuffle, deduplicate
4. **REST API**: `user/bulk` to hydrate (username, pfp, bio, follower count, score)
5. Qualify: 6mo+ age, score ≥0.42, ratio ≥0.15, 10+ followers
6. Store qualified pool, serve one at a time

## API Endpoints Used (all free)
- `GET snapchain-api.neynar.com/v1/castsByFid?fid=X` — Hub: raw casts
- `GET snapchain-api.neynar.com/v1/castsByParent?fid=X&hash=Y` — Hub: replies
- `GET snapchain-api.neynar.com/v1/userDataByFid?fid=X` — Hub: profile data
- `GET api.neynar.com/v2/farcaster/user/bulk?fids=X,Y` — REST: hydrated users

## UI Theme
- `theme.accent: "purple"` — dark mystical feel
- Blues, purples, pinks throughout

## Env Required
- `NEYNAR_API_KEY` — set in Neynar hosting dashboard
- `SNAP_PUBLIC_BASE_URL` — set to live URL

## Files
- `src/index.ts` — Main snap logic
- `package.json` — Dependencies
- `tsconfig.json` — TypeScript config
