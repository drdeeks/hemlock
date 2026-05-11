#!/usr/bin/env python3
import yaml
import ast

# Validate compose
yaml.safe_load(open("/home/drdeek/.openclaw/docker/docker-compose.yml"))
print("COMPOSE YAML: VALID")

# Validate plugin
ast.parse(open("/home/drdeek/.hermes/plugins/tool-enforcement/__init__.py").read())
print("PLUGIN PYTHON: VALID")
