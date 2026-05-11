# 🌿 Hemlock: Enterprise AI Agent Framework (v4)

Hemlock is a production-grade, strictly isolated container orchestration framework for autonomous AI agents and crews. Driven by **Open Claw** and powered by the **Hermes Agent Brain**, it provides a secure, modular environment for multi-agent narrative and technical automation.

## 🚀 Vision: Data Sovereignty
Hemlock enables the deployment of self-improving agents across multiple compute environments (local, cloud, or clusters) with **100% data isolation**. It is blockchain-neutral and environment-agnostic.

## 🏗️ The Hemlock Architecture

1.  **Open Claw (The Driver)**: Tactical gateway for multi-channel messaging (Telegram/Discord).
2.  **MCP Protocol (The Connection)**: Seamless bridge between the driver and the reasoning brain.
3.  **Hermes (The Brain)**: Pythonic reasoning loop with 40+ tools and auto-learning.
4.  **Isolated Volumes**: Every agent resides in a unique `hemlock-<id>-bundle` Docker volume.

## 🛡️ Enterprise Security & Safety
- **Strict Isolation**: Agents can access their own `workspace/`, `terminal`, and `web`, but are **hard-blocked** from other agents' volumes or core system configuration files.
- **Standards Injection**: Every agent is automatically provisioned with the **Master Toolkit** (`enforce.sh`, `secret.sh`, `memory-log.sh`, `memory-promote.sh`, `jsonfmt.py`).
- **Handoff Management**: Supports a robust "One Agent at a Time" sequential handoff protocol for complex projects.
- **Cooked-In Skills**: All agents receive the **Sub-Agent Driven Deployment** skill in their startup sequence, allowing for structured mission delegation.

## 🧠 Memory Protocol (Append-Only)
Hemlock implements a four-tier memory standard that agents review on every startup:
- `SOUL.md`: Core personality and narrative constraints.
- `USER.md`: Authenticated user preferences.
- `MEMORY.md`: Long-term curated wisdom.
- `memory/memory_MM_DD_YY.md`: Daily chronological logs (Append-only; never overwritten).
- `.secrets/`: Secure credential mapping.

## 🛠️ Getting Started

### Prerequisites
- **Docker & Docker Compose**: Essential for containerized isolation.
- **Local Models**: Optimised for `ollama/qwen3:0.6b` but compatible with any OpenAI-compatible API (Llama.cpp, OpenRouter).

### Initialization
```bash
# Setup framework nodes and local model environment
./runtime.sh initialize

# Enter the interactive command node
./runtime.sh
```

### Situational Usage
- **Plan a Project**: Use the `Project Manager` menu to generate a blueprint.
- **Create an Agent**: Provision an isolated node with standardized tool injection.
- **Run Diagnostics**: Execute `hemlock-doctor` to verify framework compliance.

## 📜 Legal & Agnostic Note
Hemlock is environment-neutral. It maintains a strict isolation protocol suitable for high-security deployment across any host infrastructure without external dependency lock-in.

---
*Built with Finality by Dr. Deeks & Blake (Wingman)*