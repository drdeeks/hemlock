FROM python:3.11-slim

# System deps — Node.js, ffmpeg, build tools, Java
RUN apt-get update && apt-get install -y \
    curl git jq ffmpeg \
    build-essential cmake \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user matching host UID/GID (prevents root-owned files on bind mounts)
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} agent 2>/dev/null || true \
    && useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash agent 2>/dev/null || true

# Python packages — hermes-agent + common skill dependencies
COPY --chown=agent:agent hermes-agent/ /app/hermes-agent/
WORKDIR /app/hermes-agent
RUN pip install --no-cache-dir -e "." \
    && pip install --no-cache-dir \
        pyyaml \
        python-telegram-bot \
        requests \
        Pillow \
        eth_account \
        defusedxml

# Apply patches: !command execution, /models command
COPY --chown=agent:agent patches/ /app/patches/
RUN python3 /app/patches/add_extras.py

# Verify installations
RUN python3 -c "import requests, PIL, yaml; print('Python: OK')" \
    && node --version && npm --version \
    && ffmpeg -version | head -1

COPY --chown=agent:agent entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

WORKDIR /app
USER agent
ENTRYPOINT ["/app/entrypoint.sh"]
