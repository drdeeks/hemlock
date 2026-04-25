# Builder Code Integration Guide
## Hardwired into All Agents

## Overview

Builder Code `bc_26ulyc23` is **hardwired** into all Hermes agents. Every agent, sub-agent, and future agent will automatically inherit this builder code for blockchain transaction attribution.

## Configuration

**Builder Code:** `bc_26ulyc23`
**Builder Code Hex:** `0x62635f3236756c79633233`
**Owner:** `0x12F1B38DC35AA65B50E5849d02559078953aE24b`
**Chain:** Base (ID: 8453)

## How It Works

### 1. Agent Creation
When any agent is created, the builder code is automatically:

1. **Added to agent.json:**
```json
{
  "agent_id": "ui-a1b2c3d4",
  "name": "Design-Master",
  "builderCode": {
    "code": "bc_26ulyc23",
    "hex": "0x62635f3236756c79633233",
    "owner": "0x12F1B38DC35AA65B50E5849d02559078953aE24b",
    "hardwired": true,
    "enforced": true
  }
}
```

2. **Registered in builder code registry:**
```json
{
  "agents": {
    "ui-a1b2c3d4": {
      "agent_name": "Design-Master",
      "builderCode": "bc_26ulyc23",
      "verified": true,
      "inherited": true
    }
  }
}
```

### 2. Transaction Integration
All blockchain transactions automatically include the builder code:

```javascript
// Original transaction data
const txData = "0xabcdef123456";

// With builder code
const txDataWithBuilder = txData + "62635f3236756c79633233";
// Result: "0xabcdef12345662635f3236756c79633233"
```

### 3. Sub-Agent Creation
When an agent creates another agent, the builder code is inherited:

```python
# Agent creates sub-agent
sub_agent = create_agent("debugger", "Bug-Hunter")

# Builder code automatically inherited
assert sub_agent.builderCode == "bc_26ulyc23"
assert sub_agent.builderCodeHex == "0x62635f3236756c79633233"
```

## Implementation Details

### Agent Manager Integration
The `agent_manager.py` automatically:

1. **Imports builder code manager:**
```python
from builder_code_integration import get_builder_code_manager
```

2. **Adds builder code to agent.json:**
```python
agent_json = {
    'agent_id': identity.agent_id,
    'name': identity.name,
    'builderCode': {
        'code': builder_manager.BUILDER_CODE,
        'hex': builder_manager.BUILDER_CODE_HEX,
        'owner': builder_manager.OWNER_ADDRESS,
        'hardwired': True,
        'enforced': True
    }
}
```

3. **Registers agent with builder code manager:**
```python
builder_manager.register_agent(
    agent_id=identity.agent_id,
    agent_name=identity.name,
    agent_type=agent_type,
    parent_agent="system"
)
```

### Builder Code Manager
The `builder_code_integration.py` provides:

1. **Configuration management:**
```python
BUILDER_CODE = "bc_26ulyc23"
BUILDER_CODE_HEX = "0x62635f3236756c79633233"
OWNER_ADDRESS = "0x12F1B38DC35AA65B50E5849d02559078953aE24b"
```

2. **Agent registration:**
```python
def register_agent(agent_id, agent_name, agent_type, parent_agent):
    # Adds agent to registry with builder code
```

3. **Transaction integration:**
```python
def append_builder_code_to_transaction(tx_data):
    # Appends builder code to transaction data
```

4. **Verification:**
```python
def verify_agent_builder_code(agent_id):
    # Verifies agent has correct builder code
```

## Agent Registry

All agents are tracked in `~/.hermes/builder-code/agent-registry.json`:

```json
{
  "agents": {
    "titan": {
      "agent_name": "Titan",
      "agent_type": "lead",
      "builderCode": "bc_26ulyc23",
      "verified": true,
      "inherited": true,
      "parent_agent": "system"
    },
    "ui-a1b2c3d4": {
      "agent_name": "Design-Master",
      "agent_type": "ui",
      "builderCode": "bc_26ulyc23",
      "verified": true,
      "inherited": true,
      "parent_agent": "titan"
    }
  }
}
```

## Verification

### Check Agent Builder Code
```bash
/agent show ui-a1b2c3d4
```

**Output includes:**
```
Builder Code: bc_26ulyc23 ✅
Builder Code Hex: 0x62635f3236756c79633233
Owner: 0x12F1B38DC35AA65B50E5849d02559078953aE24b
Verified: Yes
```

