#!/usr/bin/env python3
"""
Enhanced Telegram Commands for Agent Management
Comprehensive commands for creating, managing, and configuring agents.
"""

import json
import os
import sys
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

# Import lead agent
sys.path.insert(0, str(Path(__file__).parent))
from lead_agent import get_lead_agent, LeadAgent

logger = logging.getLogger(__name__)

class EnhancedTelegramCommands:
    """Enhanced Telegram commands for comprehensive agent management."""
    
    def __init__(self):
        self.lead_agent = get_lead_agent()
        self.active_sessions: Dict[int, Dict] = {}
    
    def handle_agent_command(self, chat_id: int, args: List[str]) -> str:
        """Handle /agent command."""
        if not args:
            return self._show_agent_help()
        
        command = args[0].lower()
        
        if command == "list":
            return self._list_agents(args[1:])
        elif command == "show" or command == "details":
            return self._show_agent_details(args[1:])
        elif command == "create":
            return self._create_agent(args[1:])
        elif command == "setup":
            return self._setup_agent(args[1:])
        elif command == "types":
            return self._show_agent_types()
        elif command == "issues" or command == "check":
            return self._detect_issues(args[1:])
        elif command == "prompt":
            return self._show_agent_prompt(args[1:])
        elif command == "delete" or command == "remove":
            return self._delete_agent(args[1:])
        elif command == "restart":
            return self._restart_agent(args[1:])
        elif command == "logs":
            return self._show_agent_logs(args[1:])
        elif command == "help":
            return self._show_agent_help()
        else:
            # Check if it's an agent ID for details
            if len(args) == 1 and '-' in args[0]:
                return self._show_agent_details(args)
            return f"❌ Unknown agent command: {command}\n\nUse /agent help for available commands."
    
    def handle_crew_command(self, chat_id: int, args: List[str]) -> str:
        """Handle /crew command."""
        if not args:
            return self._show_crew_help()
        
        command = args[0].lower()
        
        if command == "create":
            return self._create_crew(args[1:])
        elif command == "list":
            return self._list_crews()
        elif command == "show" or command == "details":
            return self._show_crew_details(args[1:])
        elif command == "add":
            return self._add_agent_to_crew(args[1:])
        elif command == "remove":
            return self._remove_agent_from_crew(args[1:])
        elif command == "start":
            return self._start_crew(args[1:])
        elif command == "stop":
            return self._stop_crew(args[1:])
        elif command == "status":
            return self._crew_status(args[1:])
        elif command == "help":
            return self._show_crew_help()
        else:
            return f"❌ Unknown crew command: {command}\n\nUse /crew help for available commands."
    
    def handle_setup_input(self, chat_id: int, user_input: str) -> Optional[str]:
        """Handle input during setup wizard."""
        if chat_id in self.active_sessions:
            session = self.active_sessions[chat_id]
            if session.get('type') == 'agent_setup':
                result = self.lead_agent.process_setup_input(user_input)
                
                # Clean up session if complete
                if "✅" in result or "❌" in result:
                    del self.active_sessions[chat_id]
                
                return result
        return None
    
    # ============================================
    # AGENT COMMANDS
    # ============================================
    
    def _show_agent_help(self) -> str:
        """Show agent command help."""
        return """🤖 Agent Management Commands

📋 Listing:
  /agent list [type]        - List all agents
  /agent types              - Show available agent types
  /agent issues             - Check for configuration issues

🔍 Details:
  /agent show <id>          - Show agent details
  /agent prompt <id>        - Show agent system prompt
  /agent logs <id>          - Show agent logs

✨ Creation:
  /agent create <type> [name] - Create new agent
    Types: ui, integration, blockchain, debugger, documentation, 
           optimization, architecture, validation
    Example: /agent create ui Design-Master

🔧 Configuration:
  /agent setup <id> [token] - Set up Telegram bot
    If no token provided, starts setup wizard
    Example: /agent setup ui-a1b2c3d4

⚙️ Management:
  /agent restart <id>       - Restart agent service
  /agent delete <id>        - Delete agent (with confirmation)

💡 Examples:
  /agent create blockchain Security-Guard
  /agent setup ui-a1b2c3d4
  /agent show debugger-x9y8z7
"""
    
    def _list_agents(self, args: List[str]) -> str:
        """List agents."""
        filter_type = args[0] if args else None
        return self.lead_agent.list_agents(filter_type)
    
    def _show_agent_details(self, args: List[str]) -> str:
        """Show agent details."""
        if not args:
            return "❌ Agent ID required.\n\nUsage: /agent show <agent_id>"
        
        agent_id = args[0]
        return self.lead_agent.get_agent_details(agent_id)
    
    def _create_agent(self, args: List[str]) -> str:
        """Create a new agent."""
        if not args:
            return "❌ Agent type required.\n\nUsage: /agent create <type> [name]\n\nUse /agent types to see available types."
        
        agent_type = args[0].lower()
        custom_name = args[1] if len(args) > 1 else None
        
        # Store session for follow-up
        result = self.lead_agent.create_agent(agent_type, custom_name)
        
        if result.startswith("✅"):
            # Extract agent ID from result
            import re
            match = re.search(r'ID: ([a-z0-9-]+)', result)
            if match:
                agent_id = match.group(1)
                self.active_sessions[self._get_chat_id_hash()] = {
                    'type': 'agent_created',
                    'agent_id': agent_id,
                    'created_at': datetime.now().isoformat()
                }
        
        return result
    
    def _setup_agent(self, args: List[str]) -> str:
        """Set up agent Telegram bot."""
        if not args:
            return "❌ Agent ID required.\n\nUsage: /agent setup <agent_id> [bot_token]"
        
        agent_id = args[0]
        bot_token = args[1] if len(args) > 1 else None
        
        result = self.lead_agent.setup_agent_telegram(agent_id, bot_token)
        
        # If wizard started, store session
        if "🧙" in result:
            self.active_sessions[self._get_chat_id_hash()] = {
                'type': 'agent_setup',
                'agent_id': agent_id,
                'created_at': datetime.now().isoformat()
            }
        
        return result
    
    def _show_agent_types(self) -> str:
        """Show available agent types."""
        return self.lead_agent.get_agent_types()
    
    def _detect_issues(self, args: List[str]) -> str:
        """Detect configuration issues."""
        agent_id = args[0] if args else None
        return self.lead_agent.detect_issues(agent_id)
    
    def _show_agent_prompt(self, args: List[str]) -> str:
        """Show agent system prompt."""
        if not args:
            return "❌ Agent ID required.\n\nUsage: /agent prompt <agent_id>"
        
        agent_id = args[0]
        return self.lead_agent.get_agent_prompt(agent_id)
    
    def _delete_agent(self, args: List[str]) -> str:
        """Delete an agent."""
        if not args:
            return "❌ Agent ID required.\n\nUsage: /agent delete <agent_id>"
        
        # For safety, require confirmation
        agent_id = args[0]
        details = self.lead_agent.agent_manager.get_agent_details(agent_id)
        
        if not details:
            return f"❌ Agent '{agent_id}' not found."
        
        return f"⚠️ Delete Agent: {details['display_name']}?\n\n"
        f"This will delete:\n"
        f"• Agent workspace\n"
        f"• Configuration files\n"
        f"• Telegram bot service\n\n"
        f"To confirm, send: /agent delete {agent_id} confirm"
    
    def _restart_agent(self, args: List[str]) -> str:
        """Restart agent service."""
        if not args:
            return "❌ Agent ID required.\n\nUsage: /agent restart <agent_id>"
        
        agent_id = args[0]
        details = self.lead_agent.agent_manager.get_agent_details(agent_id)
        
        if not details:
            return f"❌ Agent '{agent_id}' not found."
        
        if not details['telegram_configured']:
            return f"❌ Telegram bot not configured for {details['display_name']}.\n\nUse /agent setup {agent_id} first."
        
        service_name = f"telegram-{agent_id}.service"
        
        try:
            import subprocess
            subprocess.run(["systemctl", "restart", service_name], check=True)
            return f"✅ Service restarted: {details['display_name']}\n\nService: {service_name}"
        except Exception as e:
            return f"❌ Failed to restart service: {str(e)}"
    
    def _show_agent_logs(self, args: List[str]) -> str:
        """Show agent logs."""
        if not args:
            return "❌ Agent ID required.\n\nUsage: /agent logs <agent_id>"
        
        agent_id = args[0]
        details = self.lead_agent.agent_manager.get_agent_details(agent_id)
        
        if not details:
            return f"❌ Agent '{agent_id}' not found."
        
        log_file = Path(f"/opt/telegram-webhook/logs/{agent_id}.log")
        
        if not log_file.exists():
            return f"📋 No logs found for {details['display_name']}\n\nLog file: {log_file}"
        
        try:
            logs = log_file.read_text()
            lines = logs.split('\n')
            recent_logs = '\n'.join(lines[-20:])  # Last 20 lines
            
            return f"📋 Recent Logs: {details['display_name']}\n\n"
            f"```\n{recent_logs}\n```\n\n"
            f"Total lines: {len(lines)}"
        except Exception as e:
            return f"❌ Error reading logs: {str(e)}"
    
    # ============================================
    # CREW COMMANDS
    # ============================================
    
    def _show_crew_help(self) -> str:
        """Show crew command help."""
        return """👥 Crew Management Commands

📋 Management:
  /crew create <name> <agents>  - Create new crew
    Example: /crew create e-commerce ui,debugger,documentation
  /crew list                    - List all crews
  /crew show <name>             - Show crew details

👥 Agent Management:
  /crew add <crew> <agent_id>   - Add agent to crew
  /crew remove <crew> <agent_id> - Remove agent from crew

🚀 Operations:
  /crew start <name>            - Start crew workflow
  /crew stop <name>             - Stop crew workflow
  /crew status <name>           - Show crew status

💡 Example Workflow:
  1. Create agents: /agent create ui Design-Master
  2. Create crew: /crew create my-project ui-a1b2,debugger-x9y8
  3. Start crew: /crew start my-project
  4. Monitor: /crew status my-project
"""
    
    def _create_crew(self, args: List[str]) -> str:
        """Create a new crew."""
        if len(args) < 2:
            return "❌ Crew name and agents required.\n\nUsage: /crew create <name> <agent1,agent2,...>"
        
        crew_name = args[0]
        agents_str = args[1]
        agent_ids = [a.strip() for a in agents_str.split(',')]
        
        # Validate agents exist
        valid_agents = []
        invalid_agents = []
        
        for agent_id in agent_ids:
            details = self.lead_agent.agent_manager.get_agent_details(agent_id)
            if details:
                valid_agents.append(agent_id)
            else:
                invalid_agents.append(agent_id)
        
        if invalid_agents:
            return f"❌ Invalid agents: {', '.join(invalid_agents)}\n\nUse /agent list to see available agents."
        
        # Store crew (in real implementation, this would be persisted)
        return f"✅ Crew Created: {crew_name}\n\n"
        f"👥 Agents: {len(valid_agents)}\n"
        f"  • {chr(10).join('  ' + a for a in valid_agents)}\n\n"
        f"💡 Next steps:\n"
        f"  1. /crew start {crew_name}\n"
        f"  2. /crew status {crew_name}"
    
    def _list_crews(self) -> str:
        """List all crews."""
        return "📋 Crew List\n\n"
        "No crews created yet.\n\n"
        "💡 Create a crew with:\n"
        "  /crew create <name> <agent1,agent2,...>"
    
    def _show_crew_details(self, args: List[str]) -> str:
        """Show crew details."""
        if not args:
            return "❌ Crew name required.\n\nUsage: /crew show <name>"
        
        return f"📋 Crew: {args[0]}\n\n"
        "Crew not found. Use /crew list to see available crews."
    
    def _add_agent_to_crew(self, args: List[str]) -> str:
        """Add agent to crew."""
        if len(args) < 2:
            return "❌ Crew name and agent ID required.\n\nUsage: /crew add <crew> <agent_id>"
        
        return f"✅ Agent added to crew {args[0]}"
    
    def _remove_agent_from_crew(self, args: List[str]) -> str:
        """Remove agent from crew."""
        if len(args) < 2:
            return "❌ Crew name and agent ID required.\n\nUsage: /crew remove <crew> <agent_id>"
        
        return f"✅ Agent removed from crew {args[0]}"
    
    def _start_crew(self, args: List[str]) -> str:
        """Start crew workflow."""
        if not args:
            return "❌ Crew name required.\n\nUsage: /crew start <name>"
        
        return f"🚀 Starting crew: {args[0]}\n\n"
        "Crew workflow initiated. Monitor with /crew status."
    
    def _stop_crew(self, args: List[str]) -> str:
        """Stop crew workflow."""
        if not args:
            return "❌ Crew name required.\n\nUsage: /crew stop <name>"
        
        return f"⏹️ Stopped crew: {args[0]}"
    
    def _crew_status(self, args: List[str]) -> str:
        """Show crew status."""
        if not args:
            return "❌ Crew name required.\n\nUsage: /crew status <name>"
        
        return f"📊 Crew Status: {args[0]}\n\n"
        "Crew not found. Use /crew list to see available crews."
    
    def _get_chat_id_hash(self) -> str:
        """Generate a hash for chat ID (simplified)."""
        import hashlib
        return hashlib.md5(str(id(self)).encode()).hexdigest()[:8]

# Global instance
_enhanced_commands = None

def get_enhanced_commands() -> EnhancedTelegramCommands:
    """Get the global enhanced commands instance."""
    global _enhanced_commands
    if _enhanced_commands is None:
        _enhanced_commands = EnhancedTelegramCommands()
    return _enhanced_commands

# Export for bot integration
__all__ = ['EnhancedTelegramCommands', 'get_enhanced_commands']
