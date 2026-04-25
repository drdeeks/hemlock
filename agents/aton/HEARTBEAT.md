# HEARTBEAT.md - Aton's Periodic Checks

# Aton: Autonomous agent - checks research activity, tool integration, and autonomous projects.

import sys
import os
import json
import subprocess
from datetime import datetime, timedelta

sys.path.append(os.path.expanduser("~/.openclaw"))
from shared.heartbeat_lib import Heartbeat

def run_aton_heartbeat():
    hb = Heartbeat("aton")
    
    # Aton checks every 1 hour (highest frequency for autonomous research)
    if not hb.should_run(interval_hours=1):
        return "Heartbeat not due for Aton."
    
    # Run full checks
    results = hb.run_full_check({
        "id": "aton", 
        "type": "autonomous"
    })
    
    # Aton-specific checks:
    # - Check research activity (highest priority)
    try:
        research_dir = os.environ.get("HERMES_HOME", os.path.expanduser("~/.openclaw/agents/aton")) + "/memory"
        research_files = []
        for fname in os.listdir(research_dir):
            if fname.endswith('.md') and not fname.startswith('heartbeat'):
                fpath = os.path.join(research_dir, fname)
                if os.path.getmtime(fpath) > time.time() - 24*3600:  # 24 hours
                    with open(fpath, "r") as f:
                        content = f.read()
                        if any(keyword in content.lower() for keyword in ["research", "discovery", "idea", "experiment", "exploration", "analysis"]):
                            research_files.append(fname)
        
        if research_files:
            hb.log(f"Found {len(research_files)} recent research files")
            results["checks"]["research_activity"] = {"ok": True, "files": len(research_files)}
        else:
            hb.log("⚠️ No recent research activity detected!")
            results["checks"]["research_activity"] = {"ok": False, "note": "no_recent_research"}
            # Escalate to Tom for autonomous agents with no research
            try:
                from shared.task_registry import TaskRegistry
                registry = TaskRegistry()
                registry.create_task({
                    "id": f"research_alert_aton_{int(time.time())}",
                    "description": "Aton hasn't shown research activity in 24h. Autonomous agent needs attention.",
                    "agent_id": "tom",
                    "priority": "high",
                    "follow_up_due": (datetime.utcnow() + timedelta(hours=2)).isoformat() + "Z"
                })
            except:
                pass
    except:
        pass
    
    # - Check for autonomous projects
    try:
        project_dir = os.environ.get("HERMES_HOME", os.path.expanduser("~/.openclaw/agents/aton")) + "/projects"
        if os.path.exists(project_dir):
            projects = os.listdir(project_dir)
            if projects:
                hb.log(f"Found {len(projects)} autonomous projects")
                results["checks"]["autonomous_projects"] = {"ok": True, "projects": len(projects)}
            else:
                hb.log("No autonomous projects found")
                results["checks"]["autonomous_projects"] = {"ok": False, "note": "no_projects"}
        else:
            results["checks"]["autonomous_projects"] = {"ok": False, "note": "no_project_dir"}
    except:
        pass
    
    # - Check for Farcaster integration
    try:
        farcaster_skill_path = os.environ.get("HERMES_HOME", os.path.expanduser("~/.openclaw/agents/aton")) + "/skills/farcaster-agent"
        if os.path.exists(farcaster_skill_path):
            hb.log("Farcaster skill installed")
            results["checks"]["farcaster_integration"] = {"ok": True, "installed": True}
        else:
            hb.log("Farcaster skill not found")
            results["checks"]["farcaster_integration"] = {"ok": False, "installed": False}
    except:
        pass
    
    # - Check for recent tool usage
    try:
        recent_tools = []
        tool_dirs = [os.environ.get("HERMES_HOME", os.path.expanduser("~/.openclaw/agents/aton")) + "/memory"]
        for tool_dir in tool_dirs:
            for fname in os.listdir(tool_dir):
                if fname.endswith('.md') and not fname.startswith('heartbeat'):
                    fpath = os.path.join(tool_dir, fname)
                    if os.path.getmtime(fpath) > time.time() - 24*3600:
                        with open(fpath, "r") as f:
                            content = f.read()
                            if any(keyword in content.lower() for keyword in ["exec", "tool", "function", "analysis", "research"]):
                                recent_tools.append(fname)
        
        if recent_tools:
            hb.log(f"Found {len(recent_tools)} recent tool usage files")
            results["checks"]["tool_usage"] = {"ok": True, "files": len(recent_tools)}
        else:
            hb.log("No recent tool usage detected")
            results["checks"]["tool_usage"] = {"ok": False, "note": "no_tool_usage"}
    except:
        pass
    
    # - Check if Aton is using his own API key
    try:
        config_path = os.environ.get("HERMES_HOME", os.path.expanduser("~/.openclaw/agents/aton")) + "/config.json"
        with open(config_path, "r") as f:
            config = json.load(f)
        model = config.get("model", {}).get("primary", "")
        if model.startswith("openrouter:aton/"):
            hb.log("Aton using correct API key")
            results["checks"]["api_isolation"] = {"ok": True, "using_own_key": True}
        else:
            hb.log("Aton not using own API key!")
            results["checks"]["api_isolation"] = {"ok": False, "using_own_key": False}
    except:
        pass
    
    hb.record_heartbeat({
        "checks_passed": results["checks_passed"],
        "checks_total": results["checks_total"],
        "role": "autonomous",
        "research_activity": len(research_files) if 'research_activity' in results["checks"] else 0,
        "autonomous_projects": len(projects) if 'autonomous_projects' in results["checks"] else 0
    })
    
    summary = f"Aton heartbeat complete. Overall: {results['overall']}"
    print(summary)
    hb.log(summary)
    return results

if __name__ == "__main__":
    run_aton_heartbeat()
# Workspace enforcement (auto)
bash ~/.openclaw/agents/.scripts/agent-toolkit/agent-bootstrap.sh enforce
