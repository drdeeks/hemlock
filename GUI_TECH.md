# 🖼️ Hemlock GUI: Technical Blueprint & Architectural Specification

This document serves as the absolute definitive technical guide for integrating the Hemlock Enterprise Agent Framework into a Graphical User Interface (GUI). It outlines every function, technical node, and connectivity protocol required to build a robust front-end.

---

## 1. System Architecture (The "Triad")

The GUI must represent and control three distinct layers:

1.  **Open Claw (The Driver)**:
    *   **Function**: Tactical gateway handling multi-channel connectivity (Telegram, Discord, Web).
    *   **GUI Connection**: Control plane for starting/stopping the gateway and monitoring channel status.
2.  **MCP (The Bridge)**:
    *   **Function**: Model Context Protocol node connecting the Gateway to the Agent Brain.
    *   **GUI Connection**: Telemetry for tool calls, session history, and server-side RPC health.
3.  **Hermes (The Brain)**:
    *   **Function**: The reasoning engine running inside isolated containers.
    *   **GUI Connection**: Real-time log streaming, memory visualization, and personality management.

---

## 2. Functional Inventory (API & CLI Nodes)

### A. Project Manager (Workflow Engine)
*   **`plan(name)`**: Trigger a new project blueprint generation.
    *   *GUI Entry*: Project Name Input -> Result: Blueprint ID + Success Factor list.
*   **`confirm(id)`**: Immutably lock a blueprint for execution.
    *   *GUI Entry*: "Final Confirmation" toggle on draft blueprints.
*   **`handoff(id)`**: Execute the transition to autonomous Lead Agent control.
    *   *GUI Entry*: "Initiate Mission" button.
*   **`blueprint-status(id)`**: Fetch real-time audit logs and success factor validation.
    *   *GUI Entry*: Status timeline with color-coded "Success" nodes and forensic audit log viewer.

### B. Agent Management (Isolation Node)
*   **`create-agent(id, model, personality)`**: Provision a new container with an isolated volume.
    *   *GUI Entry*: Configuration wizard (ID, Name, Model selection, Personality prompt).
*   **`list-agents()`**: Enumerate active and archived agent nodes.
    *   *GUI Entry*: Grid/List view with status indicators (Running/Stopped).
*   **`control(start|stop|restart, id)`**: Manage container lifecycle.
    *   *GUI Entry*: Power controls on each agent card.
*   **`export/import(id, path)`**: Handle portable agent bundles (preserving volumes/secrets).
    *   *GUI Entry*: Drag-and-drop import and download-link export.

### C. System Operations (Health & Diagnostics)
*   **`hemlock-doctor`**: Run the comprehensive diagnostic suite.
    *   *GUI Entry*: "System Check" dashboard showing score (0-100%) and category health.
*   **`initialize()`**: First-run setup for local models and Llama.cpp.
    *   *GUI Entry*: Setup wizard with hardware detection status.
*   **`status()`**: High-level overview of total agents, crews, and memory coverage.
    *   *GUI Entry*: KPI summary bar.

---

## 3. Technical Integration Points

### 📁 Data Isolation (Docker Volumes)
*   Each agent has a dedicated volume: `hemlock-<id>-bundle`.
*   **GUI Requirement**: Ability to view volume usage and browse/edit workspace files (`/app/agent/workspace`).

### 🛠️ The Global Toolkit (Standardized Injection)
Every agent MUST contain and utilize these tools (automatically injected via `enforce.sh`):
1.  **`enforce.sh`**: Self-healing protocol for directory structure.
2.  **`secret.sh`**: Secure vault for API keys and encrypted tokens.
3.  **`memory-log.sh`**: Appends entries to the daily journal.
4.  **`memory-promote.sh`**: Distills daily logs into `MEMORY.md`.
5.  **`jsonfmt.py`**: Ensures all communication between nodes is valid structured data.

### ⛓️ Communication & Memory
*   **Protocol**: All agent communication is structured JSON over MCP.
*   **Memory Layers**:
    *   *Tier 1 (Ephemeral)*: Current session window.
    *   *Tier 2 (Daily)*: `memory/YYYY-MM-DD.md` (Raw chronological log).
    *   *Tier 3 (Long-term)*: `MEMORY.md` (Curated wisdom).
    *   *Tier 4 (Core)*: `SOUL.md` (Personality and identity).

---

## 4. UI/UX "High-Taste" Guidelines

To maintain the Hemlock Enterprise aesthetic, the GUI should implement:
-   **Machined Aesthetic**: Use "Double-Bezel" containers with razor-thin hairlines.
-   **Tactical Telemetry**: Monospaced fonts for audit logs and system info.
-   **Immersive Atmosphere**: Subtle backdrop blurs and generative "Ether" backgrounds.
-   **Phantasm Palette**: Electric Cyan (#00FFFF), Deep Indigo (#4B0082), and Vantablack backgrounds.

---

## 5. Connectivity Matrix

| GUI Action | CLI Command | Target Component | Protocol |
| :--- | :--- | :--- | :--- |
| Send Msg | `openclaw send` | Gateway | WebSocket |
| Get Logs | `docker logs` | Agent Container | Stdio |
| Edit Soul | `cat > SOUL.md` | Isolated Volume | FS Mount |
| Run Diagnostic | `hemlock-doctor` | Host Runtime | Bash |
| Tool Call | `mcp call` | Hermes Brain | MCP RPC |