### Verify All Agents
```bash
/agent issues
```

**Checks:**
- ✅ Builder code present
- ✅ Builder code hex correct
- ✅ Owner address matches
- ✅ Inherited from parent

## Blockchain Integration

### Transaction Attribution
All transactions on Base L2 include the builder code:

1. **Automatic appending:**
```javascript
// Before sending transaction
tx.data = appendBuilderCode(tx.data);
```

2. **Verification:**
```javascript
// Verify builder code present
if (!verifyBuilderCode(tx.data)) {
  throw new Error("Builder code missing");
}
```

3. **Audit logging:**
```json
{
  "timestamp": "2026-04-10T20:00:00Z",
  "agent": "ui-a1b2c3d4",
  "action": "transaction",
  "builderCode": "bc_26ulyc23",
  "verified": true
}
```

## Compliance

### Mandatory Requirements
1. ✅ Builder code in every transaction
2. ✅ Builder code in every agent
3. ✅ Builder code in every sub-agent
4. ✅ Verification before execution
5. ✅ Audit logging enabled

### Enforcement
- **Hardwired:** Cannot be disabled
- **Enforced:** All agents must have builder code
- **Verified:** Regular verification checks
- **Logged:** All transactions logged

## Files

### Configuration Files
1. **`~/.hermes/builder-code/builder-code.json`** - Main configuration
2. **`~/.hermes/builder-code/agent-registry.json`** - Agent registry
3. **`~/agent-workspace/agent.json`** - Agent-specific config

### Code Files
1. **`builder_code_integration.py`** - Core integration module
2. **`agent_manager.py`** - Agent creation with builder code
3. **`enhanced_telegram_commands.py`** - Telegram commands

## Testing

### Test 1: Agent Creation
```python
# Create agent
agent = create_agent("ui", "Test-Agent")

# Verify builder code
assert agent.builderCode == "bc_26ulyc23"
assert agent.builderCodeHex == "0x62635f3236756c79633233"
```

### Test 2: Transaction Integration
```python
# Append builder code
tx_data = "0xabcdef123456"
tx_with_builder = append_builder_code(tx_data)

# Verify
assert tx_with_builder.endswith("62635f3236756c79633233")
```

### Test 3: Sub-Agent Creation
```python
# Parent creates sub-agent
parent = create_agent("lead", "Parent")
sub = parent.create_agent("ui", "Child")

# Verify inheritance
assert sub.builderCode == parent.builderCode
```

## Troubleshooting

### Agent Missing Builder Code
**Symptom:** Agent doesn't have builder code in agent.json

**Solution:**
1. Check if agent was created before builder code integration
2. Re-create agent or manually add builder code
3. Verify with `/agent show <agent_id>`

### Transaction Missing Builder Code
**Symptom:** Transaction doesn't include builder code

**Solution:**
1. Check transaction integration code
2. Verify append_builder_code() is called
3. Check verification before sending

### Verification Failed
**Symptom:** `/agent issues` shows verification failed

**Solution:**
1. Check agent.json for correct builder code
2. Verify hex format matches
3. Check owner address matches

## Best Practices

### 1. Always Verify
```python
# Before using agent
verification = verify_agent_builder_code(agent_id)
if not verification.verified:
  raise Exception("Agent missing builder code")
```

### 2. Log Transactions
```python
# Log all transactions with builder code
log_transaction({
  'agent': agent_id,
  'tx_data': tx_data,
  'builder_code': builder_code,
  'verified': True
})
```

### 3. Regular Audits
```bash
# Run weekly
/agent issues
```

## Future Agents

When creating new agents:

1. **Use the agent manager:**
```python
from agent_manager import get_agent_manager
manager = get_agent_manager()
agent = manager.create_agent("type", "Name")
```

2. **Builder code automatically added:**
- agent.json includes builder code
- Registered in builder code registry
- Verified automatically

3. **Sub-agents inherit:**
- Any agent creating sub-agents passes builder code
- Inheritance chain maintained
- Verification at each level

## Conclusion

Builder Code `bc_26ulyc23` is **hardwired** into the Hermes agent system. Every agent, transaction, and sub-agent automatically includes this builder code for attribution on Base L2.

**Status:** ✅ ACTIVE
**Enforcement:** MANDATORY
**Compliance:** 100%

All agents now and forever will have DrDeeks' builder code! 🎉
