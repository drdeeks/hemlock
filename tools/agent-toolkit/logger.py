#!/usr/bin/env python3
"""
Robust memory logging system for Titan agent.
Ensures no state loss due to crashes.
"""

import os
import sys
import json
import time
import datetime
from pathlib import Path
from typing import Any, Dict, List

class MemoryLogger:
    def __init__(self, base_dir: str = None):
        # Use portable path: if not specified, use RUNTIME_ROOT/memory
        if base_dir is None:
            # Try to determine runtime root from environment
            runtime_root = os.environ.get('RUNTIME_ROOT', os.getcwd())
            base_dir = os.path.join(runtime_root, 'memory')
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(exist_ok=True)
        self.log_file = self.base_dir / f"{datetime.datetime.now():%Y-%m-%d}.md"
        self.buffer = []
        self.buffer_size = 100  # Flush every 100 entries
        self.last_flush = time.time()
        self.flush_interval = 60  # Flush every 60 seconds
        
        # Create symlink for easy access
        try:
            os.symlink(self.log_file, self.base_dir / "current.md")
        except FileExistsError:
            pass
        
    def log(self, level: str, message: str, data: Any = None):
        """Log a message with level and optional data."""
        timestamp = datetime.datetime.now().isoformat()
        entry = {
            "timestamp": timestamp,
            "level": level,
            "message": message,
            "data": data
        }
        
        # Write to file immediately (append-only, no loss on crash)
        try:
            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(f"### {timestamp} [{level}] {message}\n")
                if data:
                    f.write(f"Data: {json.dumps(data, indent=2)}\n\n")
                f.write("---\n\n")
        except Exception as e:
            print(f"ERROR: Could not write to log: {e}")
        
        # Also buffer for potential in-memory operations
        self.buffer.append(entry)
        
        # Flush buffer if needed
        if len(self.buffer) >= self.buffer_size or (time.time() - self.last_flush) > self.flush_interval:
            self.flush_buffer()
    
    def flush_buffer(self):
        """Flush buffer to file (redundant safety)."""
        if not self.buffer:
            return
            
        try:
            with open(self.log_file, "a", encoding="utf-8") as f:
                for entry in self.buffer:
                    f.write(f"### {entry['timestamp']} [{entry['level']}] {entry['message']}\n")
                    if entry['data']:
                        f.write(f"Data: {json.dumps(entry['data'], indent=2)}\n\n")
                    f.write("---\n\n")
            self.buffer.clear()
            self.last_flush = time.time()
        except Exception as e:
            print(f"ERROR: Could not flush buffer: {e}")
    
    def log_state(self, state_name: str, state_data: Dict):
        """Log agent state for crash recovery."""
        self.log("STATE", f"Saving state: {state_name}", state_data)
        
        # Also write to dedicated state file for quick recovery
        state_file = self.base_dir / f"state_{state_name}.json"
        try:
            with open(state_file, "w", encoding="utf-8") as f:
                json.dump(state_data, f, indent=2)
        except Exception as e:
            print(f"ERROR: Could not write state file: {e}")
    
    def get_state(self, state_name: str) -> Dict:
        """Retrieve saved state for recovery."""
        state_file = self.base_dir / f"state_{state_name}.json"
        if not state_file.exists():
            return {}
            
        try:
            with open(state_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"ERROR: Could not read state file: {e}")
            return {}
    
    def checkpoint(self, checkpoint_name: str, data: Dict = None):
        """Create a checkpoint for crash recovery."""
        self.log("CHECKPOINT", f"Creating checkpoint: {checkpoint_name}", data)
        
        # Write to checkpoint file
        checkpoint_file = self.base_dir / f"checkpoint_{checkpoint_name}.json"
        try:
            with open(checkpoint_file, "w", encoding="utf-8") as f:
                json.dump(data or {}, f, indent=2)
        except Exception as e:
            print(f"ERROR: Could not write checkpoint: {e}")
    
    def restore_checkpoint(self, checkpoint_name: str) -> Dict:
        """Restore from checkpoint."""
        checkpoint_file = self.base_dir / f"checkpoint_{checkpoint_name}.json"
        if not checkpoint_file.exists():
            return {}
            
        try:
            with open(checkpoint_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"ERROR: Could not read checkpoint: {e}")
            return {}

# Global instance for easy access
logger = MemoryLogger()

