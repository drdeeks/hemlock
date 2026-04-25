#!/usr/bin/env python3
"""
Telegram Bot Commands for Autonomous Crew System
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from autonomous_crew import CrewManager

class CrewTelegramCommands:
    """Telegram commands for crew management."""
    
    def __init__(self):
        self.active_crews: Dict[str, CrewManager] = {}
        self.default_project_path = "/home/ubuntu/hermes-agent/workspaces"
    
    def handle_crew_command(self, chat_id: int, args: List[str]) -> str:
        """Handle /crew command."""
        if not args:
            return self._show_crew_help()
        
        command = args[0].lower()
        
        if command == "init":
            return self._init_crew(chat_id, args[1:])
        elif command == "status":
            return self._show_crew_status(chat_id, args[1:])
        elif command == "agents":
            return self._list_agents(chat_id, args[1:])
        elif command == "blueprint":
            return self._show_blueprint(chat_id, args[1:])
        elif command == "checkpoint":
            return self._create_checkpoint(chat_id, args[1:])
        elif command == "rollback":
            return self._rollback(chat_id, args[1:])
        elif command == "logs":
            return self._show_logs(chat_id, args[1:])
        elif command == "run":
            return self._run_workflow(chat_id, args[1:])
        elif command == "help":
            return self._show_crew_help()
        else:
            return f"❌ Unknown crew command: {command}\n\nUse /crew help for available commands."
    
    def _show_crew_help(self) -> str:
        """Show crew command help."""
        return """🤖 Autonomous Crew Commands

🔧 Setup:
  /crew init <project> [agents] - Initialize new crew
    Example: /crew init my-project ui,debugger,documentation
    Default agents: lead,ui,integration,debugger,documentation,validation

📊 Status:
  /crew status [project] - Show crew status
  /crew agents [project] - List active agents
  /crew blueprint [project] - Show project blueprint
  /crew logs [project] [agent] - Show agent logs

⚡ Actions:
  /crew run [project] - Start autonomous workflow
  /crew checkpoint [project] - Create checkpoint
  /crew rollback [project] <checkpoint> - Rollback to checkpoint

📚 Help:
  /crew help - Show this help

💡 Example Workflow:
  1. /crew init my-project ui,debugger,documentation
  2. /crew status
  3. /crew run
  4. /crew checkpoint
  5. /crew logs
