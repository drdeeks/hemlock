#!/usr/bin/env python3
"""
Robust memory logging system for Hemlock agents and crews.
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
        """Log agent or crew state for crash recovery."""
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
