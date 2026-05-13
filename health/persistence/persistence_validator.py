#!/usr/bin/env python3
"""
Persistence validator for Hermes/OpenClaw framework.
Checks that persistence mechanisms are available.
"""
import sys
import os
import tempfile

def test_persistence():
    """Test that we can write and read from persistence layer."""
    try:
        # Test SQLite
        import sqlite3
        with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
            db_path = f.name
        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, data TEXT)")
            cursor.execute("INSERT INTO test (data) VALUES (?)", ("test",))
            conn.commit()
            cursor.execute("SELECT data FROM test WHERE id=1")
            row = cursor.fetchone()
            if row and row[0] == "test":
                print("✓ SQLite persistence test passed")
            else:
                print("✗ SQLite persistence test failed: data mismatch")
                return False
            conn.close()
        finally:
            os.unlink(db_path)
        
        # Test JSON persistence
        import json
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json_path = f.name
            json.dump({"test": "data"}, f)
        try:
            with open(json_path, 'r') as f:
                data = json.load(f)
            if data.get("test") == "data":
                print("✓ JSON persistence test passed")
            else:
                print("✗ JSON persistence test failed: data mismatch")
                return False
        finally:
            os.unlink(json_path)
            
        return True
    except Exception as e:
        print(f"✗ Persistence validation failed: {e}")
        return False

if __name__ == "__main__":
    if test_persistence():
        sys.exit(0)
    else:
        sys.exit(1)
