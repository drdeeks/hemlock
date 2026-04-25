# Hackathon Manager

> Manages hackathon participation, project organization, and submission workflows.

## Overview

This skill helps manage hackathon participation including project organization, submission workflows, and tracking multiple project ideas across different tracks.

## Core Functions

### Project Organization
- Create project directories for hackathon ideas
- Track project status and progress
- Manage multiple project concepts
- Link projects to specific bounties/tracks

### Submission Management
- Prepare submission metadata
- Track submission deadlines
- Manage team coordination
- Handle on-chain identity integration

### Resource Management
- Track bounties and prize pools
- Map projects to relevant tracks
- Monitor competition landscape
- Manage credentials and API keys

## Key Commands

```bash
# Create project directory
mkdir -p "/home/ubuntu/.openclaw/workspace-titan/hackathon/[project-name]"

# Track project status
# (managed through memory files and project directories)

# Prepare submission
# (handled through submission workflows)
```

## Data Structure

```
hackathon/
├── [project-name]/
│   ├── README.md
│   ├── submission.md
│   ├── credentials.json
│   └── progress.md
├── bounties.json
└── projects.json
```

## Integration

- Uses OpenClaw workspace for file operations
- Integrates with hackathon APIs (Devfolio, etc.)
- Manages ERC-8004 identity through stored credentials
- Tracks multiple bounties and prize pools

## Security

- Credentials stored in `.synth-creds.json` with restricted permissions
- API keys never shared publicly
- Submission data managed through secure workflows
- On-chain identity handled through ERC-8004

## Usage

1. Install skill: `openclaw skill add /path/to/skill`
2. Create project directories: `mkdir -p hackathon/[project-name]`
3. Track progress through memory files
4. Prepare submissions using stored credentials
5. Monitor bounties and prize pools

## Best Practices

- Keep credentials secure and permissions restricted
- Track project progress systematically
- Map projects to relevant bounties early
- Prepare submissions well before deadlines
- Use on-chain identity for verification