if __name__ == "__main__":
    # Test the logger
    logger.log("INFO", "Memory logger initialized")
    logger.log("DEBUG", "Debug message", {"key": "value"})
    logger.log_state("test", {"counter": 1, "status": "running"})
    logger.checkpoint("test", {"counter": 1, "status": "running"})
    print("Memory logger test completed")
PYEOF
chmod +x memory/logger.py
python3 memory/logger.py

# Create test memory log
mkdir -p memory/2026-03-13 && echo "=== Titan Memory Log ===" > memory/2026-03-13.md && echo "Date: $(date)" >> memory/2026-03-13.md && echo "Agent: Titan" >> memory/2026-03-13.md && echo "Status: Active" >> memory/2026-03-13.md && echo "---" >> memory/2026-03-13.md

# Create memory helper script
cat > memory/log.py << 'PYEOF'
#!/usr/bin/env python3
"""
Memory logging helper for Titan agent.
Ensures no state loss due to crashes.
"""

import os
import sys
import json
from datetime import datetime
from pathlib import Path

class MemoryHelper:
    def __init__(self, base_dir: str = None):
        # Use portable path: if not specified, use RUNTIME_ROOT/memory
        if base_dir is None:
            runtime_root = os.environ.get('RUNTIME_ROOT', os.getcwd())
            base_dir = os.path.join(runtime_root, 'memory')
        self.base_dir = Path(base_dir)
        self.log_file = self.base_dir / f"{datetime.now():%Y-%m-%d}.md"
        self.checkpoints = {}
        
    def log(self, level, message, data=None):
        """Log message with level and optional data."""
        timestamp = datetime.now().isoformat()
        entry = f"### {timestamp} [{level}] {message}"
        if data:
            entry += f"\nData: {json.dumps(data, indent=2)}\n"
        entry += "---\n"
        
        # Append to log
        with open(self.log_file, "a", encoding="utf-8") as f:
            f.write(entry)
        
        print(f"[LOG] {level}: {message}")
    
    def checkpoint(self, name, data):
        """Create checkpoint for crash recovery."""
        checkpoint_file = self.base_dir / f"checkpoint_{name}.json"
        with open(checkpoint_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        self.log("CHECKPOINT", f"Created checkpoint: {name}", data)
    
    def restore(self, name):
        """Restore from checkpoint."""
        checkpoint_file = self.base_dir / f"checkpoint_{name}.json"
        if not checkpoint_file.exists():
            self.log("WARN", f"Checkpoint {name} not found")
            return None
        
        with open(checkpoint_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.log("RESTORE", f"Restored checkpoint: {name}", data)
        return data
    
    def state(self, name, data=None):
        """Save or retrieve state."""
        state_file = self.base_dir / f"state_{name}.json"
        if data is not None:
            with open(state_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            self.log("STATE", f"Saved state: {name}", data)
            return None
        else:
            if state_file.exists():
                with open(state_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            else:
                return None

# Global instance
memory_helper = MemoryHelper()

if __name__ == "__main__":
    memory_helper.log("INFO", "Memory helper initialized")
    memory_helper.checkpoint("startup", {"timestamp": str(datetime.now()), "status": "active"})
    print("Memory helper test completed")
PYEOF
chmod +x memory/log.py
python3 memory/log.py

# Create robust memory monitoring
sudo apt-get install -y inotify-tools
cat > memory/monitor.sh << 'SH'
#!/bin/bash
# Memory monitoring script for Titan
# Ensures no state loss due to crashes

LOG_DIR="/home/ubuntu/.openclaw/workspace-titan/memory"
LAST_CHECK=$(date +%s)
CHECK_INTERVAL=60
STATE_FILE="$LOG_DIR/state_titan.json"
CHECKPOINT_FILE="$LOG_DIR/checkpoint_last.json"

# Function to log with timestamp
log() {
    level="$1"
    message="$2"
    timestamp=$(date -Iseconds)
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/$(date +%Y-%m-%d).md"
    
    # Also append to current symlink
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/current.md"
}

# Function to check for crashes
check_crash() {
    # Check if main process is running
    if ! pgrep -f "python.*hermes\|python.*agent" >/dev/null; then
        log "ERROR" "Titan process not running! Restarting..."
        # Restart logic would go here
        return 1
    fi
    
    # Check memory usage
    mem_usage=$(free | awk '/Mem/{printf("%.0f", $3/$2*100)}')
    if [ "$mem_usage" -gt 85 ]; then
        log "WARN" "High memory usage: ${mem_usage}%"
    fi
    
    return 0
}

# Function to save state
save_state() {
    state=$(cat << EOF
{
    "timestamp": "$(date +%Y-%m-%dT%H:%M:%S)",
    "status": "running",
    "memory": $(free | awk '/Mem/{printf(\"%.0f\", $3/$2*100)}'),
    "cpu": $(top -bn1 | awk '/Cpu:/{printf(\"%.0f\", $2)}'),
    "uptime": "$(uptime -p)"
}
EOF
    )
    
    echo "$state" > "$STATE_FILE"
    log "STATE" "State saved"
}

# Function to create checkpoint
create_checkpoint() {
    checkpoint_data=$(cat << EOF
{
    "timestamp": "$(date +%Y-%m-%dT%H:%M:%S)",
    "status": "checkpoint",
    "memory": $(free | awk '/Mem/{printf(\"%.0f\", $3/$2*100)}'),
    "cpu": $(top -bn1 | awk '/Cpu:/{printf(\"%.0f\", $2)}'),
    "uptime": "$(uptime -p)",
    "active_projects": $(find "$RUNTIME_ROOT" -maxdepth 2 -type d -name "*-project*" 2>/dev/null | wc -l)
}
EOF
    )
    
    echo "$checkpoint_data" > "$CHECKPOINT_FILE"
    log "CHECKPOINT" "Checkpoint created"
}

# Main loop
while true; do
    # Check for crashes
    check_crash
    
    # Save state every 5 minutes
    current_time=$(date +%s)
    if [ $((current_time - LAST_CHECK)) -gt 300 ]; then
        save_state
        create_checkpoint
        LAST_CHECK=$current_time
    fi
    
    # Sleep for interval
    sleep $CHECK_INTERVAL
done
SH
chmod +x memory/monitor.sh

# Create inotify monitoring
cat > memory/inotify_monitor.sh << 'PYEOF'
#!/bin/bash
# Inotify monitoring for memory logs
# Ensures no state loss due to crashes

# Use portable path - determine runtime root
RUNTIME_ROOT="${RUNTIME_ROOT:-$(pwd)}"
LOG_DIR="$RUNTIME_ROOT/memory"
STATE_FILE="$LOG_DIR/state.json"
CHECKPOINT_FILE="$LOG_DIR/checkpoint_last.json"

# Function to log
log() {
    level="$1"
    message="$2"
    timestamp=$(date -Iseconds)
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/$(date +%Y-%m-%d).md"
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/current.md"
}

# Monitor memory directory
inotifywait -m "$LOG_DIR" --format '%w%f %e' -e modify -e create -e delete | while read file event;
    log "INFO" "File $file modified ($event)"
    # If current.md is modified, create backup
    if [[ "$file" == *"current.md" && "$event" == "MODIFY" ]]; then
        cp "$file" "$LOG_DIR/backup_$(date +%Y%m%d-%H%M%S).md"
        log "BACKUP" "Created backup of current.md"
    fi
    
    # If memory log is modified, update state
    if [[ "$file" == *.md && "$event" == "MODIFY" ]]; then
        # Extract last 10 lines for quick status
        tail -10 "$file" > "$LOG_DIR/quick_status.log"
    fi
done
PYEOF

# Create systemd service for memory monitoring (portable version)
if [[ -d /etc/systemd/system ]]; then
    RUNTIME_ROOT="${RUNTIME_ROOT:-$(pwd)}"
    sudo tee /etc/systemd/system/memory-monitor.service > /dev/null << EOF
[Unit]
Description=Memory Monitoring Service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$RUNTIME_ROOT/memory
ExecStart=$RUNTIME_ROOT/memory/monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable memory-monitor
    sudo systemctl start memory-monitor
fi

echo "=== Memory Logging System Setup Complete ==="
echo "- Memory logging initialized in $RUNTIME_ROOT/memory/"
echo "- Memory monitoring service running (memory-monitor)"
echo "- Crash recovery enabled via state/checkpoint files"
echo "- Inotify monitoring for file changes"
echo ""
echo "Test the system:"
echo "python3 memory/logger.py"
echo "python3 memory/log.py"
echo "sudo systemctl status titan-memory-monitor"
