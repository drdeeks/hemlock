---
name: neynar-deploy
description: Deploy static sites, Vite apps, and Next.js apps to a live URL with a
  single API call. Built-in versioning with instant rollback -- no git required. Use
  when you need to deploy, host, or update a website on host.neynar.app.
license: MIT
compatibility: Requires network access to https://api.host.neynar.app
metadata:
  author: neynar
  version: '1.1'
  last_updated: '2026-03-05'
  update_url: https://raw.githubusercontent.com/neynarxyz/neynar-deploy/main/SKILL.md
version: 1.0.0
author: openclaw
---
## Keeping this skill up to date

This skill was last updated on **2026-03-05**. If that date is more than 7 days ago, fetch the latest version before proceeding:

```bash
curl -s https://raw.githubusercontent.com/neynarxyz/neynar-deploy/main/SKILL.md
```

# Agent Deploy

Deploy web projects to `https://{project-name}.host.neynar.app` with a single HTTP call.

## Quick deploy flow

1. Create a `.tar.gz` archive of the project directory
2. POST it to `https://api.host.neynar.app/v1/deploy`
3. On first deploy, an API key is returned — save it to `.agentdeploy` or credentials
4. Response includes the live URL

## How to deploy

### Step 1: Archive
```bash
tar czf /tmp/site.tar.gz -C /path/to/project .
```

### Step 2: Deploy (first time — no auth needed)
```bash
curl -X POST https://api.host.neynar.app/v1/deploy \
  -F "files=@/tmp/site.tar.gz" \
  -F "projectName=my-site" \
  -F "framework=static"
```

`framework` options: `nextjs`, `vite`, `static`, `auto` (default)

### Step 3: Save API key
First deploy response includes `apiKey` — returned exactly once. Save immediately.

```json
{
  "success": true,
  "projectId": "uuid",
  "apiKey": "uuid",
  "deploymentId": "uuid",
  "url": "https://my-site.host.neynar.app"
}
```

### Step 4: Subsequent deploys
```bash
curl -X POST https://api.host.neynar.app/v1/deploy \
  -F "files=@/tmp/site.tar.gz" \
  -F "projectName=my-site" \
  -H "Authorization: Bearer <api-key>"
```

## API Reference

Base URL: `https://api.host.neynar.app`
Auth: `Authorization: Bearer <api-key>`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/deploy` | POST | Deploy files (creates project + key if no auth) |
| `/v1/projects` | GET | List all projects |
| `/v1/projects/:id` | GET | Project details + deploy history + 7d analytics |
| `/v1/projects/:id` | DELETE | Delete project |
| `/v1/projects/:id/deploy` | POST | Deploy new version to existing project |
| `/v1/projects/:id/deploy/:deploymentId` | GET | Check deploy status |
| `/v1/projects/:id/rollback` | POST | Roll back: `{ "version": <number> }` |
| `/v1/projects/:id/analytics?period=7d` | GET | Analytics (1d/7d/30d) |
| `/v1/projects/:id/files` | GET | Download URL for latest source |
| `/v1/billing/tier` | GET | Current tier and limits |

## Deploy status values
`pending` → `building` → `ready` / `error`

## Limits (free tier)
- 3 active projects
- 10 deploys/hour
- 50MB max upload

## Error format
```json
{ "success": false, "error": "Human-readable message" }
```
Status codes: `400` bad input, `401` invalid key, `402` project limit, `404` not found, `413` too large, `429` rate limited

