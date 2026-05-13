#!/usr/bin/env python3
"""
Orchestration validator for Hermes/OpenClaw framework.
Checks that orchestration components are available.
"""
import sys
import os

def test_orchestration():
    """Test that we can access orchestration components."""
    try:
        # Check for process registry
        from tools.process_registry import process_registry
        print("✓ Process registry accessible")
        
        # Check for skill manager (if exists)
        skill_manager_path = '/opt/hermes/tools/skill_manager_tool.py'
        if os.path.exists(skill_manager_path):
            print("✓ Skill manager tool found")
        else:
            print("⚠ Skill manager tool not found")
            
        # Check for MCP files
        mcp_file = '/opt/hermes/agent_brain_mcp.py'
        if os.path.exists(mcp_file):
            print("✓ MCP brain file found")
        else:
            print("⚠ MCP brain file not found")
            
        return True
    except Exception as e:
        print(f"✗ Orchestration validation failed: {e}")
        return False

if __name__ == "__main__":
    if test_orchestration():
        sys.exit(0)
    else:
        sys.exit(1)
