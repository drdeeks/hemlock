#!/usr/bin/env python3
"""
Import validator for Hermes/OpenClaw framework.
Checks that critical modules can be imported.
"""
import sys
import traceback

def test_imports():
    """Test that we can import the core modules."""
    try:
        # Try to import from the Hermes agent
        from gateway.config import load_gateway_config
        from gateway.session import SessionStore
        from gateway.hooks import HookRegistry
        from gateway.pairing import PairingStore
        from gateway.run import start_gateway
        from tools.process_registry import process_registry
        from gateway.config import Platform
        from gateway.session import SessionSource
        
        print("✓ All Hermes gateway imports successful")
        
        # Try to import OpenClaw runtime (if available)
        try:
            import openclaw_runtime
            print("✓ OpenClaw runtime import successful")
        except ImportError:
            print("⚠ OpenClaw runtime not available (expected in base image)")
            
        return True
    except Exception as e:
        print(f"✗ Import validation failed: {e}")
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if test_imports():
        sys.exit(0)
    else:
        sys.exit(1)
