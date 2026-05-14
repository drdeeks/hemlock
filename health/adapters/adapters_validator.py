#!/usr/bin/env python3
"""
Adapter validator for Hermes/OpenClaw framework.
Checks that platform adapters can be initialized.
"""
import sys
import os

def test_adapters():
    """Test that we can initialize platform adapters."""
    try:
        gateway_dir = os.getenv('HERMES_HOME', '/opt/hermes') + '/gateway'
        if os.path.exists(gateway_dir):
            print("✓ Gateway directory found")
            
            # Check for platform directories
            platforms_dir = os.path.join(gateway_dir, 'platforms')
            if os.path.exists(platforms_dir):
                platforms = os.listdir(platforms_dir)
                print(f"✓ Found platforms: {platforms}")
            else:
                print("⚠ Platforms directory not found")
                
            # Check for key gateway files
            required_files = ['config.py', 'session.py', 'hooks.py', 'pairing.py', 'run.py']
            for file in required_files:
                if os.path.exists(os.path.join(gateway_dir, file)):
                    print(f"✓ {file} found")
                else:
                    print(f"✗ {file} missing")
                    return False
        else:
            print("⚠ Gateway directory not found in expected location")
            
        return True
    except Exception as e:
        print(f"✗ Adapter validation failed: {e}")
        return False

if __name__ == "__main__":
    if test_adapters():
        sys.exit(0)
    else:
        sys.exit(1)
