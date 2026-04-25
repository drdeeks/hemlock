---
name: fix-systemd-workingdirectory
description: Fix systemd service WorkingDirectory issues when services fail to start due to path problems
category: system administration
---

# Fix Systemd Service WorkingDirectory Issues

## When to Use This Skill
When a systemd service fails with errors like:
- "Changing to the requested working directory failed: No such file or directory"
- "Failed to change to working directory"
- Service fails to start due to path issues

## Steps to Fix

### 1. Check Service Status and Logs
```bash
systemctl status <service-name>
journalctl -u <service-name> -n 20
```

Look for errors indicating working directory problems.

### 2. Examine the Service File
```bash
cat /etc/systemd/system/<service-name>.service
```

Check the `WorkingDirectory` directive in the `[Service]` section.

### 3. Verify Actual Directory Exists
```bash
ls -la /path/from/WorkingDirectory
```

If the directory doesn't exist, you have two options:
- Create the missing directory
- Update WorkingDirectory to point to an existing directory

### 4. Find Correct Directory Location
Search for the service's actual files:
```bash
find /home -type d -name "*<service-name>*" 2>/dev/null | head -10
ls -la /home/ubuntu/ | grep -E "\\.(gateway|hermes)"
```

### 5. Update the Service File
```bash
sudo sed -i 's|OldWorkingDirectory|NewWorkingDirectory|' /etc/systemd/system/<service-name>.service
```

Example:
```bash
sudo sed -i 's|WorkingDirectory=/home/ubuntu/hermes-agent/workspaces/agent-allman|WorkingDirectory=/home/ubuntu/.agent-allman.gateway|' /etc/systemd/system/agent-allman-gateway.service
```

### 6. Reload Systemd and Restart Service
```bash
sudo systemctl daemon-reload
sudo systemctl start <service-name>
```

### 7. Verify Service is Running
```bash
systemctl status <service-name>
```

## Verification
- Service should show "Active: active (running)"
- No more working directory errors in logs
- Service maintains active state over time

## Common Causes
- Service configuration references old directory structure
- Directory was moved or renamed after service creation
- Template services deployed to incorrect paths
- Gateway or agent directory restructuring

## Prevention
- When deploying services, verify WorkingDirectory points to existing path
- Use environment variables or dynamic paths when possible
- Document directory structure assumptions in service descriptions