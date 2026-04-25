# Tools Directory

This directory contains shared tools that can be used by all Hermes agents through the OpenClaw Gateway.

## Tool Structure

Each tool is contained in its own subdirectory with the following structure:

```
tools/
└── <tool_name>/
    ├── tool.yaml      # Tool metadata and configuration
    ├── main.py        # Main tool implementation
    ├── requirements.txt # Python dependencies
    ├── README.md      # Tool documentation
    └── ...            # Additional files as needed
```

## Tool Configuration (tool.yaml)

```yaml
tool:
  name: <tool_name>          # Tool name
  description: <description>   # What the tool does
  version: <version>          # Tool version
  author: <author>            # Tool author
  requirements:              # Requirements
    - <requirement_1>
    - <requirement_2>
  permissions:               # Required permissions
    - <permission_1>
    - <permission_2>
  security:                 # Security settings
    sandbox: true            # Run in sandbox
    timeout: 30              # Timeout in seconds
```

## Creating a New Tool

1. Create a new directory for your tool
2. Add a `tool.yaml` configuration file
3. Implement the tool in `main.py`
4. Add any dependencies to `requirements.txt`
5. Document the tool in `README.md`

## Example Tool: Web Browser

```
tools/
└── browser/
    ├── tool.yaml
    ├── main.py
    ├── requirements.txt
    └── README.md
```

### tool.yaml

```yaml
tool:
  name: browser
  description: Full-featured web browser for agents
  version: 1.0.0
  author: OpenClaw Team
  requirements:
    - playwright
  permissions:
    - internet-access
    - browser-automation
  security:
    sandbox: true
    timeout: 60
```

### main.py

```python
from playwright.sync_api import sync_playwright

def browse(url, actions=None):
    """Browse to a URL and perform actions"""
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        page.goto(url)
        
        # Perform actions if specified
        if actions:
            for action in actions:
                # Execute action
                pass
        
        content = page.content()
        browser.close()
        return content

def main(args):
    url = args.get('url')
    actions = args.get('actions', [])
    
    if not url:
        return {"error": "URL parameter is required"}
    
    result = browse(url, actions)
    return {"content": result}
```

### requirements.txt

```
playwright==1.27.1
```

## Using Tools

Agents use tools through the OpenClaw Gateway. The Gateway provides:
- Tool discovery
- Access control
- Execution environment
- Result formatting
- Security sandboxing

## Tool Best Practices

1. **Modularity**: Keep tools focused on specific capabilities
2. **Documentation**: Document inputs, outputs, and examples
3. **Error Handling**: Gracefully handle errors and timeouts
4. **Security**: Declare required permissions and security settings
5. **Testing**: Include test cases for your tool
6. **Sandboxing**: Use sandboxing for tools that need it

## Tool Security

- Tools run in isolated environments
- Permissions are strictly enforced
- Timeouts prevent hanging
- Sensitive operations require approval

## Shared vs Agent-Specific Tools

- **Shared Tools** (in this directory): Available to all agents
- **Agent-Specific Tools** (in agent directory): Only available to that agent

## Tool Validation

Validate tools with:

```bash
./scripts/runtime-doctor.sh --tools
```