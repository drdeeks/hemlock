# =============================================================================
# OpenClaw Enterprise Framework - Main Dockerfile
# 
# Builds the complete framework image with all agents, crews, plugins, and skills
# Can be used as a base for agent-specific images or standalone deployment
# =============================================================================

# Use official Python image as base
FROM python:3.11-slim as base

# =============================================================================
# Stage 1: Builder stage - Install all dependencies
# =============================================================================
FROM base as builder

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for the framework
RUN pip install --no-cache-dir --upgrade \
    pip \
    setuptools \
    wheel

# Install OpenClaw core components
RUN pip install --no-cache-dir \
    hermes-agent==0.15.0 \
    openclaw-client==0.15.0 \
    openclaw==0.15.0

# =============================================================================
# Stage 2: Framework image - Complete runtime environment
# =============================================================================
FROM base as framework

# Copy system dependencies from builder
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/lib/python3.11/dist-packages /usr/local/lib/python3.11/dist-packages

# Install runtime system dependencies (minimal)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create framework directory structure
RUN mkdir -p /app/{agents,crews,config,plugins,skills,tools,logs,data,scripts,lib}

# Copy framework entrypoint
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Copy configuration files
COPY config/ /app/config/

# Copy docker configurations
COPY docker-compose.yml /app/docker-compose.yml

# Copy all framework components (hidden files included with COPY + trailing /)
COPY agents/ /app/agents/
COPY crews/ /app/crews/
COPY plugins/ /app/plugins/
COPY skills/ /app/skills/
COPY tools/ /app/tools/
COPY scripts/ /app/scripts/
COPY lib/ /app/lib/

# Set environment variables
ENV RUNTIME_ROOT=/app
ENV AGENTS_DIR=/app/agents
ENV CREWS_DIR=/app/crews
ENV CONFIG_DIR=/app/config
ENV PLUGINS_DIR=/app/plugins
ENV SKILLS_DIR=/app/skills
ENV TOOLS_DIR=/app/tools
ENV LOGS_DIR=/app/logs
ENV SCRIPTS_DIR=/app/scripts
ENV LIB_DIR=/app/lib

# Default gateway configuration
ENV OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
ENV OPENCLAW_GATEWAY_TOKEN=change_this_to_a_secure_token
ENV OPENCLAW_GATEWAY_BIND=lan
ENV OPENCLAW_GATEWAY_PORT=18789

# Default agent settings
ENV DEFAULT_AGENT_MODEL=nous/mistral-large
ENV DEFAULT_AGENT_NETWORK=agents_net

# Security settings
ENV READ_ONLY=true
ENV CAP_DROP=true
ENV ICC=false

# Framework version
ENV FRAMEWORK_VERSION=1.0.0
ENV FRAMEWORK_NAME=openclaw-enterprise

# Set working directory
WORKDIR /app

# Expose gateway port
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -fsS http://localhost:18789/healthz || exit 1

# Entrypoint - can be overridden
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--help"]