"""
    
    def _init_crew(self, chat_id: int, args: List[str]) -> str:
        """Initialize a new crew."""
        if not args:
            return "❌ Project name required. Usage: /crew init <project> [agents]"
        
        project_name = args[0]
        project_path = Path(self.default_project_path) / project_name
        
        # Parse agent types
        agent_types = ["lead", "ui", "integration", "debugger", "documentation", "validation"]
        if len(args) > 1:
            agent_types = ["lead"] + args[1].split(",")
        
        # Validate agent types
        valid_types = ["lead", "ui", "integration", "blockchain", "debugger", 
                      "documentation", "optimization", "architecture", "validation"]
        
        for agent_type in agent_types:
            if agent_type not in valid_types:
                return f"❌ Invalid agent type: {agent_type}\n\nValid types: {', '.join(valid_types)}"
        
        # Create project directory
        project_path.mkdir(parents=True, exist_ok=True)
        
        # Initialize crew
        crew = CrewManager(str(project_path))
        crew.initialize_crew(
            project_name=project_name,
            success_criteria=[
                "All tests pass",
                "Documentation complete",
                "Code quality meets standards"
            ],
            agent_types=agent_types,
            expected_outcomes=[
                "Fully functional project",
                "Comprehensive documentation",
                "Clean, maintainable code"
            ],
            success_measures=[
                "100% test coverage",
                "Zero critical bugs",
                "Complete API documentation"
            ]
        )
        
        # Store crew
        self.active_crews[project_name] = crew
        
        response = f"✅ Crew initialized for project: {project_name}\n\n"
        response += f"📁 Location: {project_path}\n"
        response += f"👥 Agents: {len(agent_types)}\n"
        response += f"   • {', '.join(agent_types)}\n\n"
        response += "📋 Success Criteria:\n"
        for criterion in crew.blueprint.success_criteria:
            response += f"   • {criterion}\n"
        response += "\n💡 Next steps:\n"
        response += "   1. /crew status - Check status\n"
        response += "   2. /crew run - Start workflow\n"
        response += "   3. /crew logs - Monitor progress"
        
        return response
    
    def _show_crew_status(self, chat_id: int, args: List[str]) -> str:
        """Show crew status."""
        project_name = self._get_project_name(args)
        if not project_name:
            return "❌ Project name required. Usage: /crew status <project>"
        
        crew = self.active_crews.get(project_name)
        if not crew:
            return f"❌ Crew not found for project: {project_name}"
        
        status = crew.get_crew_status()
        
        response = f"📊 Crew Status: {project_name}\n\n"
        response += f"🔄 Phase: {status['current_phase']}\n"
        response += f"👥 Active Agents: {len(status['active_agents'])}\n"
        response += f"📋 Tasks: {status['completed_tasks']}/{status['task_queue_size']}\n"
        response += f"💾 Checkpoints: {status['checkpoints']}\n\n"
        
        # Progress bar
        if status['task_queue_size'] > 0:
            progress = status['completed_tasks'] / status['task_queue_size']
            bar_length = 20
            filled = int(bar_length * progress)
            bar = "█" * filled + "░" * (bar_length - filled)
            response += f"Progress: [{bar}] {progress:.0%}\n\n"
        
        response += "💡 Commands:\n"
        response += "   /crew agents - List agents\n"
        response += "   /crew logs - View logs\n"
        response += "   /crew run - Continue workflow"
        
        return response
    
    def _list_agents(self, chat_id: int, args: List[str]) -> str:
        """List active agents."""
        project_name = self._get_project_name(args)
        if not project_name:
            return "❌ Project name required. Usage: /crew agents <project>"
        
        crew = self.active_crews.get(project_name)
        if not crew:
            return f"❌ Crew not found for project: {project_name}"
        
        logs = crew.get_agent_logs()
        
        response = f"👥 Agents for {project_name}:\n\n"
        
        for agent_id, log_data in logs.items():
            agent_type = log_data.get('agent_type', 'unknown')
            summary = log_data.get('summary', {})
            total = summary.get('total_actions', 0)
            successful = summary.get('successful', 0)
            
            response += f"🤖 {agent_id}\n"
            response += f"   Type: {agent_type}\n"
            response += f"   Actions: {total} (✅ {successful})\n"
            
            if summary.get('obstacles'):
                response += f"   Obstacles: {len(summary['obstacles'])}\n"
            
            response += "\n"
        
        response += f"📊 Total: {len(logs)} agents"
        
        return response
    
    def _show_blueprint(self, chat_id: int, args: List[str]) -> str:
        """Show project blueprint."""
        project_name = self._get_project_name(args)
        if not project_name:
            return "❌ Project name required. Usage: /crew blueprint <project>"
        
        crew = self.active_crews.get(project_name)
        if not crew or not crew.blueprint:
            return f"❌ Blueprint not found for project: {project_name}"
        
        blueprint = crew.blueprint
        
        response = f"📋 Blueprint: {project_name}\n\n"
        
        response += "🎯 Success Criteria:\n"
        for criterion in blueprint.success_criteria:
            response += f"   • {criterion}\n"
        
        response += "\n📈 Expected Outcomes:\n"
        for outcome in blueprint.expected_outcomes:
            response += f"   • {outcome}\n"
        
        response += "\n📏 Success Measures:\n"
        for measure in blueprint.success_measures:
            response += f"   • {measure}\n"
        
        response += f"\n👥 Agents: {len(blueprint.agent_types)}\n"
        response += f"   • {', '.join(blueprint.agent_types)}\n"
        
        response += f"\n🔄 Workflow Steps: {len(blueprint.workflow_steps)} phases\n"
        for step_group in blueprint.workflow_steps:
            response += f"   • {step_group['phase']}: {len(step_group['steps'])} steps\n"
        
        response += f"\n💾 Checkpoints: {len(blueprint.checkpoints)}\n"
        
        return response
    
    def _create_checkpoint(self, chat_id: int, args: List[str]) -> str:
        """Create a checkpoint."""
        project_name = self._get_project_name(args)
        if not project_name:
            return "❌ Project name required. Usage: /crew checkpoint <project>"
        
        crew = self.active_crews.get(project_name)
        if not crew:
            return f"❌ Crew not found for project: {project_name}"
        
        checkpoint_id = crew.create_checkpoint("Manual checkpoint via Telegram")
        
        if checkpoint_id:
            return f"✅ Checkpoint created: {checkpoint_id}\n\nUse /crew rollback {project_name} {checkpoint_id} to restore."
        else:
            return "❌ Failed to create checkpoint"
    
    def _rollback(self, chat_id: int, args: List[str]) -> str:
        """Rollback to checkpoint."""
        if len(args) < 2:
            return "❌ Project and checkpoint required. Usage: /crew rollback <project> <checkpoint>"
        
        project_name = args[0]
        checkpoint_id = args[1]
        
        crew = self.active_crews.get(project_name)
        if not crew:
            return f"❌ Crew not found for project: {project_name}"
        
        success = crew.rollback_to_checkpoint(checkpoint_id)
        
        if success:
            return f"✅ Rolled back to checkpoint: {checkpoint_id}"
        else:
            return f"❌ Failed to rollback to checkpoint: {checkpoint_id}"
    
    def _show_logs(self, chat_id: int, args: List[str]) -> str:
        """Show agent logs."""
        project_name = self._get_project_name(args)
        agent_id = args[1] if len(args) > 1 else None
        
        if not project_name:
            return "❌ Project name required. Usage: /crew logs <project> [agent]"
        
        crew = self.active_crews.get(project_name)
        if not crew:
            return f"❌ Crew not found for project: {project_name}"
        
        logs = crew.get_agent_logs(agent_id)
        
        if agent_id:
            if not logs:
                return f"❌ No logs found for agent: {agent_id}"
            
            response = f"📝 Logs for {agent_id}:\n\n"
            log_data = logs
            
            response += f"🤖 Agent: {log_data['agent_id']}\n"
            response += f"📋 Type: {log_data['agent_type']}\n"
            response += f"⏰ Created: {log_data['created_at']}\n"
            response += f"🔄 Updated: {log_data['updated_at']}\n\n"
            
            summary = log_data.get('summary', {})
            response += "📊 Summary:\n"
            response += f"   Total Actions: {summary.get('total_actions', 0)}\n"
            response += f"   Successful: {summary.get('successful', 0)}\n"
            response += f"   Failed: {summary.get('failed', 0)}\n"
            
            if summary.get('obstacles'):
                response += f"   Obstacles: {len(summary['obstacles'])}\n"
            
            if summary.get('solutions'):
                response += f"   Solutions: {len(summary['solutions'])}\n"
            
            response += f"\n📝 Recent Actions: {len(log_data.get('actions', []))}\n"
            
            # Show last 3 actions
            actions = log_data.get('actions', [])[-3:]
            for action in actions:
                response += f"\n   • {action['timestamp'][:19]}\n"
                response += f"     {action['action']}: {action['details'][:50]}...\n"
        
        else:
            response = f"📝 Logs for {project_name}:\n\n"
            
            for aid, log_data in logs.items():
                summary = log_data.get('summary', {})
                total = summary.get('total_actions', 0)
                successful = summary.get('successful', 0)
                
                response += f"🤖 {aid}: {total} actions (✅ {successful})\n"
            
            response += f"\n📊 Total: {len(logs)} agents"
        
        return response
    
    def _run_workflow(self, chat_id: int, args: List[str]) -> str:
        """Run autonomous workflow."""
        project_name = self._get_project_name(args)
        if not project_name:
            return "❌ Project name required. Usage: /crew run <project>"
        
        crew = self.active_crews.get(project_name)
        if not crew:
            return f"❌ Crew not found for project: {project_name}"
        
        # Start workflow in background
        import threading
        
        def run_workflow():
            crew.run_autonomous_workflow(max_iterations=50)
        
        thread = threading.Thread(target=run_workflow, daemon=True)
        thread.start()
        
        return f"🚀 Started autonomous workflow for {project_name}\n\n"
        "The crew will now work autonomously until success criteria are met.\n\n"
        "Monitor progress with:\n"
        "• /crew status - Check status\n"
        "• /crew logs - View agent logs\n"
        "• /crew checkpoint - Create checkpoint"
    
    def _get_project_name(self, args: List[str]) -> Optional[str]:
        """Get project name from args or active crews."""
        if args:
            return args[0]
        
        # Return first active crew if only one
        if len(self.active_crews) == 1:
            return list(self.active_crews.keys())[0]
        
        return None

# Global instance
_crew_commands = None

def get_crew_commands() -> CrewTelegramCommands:
    """Get the global crew commands instance."""
    global _crew_commands
    if _crew_commands is None:
        _crew_commands = CrewTelegramCommands()
    return _crew_commands

# Export for bot integration
__all__ = ['CrewTelegramCommands', 'get_crew_commands']
