# frozen_string_literal: true

# AI Orchestration Articles - Priority 3
# Creates comprehensive documentation for AI Orchestration features

puts "  🤖 Creating AI Orchestration articles..."

ai_cat = KnowledgeBase::Category.find_by!(slug: "ai-orchestration")
author = User.find_by!(email: "admin@powernode.org")

# Article 15: AI Orchestration Overview (Featured)
ai_overview_content = <<~MARKDOWN
# AI Orchestration Overview

Powernode's AI Orchestration platform enables you to integrate, manage, and deploy AI capabilities across your organization with enterprise-grade security and governance.

## What You'll Learn

- Core AI capabilities in Powernode
- Key concepts: Providers, Agents, Workflows, MCP
- Common use cases and applications
- Getting started with AI features
- Governance and cost management

## Platform Capabilities

### Multi-Provider Support

Connect to leading AI providers:

| Provider | Models | Best For |
|----------|--------|----------|
| **OpenAI** | GPT-4o, GPT-4, GPT-3.5 | General purpose, coding |
| **Anthropic** | Claude 3.5 Sonnet, Claude 3 Opus | Analysis, safety-critical |
| **xAI** | Grok | Real-time information |
| **Ollama** | Llama, Mistral, CodeLlama | Self-hosted, privacy |

### AI Agents

Deploy intelligent agents for automated tasks:

- **Customer Support** - Handle inquiries and escalations
- **Content Generation** - Create marketing copy and docs
- **Data Analysis** - Process and summarize datasets
- **Code Review** - Automated PR analysis
- **Research** - Information gathering and synthesis

### Workflow Automation

Build complex AI pipelines with visual tools:

```yaml
Workflow Example: Customer Feedback Analysis
  Trigger: New feedback received
  Steps:
    1. Sentiment Analysis (Claude)
    2. Topic Classification (GPT-4)
    3. Priority Scoring (Rules)
    4. Route to Team (Conditional)
    5. Generate Response Draft (Claude)
```

### Model Context Protocol (MCP)

Extend agent capabilities with external tools:

- Database queries
- API integrations
- File system access
- Web browsing
- Custom tools

## Key Concepts

### Providers

AI Providers are the underlying services that power your agents:

```yaml
Provider Configuration:
  Name: OpenAI Production
  Type: openai
  API Key: sk-... (encrypted)
  Models:
    - gpt-4o
    - gpt-4-turbo
    - gpt-3.5-turbo
  Rate Limits:
    requests_per_minute: 500
    tokens_per_minute: 100000
  Fallback: claude-3-sonnet
```

### Agents

Agents are AI-powered assistants with specific roles:

```yaml
Agent Configuration:
  Name: Support Agent
  Description: Handles customer support inquiries
  Provider: openai-production
  Model: gpt-4o
  System Prompt: |
    You are a helpful customer support agent for Powernode.
    Be professional, empathetic, and solution-oriented.
    Always verify customer identity before sharing account details.
  Temperature: 0.7
  Max Tokens: 2000
  Tools:
    - customer_lookup
    - ticket_creation
    - knowledge_base_search
```

### Workflows

Workflows orchestrate multiple AI operations:

```yaml
Workflow Configuration:
  Name: Content Pipeline
  Trigger: manual
  Nodes:
    - id: research
      type: agent
      agent: research-agent
      input: "Research topic: {{input.topic}}"

    - id: outline
      type: agent
      agent: writer-agent
      input: "Create outline from: {{research.output}}"

    - id: review
      type: approval
      approvers: [content-team]

    - id: publish
      type: action
      condition: "{{review.approved}}"
      action: publish_to_cms
```

### Contexts

Contexts provide agents with relevant information:

```yaml
Context Configuration:
  Name: Product Documentation
  Type: document
  Sources:
    - path: /docs/api/**/*.md
    - url: https://docs.powernode.org/api
  Refresh: daily
  Embedding Model: text-embedding-3-large
  Chunk Size: 1000
  Overlap: 200
```

## Use Cases

### Customer Support Automation

Automate first-level support with AI:

**Capabilities:**
- Answer common questions instantly
- Classify and route complex issues
- Generate response drafts for agents
- Summarize ticket history

**Results:**
- 40% reduction in response time
- 60% of inquiries handled automatically
- Improved customer satisfaction

### Content Generation

Scale content creation with AI assistance:

**Capabilities:**
- Generate blog posts and articles
- Create product descriptions
- Write documentation
- Translate content

**Workflow Example:**
```
Brief → Research → Draft → Review → Edit → Publish
  ↓        ↓         ↓       ↓        ↓        ↓
Human    Agent    Agent   Human   Agent   Automated
```

### Data Analysis

Extract insights from large datasets:

**Capabilities:**
- Summarize reports and documents
- Identify trends and patterns
- Generate visualizations
- Create executive summaries

### Code Review

Automate code quality checks:

**Capabilities:**
- Review pull requests
- Identify security issues
- Suggest improvements
- Check documentation

## Getting Started

### Step 1: Configure Provider

1. Navigate to **AI > Providers**
2. Click **Add Provider**
3. Select provider type (OpenAI, Anthropic, etc.)
4. Enter API credentials
5. Configure rate limits
6. Test connection

### Step 2: Create Agent

1. Navigate to **AI > Agents**
2. Click **Create Agent**
3. Configure:
   - Name and description
   - Provider and model
   - System prompt
   - Parameters (temperature, tokens)
4. Add tools (optional)
5. Test in playground

### Step 3: Build Workflow (Optional)

1. Navigate to **AI > Workflows**
2. Click **Create Workflow**
3. Add trigger node
4. Connect agent and action nodes
5. Configure conditions
6. Test and deploy

## AI Dashboard

### Quick Actions

- **Chat with Agent** - Test agents interactively
- **Run Workflow** - Execute workflows manually
- **View Analytics** - Monitor usage and costs
- **Manage Contexts** - Update knowledge bases

### Key Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| Response Time | Average AI response latency | < 2s |
| Success Rate | Successful completions | > 99% |
| Cost per Request | Average cost per API call | Monitor |
| Token Usage | Daily token consumption | Budget |

## Governance and Safety

### Access Control

Control who can use AI features:

```yaml
Permission Matrix:
  ai.providers.manage: Admin only
  ai.agents.create: AI Team, Developers
  ai.agents.use: All authenticated users
  ai.workflows.execute: Workflow owners
  ai.analytics.view: Managers, AI Team
```

### Content Filtering

Configure safety guardrails:

- Input sanitization
- Output filtering
- PII detection
- Topic restrictions
- Prompt injection protection

### Audit Logging

Track all AI operations:

```yaml
Audit Log Entry:
  Timestamp: 2024-01-15T10:30:00Z
  User: jane@company.com
  Agent: support-agent
  Model: gpt-4o
  Tokens: 1,250
  Cost: $0.025
  Duration: 1.8s
  Status: success
```

## Cost Management

### Token Tracking

Monitor usage across providers:

```yaml
Monthly Usage Summary:
  OpenAI:
    GPT-4o: 2,500,000 tokens ($50.00)
    GPT-4: 500,000 tokens ($30.00)
    GPT-3.5: 5,000,000 tokens ($7.50)

  Anthropic:
    Claude 3.5 Sonnet: 1,000,000 tokens ($15.00)

  Total: $102.50
```

### Budget Alerts

Set spending limits:

- Daily budget caps
- Per-user limits
- Per-agent limits
- Automatic throttling

### Optimization Tips

1. **Choose Appropriate Models**
   - Use GPT-3.5/Claude Haiku for simple tasks
   - Reserve GPT-4/Opus for complex reasoning

2. **Optimize Prompts**
   - Be concise and specific
   - Use system prompts effectively
   - Cache common responses

3. **Implement Caching**
   - Cache identical requests
   - Use semantic caching for similar queries

## Best Practices

### Prompt Engineering

1. **Be Specific**
   ```
   ❌ "Summarize this"
   ✅ "Summarize this customer feedback in 3 bullet points,
       focusing on product issues and suggested improvements"
   ```

2. **Provide Context**
   ```
   ✅ "You are a senior software engineer reviewing code.
       Focus on security, performance, and maintainability.
       Be constructive and explain your suggestions."
   ```

3. **Set Expectations**
   ```
   ✅ "Respond in JSON format with fields:
       sentiment (positive/negative/neutral),
       topics (array of strings),
       summary (max 100 words)"
   ```

### Agent Design

1. **Single Responsibility**
   - Each agent should have one clear purpose
   - Combine agents in workflows for complex tasks

2. **Appropriate Model Selection**
   - Match model capability to task complexity
   - Consider latency vs. quality tradeoffs

3. **Robust Error Handling**
   - Configure fallback providers
   - Handle rate limits gracefully
   - Log failures for analysis

## Next Steps

Explore detailed guides:

1. [Configuring AI Providers](/kb/configuring-ai-providers) - Provider setup
2. [Creating and Managing AI Agents](/kb/creating-managing-ai-agents) - Agent development
3. [Building AI Workflows](/kb/building-ai-workflows) - Workflow automation
4. [MCP Servers and Context Management](/kb/mcp-servers-context-management) - Tool integration
5. [Agent Teams and Multi-Agent Orchestration](/kb/agent-teams-multi-agent) - Team coordination

---

Questions about AI features? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "ai-orchestration-overview") do |article|
  article.title = "AI Orchestration Overview"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Comprehensive introduction to Powernode's AI capabilities including providers, agents, workflows, and governance for enterprise AI deployment."
  article.content = ai_overview_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ AI Orchestration Overview"

# Article 16: Configuring AI Providers
ai_providers_content = <<~MARKDOWN
# Configuring AI Providers

Connect and manage AI service providers in Powernode to power your agents and workflows with leading language models.

## Supported Providers

### OpenAI

Industry-leading GPT models for general-purpose AI tasks.

**Available Models:**
| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| gpt-4o | 128K | Multimodal, complex reasoning | $$ |
| gpt-4-turbo | 128K | Extended context tasks | $$$ |
| gpt-4 | 8K | High-quality output | $$$$ |
| gpt-3.5-turbo | 16K | Fast, cost-effective | $ |

**Configuration:**
```yaml
Provider Setup:
  Name: OpenAI Production
  Type: openai
  API Key: sk-... (from platform.openai.com)
  Organization ID: org-... (optional)
  Base URL: https://api.openai.com/v1 (default)

Settings:
  Default Model: gpt-4o
  Max Retries: 3
  Timeout: 60s
  Rate Limit:
    requests_per_minute: 500
    tokens_per_minute: 100000
```

### Anthropic Claude

Safety-focused AI with excellent analysis and writing capabilities.

**Available Models:**
| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| claude-3-5-sonnet | 200K | Balanced performance | $$ |
| claude-3-opus | 200K | Most capable | $$$$ |
| claude-3-sonnet | 200K | Good balance | $$ |
| claude-3-haiku | 200K | Fast, affordable | $ |

**Configuration:**
```yaml
Provider Setup:
  Name: Anthropic Production
  Type: anthropic
  API Key: sk-ant-... (from console.anthropic.com)
  Base URL: https://api.anthropic.com (default)

Settings:
  Default Model: claude-3-5-sonnet-20241022
  Max Retries: 3
  Timeout: 120s
```

### xAI Grok

Real-time information access with distinctive capabilities.

**Available Models:**
| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| grok-2 | 128K | Latest capabilities | $$$ |
| grok-2-mini | 128K | Faster, lighter | $$ |

**Configuration:**
```yaml
Provider Setup:
  Name: xAI Grok
  Type: xai
  API Key: xai-... (from x.ai)

Settings:
  Default Model: grok-2
  Max Retries: 3
```

### Ollama (Self-Hosted)

Run open-source models locally for privacy and cost control.

**Popular Models:**
| Model | Size | Best For |
|-------|------|----------|
| llama3.1 | 8B-70B | General purpose |
| codellama | 7B-34B | Code generation |
| mistral | 7B | Fast inference |
| mixtral | 8x7B | MoE architecture |

**Configuration:**
```yaml
Provider Setup:
  Name: Local Ollama
  Type: ollama
  Base URL: http://localhost:11434

Settings:
  Default Model: llama3.1:8b
  Pull Models on Start: true
  Available Models:
    - llama3.1:8b
    - llama3.1:70b
    - codellama:13b
```

## Adding a Provider

### Via Dashboard

1. Navigate to **AI > Providers**
2. Click **Add Provider**
3. Select provider type
4. Enter configuration:
   - Name (descriptive identifier)
   - API credentials
   - Default model
   - Rate limits
5. Click **Test Connection**
6. Save configuration

### Via API

```bash
curl -X POST https://api.powernode.org/api/v1/ai/providers \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "name": "OpenAI Production",
    "provider_type": "openai",
    "api_key": "sk-...",
    "config": {
      "default_model": "gpt-4o",
      "organization_id": "org-...",
      "rate_limit": {
        "requests_per_minute": 500,
        "tokens_per_minute": 100000
      }
    }
  }'
```

## Provider Settings

### Rate Limiting

Configure limits to prevent API quota exhaustion:

```yaml
Rate Limit Configuration:
  Global Limits:
    requests_per_minute: 1000
    tokens_per_minute: 500000
    requests_per_day: 50000

  Per-User Limits:
    requests_per_minute: 60
    tokens_per_minute: 50000

  Per-Agent Limits:
    support-agent:
      requests_per_minute: 200
    research-agent:
      requests_per_minute: 50

  Throttling Behavior:
    type: queue  # or 'reject'
    queue_timeout: 30s
```

### Fallback Configuration

Set up automatic failover:

```yaml
Fallback Chain:
  Primary: openai-production (gpt-4o)
  Fallbacks:
    1. anthropic-production (claude-3-5-sonnet)
    2. openai-backup (gpt-4-turbo)
    3. ollama-local (llama3.1:70b)

  Trigger Conditions:
    - Rate limit exceeded
    - API timeout (> 30s)
    - Error rate > 5%
    - Provider unavailable
```

### Cost Tracking

Monitor spending per provider:

```yaml
Cost Configuration:
  Budget Alerts:
    daily: $50
    weekly: $200
    monthly: $500

  Alert Recipients:
    - admin@company.com
    - billing@company.com

  Actions on Budget Exceeded:
    soft_limit: Alert only
    hard_limit: Switch to fallback
    emergency: Disable non-critical agents
```

## Testing Providers

### Connection Test

Verify provider connectivity:

```bash
curl -X POST https://api.powernode.org/api/v1/ai/providers/{id}/test \\
  -H "Authorization: Bearer YOUR_API_KEY"

# Response:
{
  "status": "success",
  "latency_ms": 245,
  "model_available": true,
  "rate_limit_status": {
    "remaining_requests": 487,
    "remaining_tokens": 95000,
    "reset_at": "2024-01-15T11:00:00Z"
  }
}
```

### Playground Testing

Test models interactively:

1. Navigate to **AI > Playground**
2. Select provider and model
3. Enter test prompt
4. Adjust parameters (temperature, max_tokens)
5. Send request
6. Review response and metrics

## Security Best Practices

### API Key Management

1. **Use Environment Variables**
   - Never hardcode API keys
   - Rotate keys quarterly
   - Use separate keys per environment

2. **Access Control**
   - Limit who can view/edit providers
   - Use permission-based access
   - Audit key usage

3. **Key Rotation**
   ```bash
   # Update API key via API
   curl -X PATCH https://api.powernode.org/api/v1/ai/providers/{id} \\
     -H "Authorization: Bearer YOUR_API_KEY" \\
     -d '{"api_key": "new-sk-..."}'
   ```

### Network Security

- Use HTTPS for all API calls
- Configure IP allowlists where supported
- Monitor for unusual traffic patterns

## Troubleshooting

### Common Issues

**Authentication Failed:**
- Verify API key is correct
- Check key hasn't expired
- Confirm organization ID (OpenAI)
- Verify account is active

**Rate Limit Exceeded:**
- Implement request queuing
- Distribute load across providers
- Upgrade API tier
- Optimize token usage

**Timeout Errors:**
- Increase timeout settings
- Reduce max_tokens for faster responses
- Check network connectivity
- Monitor provider status page

**Model Not Available:**
- Verify model name is correct
- Check model access in provider dashboard
- Confirm regional availability
- Update to latest model version

### Provider Status

Monitor provider health:

- [OpenAI Status](https://status.openai.com)
- [Anthropic Status](https://status.anthropic.com)
- [xAI Status](https://status.x.ai)

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [Building AI Workflows](/kb/building-ai-workflows)

---

Need help with provider configuration? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "configuring-ai-providers") do |article|
  article.title = "Configuring AI Providers"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Complete guide to connecting OpenAI, Anthropic Claude, xAI Grok, and Ollama providers with API configuration, rate limiting, and fallback settings."
  article.content = ai_providers_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Configuring AI Providers"

# Article 17: Creating and Managing AI Agents
ai_agents_content = <<~MARKDOWN
# Creating and Managing AI Agents

Build intelligent AI agents that automate tasks, assist users, and integrate with your business processes.

## What Are AI Agents?

AI Agents are configured AI assistants with:
- **Specific roles** - Defined purpose and expertise
- **Custom prompts** - Tailored behavior and responses
- **Tool access** - Ability to perform actions
- **Memory** - Context retention across conversations

## Creating Your First Agent

### Step 1: Basic Configuration

1. Navigate to **AI > Agents**
2. Click **Create Agent**
3. Enter basic details:

```yaml
Basic Configuration:
  Name: Customer Support Agent
  Description: Handles customer inquiries and support tickets
  Icon: 🎧 (optional)
  Tags: [support, customer-facing, production]
```

### Step 2: Model Selection

Choose the AI model:

```yaml
Model Configuration:
  Provider: openai-production
  Model: gpt-4o
  Temperature: 0.7  # 0=deterministic, 1=creative
  Max Tokens: 2000
  Top P: 1.0
  Frequency Penalty: 0
  Presence Penalty: 0
```

**Temperature Guidelines:**
| Use Case | Temperature |
|----------|-------------|
| Code generation | 0.0-0.3 |
| Customer support | 0.5-0.7 |
| Creative writing | 0.8-1.0 |
| Data extraction | 0.0 |

### Step 3: System Prompt

Define agent behavior:

```markdown
# Customer Support Agent

You are a helpful customer support agent for Powernode, a subscription management platform.

## Your Role
- Answer questions about Powernode features and billing
- Help troubleshoot common issues
- Escalate complex problems to human agents
- Maintain a professional, empathetic tone

## Guidelines
- Always verify customer identity before sharing account details
- Never share internal system information
- If unsure, say so and offer to escalate
- Keep responses concise but complete

## Available Actions
- Look up customer accounts
- Check subscription status
- Create support tickets
- Search knowledge base

## Response Format
- Use clear, simple language
- Break complex answers into steps
- Include relevant links when helpful
- End with a question to confirm understanding
```

### Step 4: Tool Configuration

Enable agent capabilities:

```yaml
Tools:
  - name: customer_lookup
    description: Look up customer by email or ID
    parameters:
      email: string (optional)
      customer_id: string (optional)

  - name: subscription_status
    description: Check subscription details
    parameters:
      customer_id: string (required)

  - name: create_ticket
    description: Create support ticket
    parameters:
      customer_id: string (required)
      subject: string (required)
      description: string (required)
      priority: enum [low, medium, high]

  - name: kb_search
    description: Search knowledge base
    parameters:
      query: string (required)
      limit: number (default: 5)
```

### Step 5: Testing

Test in the playground before deployment:

1. Click **Test Agent**
2. Enter sample conversations
3. Verify tool usage
4. Check response quality
5. Adjust as needed

## Agent Configuration Options

### Memory and Context

Configure how agents remember conversations:

```yaml
Memory Configuration:
  Type: conversation  # or 'persistent', 'none'
  Max History: 20 messages
  Summarize After: 10 messages
  Context Window: 8000 tokens

  Persistent Memory:
    Enabled: true
    Storage: vector_database
    Retention: 30 days
```

### Input/Output Processing

Control data handling:

```yaml
Processing:
  Input:
    Max Length: 10000 characters
    Sanitize HTML: true
    Remove PII: false
    Language Detection: true

  Output:
    Format: markdown
    Max Length: 5000 characters
    Filter Profanity: true
    Add Citations: true
```

### Rate Limiting

Prevent abuse:

```yaml
Rate Limits:
  Per User:
    requests_per_minute: 10
    requests_per_hour: 100
    tokens_per_day: 50000

  Global:
    concurrent_requests: 50
    requests_per_minute: 500
```

## Agent Types

### Conversational Agents

For interactive chat interfaces:

```yaml
Agent: Chat Assistant
  Type: conversational
  Features:
    - Multi-turn conversations
    - Context awareness
    - Clarifying questions
    - Handoff to humans
```

### Task Agents

For specific automated tasks:

```yaml
Agent: Data Processor
  Type: task
  Features:
    - Single-purpose execution
    - Structured input/output
    - Batch processing
    - Scheduled runs
```

### Autonomous Agents

For complex, multi-step operations:

```yaml
Agent: Research Assistant
  Type: autonomous
  Features:
    - Goal-oriented behavior
    - Tool chaining
    - Decision making
    - Progress reporting
```

## Advanced Features

### Agent Versioning

Track changes over time:

```yaml
Version History:
  v3 (current):
    Created: 2024-01-15
    Changes: Updated system prompt, added new tools
    Performance: 94% satisfaction

  v2:
    Created: 2024-01-01
    Changes: Added memory feature
    Performance: 89% satisfaction

  v1:
    Created: 2023-12-15
    Changes: Initial release
    Performance: 82% satisfaction
```

### A/B Testing

Compare agent configurations:

```yaml
A/B Test Configuration:
  Name: Temperature Comparison
  Duration: 7 days
  Variants:
    A (Control):
      Temperature: 0.7
      Traffic: 50%
    B (Test):
      Temperature: 0.5
      Traffic: 50%

  Metrics:
    - User satisfaction
    - Task completion rate
    - Response relevance
```

### Performance Analytics

Monitor agent effectiveness:

```yaml
Agent Metrics:
  Usage:
    Total Conversations: 5,234
    Messages Processed: 42,891
    Avg Response Time: 1.8s

  Quality:
    User Satisfaction: 4.2/5
    Task Completion: 87%
    Escalation Rate: 12%

  Costs:
    Total Tokens: 15,234,567
    Total Cost: $152.34
    Cost per Conversation: $0.029
```

## Agent Management

### Deployment

Control agent availability:

```yaml
Deployment Settings:
  Status: active  # or 'inactive', 'testing'
  Environments:
    - production
    - staging

  Availability:
    Schedule: 24/7
    # Or specific hours:
    # schedule:
    #   weekdays: 9:00-18:00
    #   weekends: 10:00-16:00
```

### Access Control

Manage who can use agents:

```yaml
Access Control:
  Users:
    - support-team (full access)
    - sales-team (read-only)

  API Access:
    Enabled: true
    Rate Limit: 100/hour
    IP Whitelist:
      - 10.0.0.0/8
```

### Monitoring

Set up alerts and monitoring:

```yaml
Monitoring:
  Alerts:
    - condition: error_rate > 5%
      action: notify_team
    - condition: latency > 5s
      action: slack_alert
    - condition: cost > $10/hour
      action: email_admin

  Logging:
    Level: info
    Retention: 30 days
    Include:
      - Conversations
      - Tool calls
      - Errors
```

## Best Practices

### System Prompt Design

1. **Be Specific About Role**
   ```
   You are a [role] for [company/product].
   Your primary responsibility is [task].
   ```

2. **Define Boundaries**
   ```
   You should:
   - [Allowed actions]

   You should NOT:
   - [Prohibited actions]
   ```

3. **Provide Examples**
   ```
   Example interaction:
   User: [Sample question]
   You: [Expected response]
   ```

### Tool Design

1. **Clear Descriptions**
   - Explain when to use each tool
   - Document parameters clearly
   - Provide examples

2. **Error Handling**
   - Return meaningful error messages
   - Include retry logic
   - Log failures

3. **Security**
   - Validate inputs
   - Check permissions
   - Audit tool usage

### Testing

1. **Unit Tests**
   - Test individual prompts
   - Verify tool execution
   - Check edge cases

2. **Integration Tests**
   - Full conversation flows
   - Multi-tool scenarios
   - Error recovery

3. **User Testing**
   - Beta testing with real users
   - Gather feedback
   - Iterate on design

## Troubleshooting

### Common Issues

**Agent Not Responding:**
- Check provider connectivity
- Verify model availability
- Review rate limits
- Check agent status

**Poor Response Quality:**
- Review system prompt
- Adjust temperature
- Check context length
- Verify tool responses

**Tool Failures:**
- Test tool endpoints
- Check permissions
- Review error logs
- Verify parameters

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Configuring AI Providers](/kb/configuring-ai-providers)
- [Building AI Workflows](/kb/building-ai-workflows)
- [MCP Servers and Context Management](/kb/mcp-servers-context-management)

---

Need help creating agents? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "creating-managing-ai-agents") do |article|
  article.title = "Creating and Managing AI Agents"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Step-by-step guide to building AI agents with custom prompts, tool integration, memory management, versioning, and performance monitoring."
  article.content = ai_agents_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Creating and Managing AI Agents"

# Article 18: Building AI Workflows
ai_workflows_content = <<~MARKDOWN
# Building AI Workflows

Create automated AI pipelines that combine multiple agents, conditions, and actions to handle complex business processes.

## Workflow Concepts

### What is an AI Workflow?

A workflow is a directed graph of nodes that processes data through AI agents, conditions, and actions:

```
Trigger → Agent → Condition → Agent → Action
   ↓         ↓          ↓         ↓        ↓
Event    Process    Decision   Process   Output
```

### Node Types

| Type | Purpose | Example |
|------|---------|---------|
| **Trigger** | Start workflow | Webhook, schedule, manual |
| **Agent** | AI processing | Analyze, generate, classify |
| **Condition** | Decision point | If/else, switch |
| **Action** | External effect | API call, email, database |
| **Loop** | Iteration | For each item |
| **Parallel** | Concurrent execution | Multiple agents |

## Creating Workflows

### Visual Builder

1. Navigate to **AI > Workflows**
2. Click **Create Workflow**
3. Drag nodes from palette
4. Connect nodes with edges
5. Configure each node
6. Test and deploy

### YAML Configuration

```yaml
name: Customer Feedback Pipeline
description: Analyze and route customer feedback
version: 1.0.0

trigger:
  type: webhook
  path: /feedback
  method: POST

nodes:
  - id: analyze_sentiment
    type: agent
    agent: sentiment-analyzer
    input:
      text: "{{trigger.body.feedback}}"

  - id: classify_topic
    type: agent
    agent: topic-classifier
    input:
      text: "{{trigger.body.feedback}}"

  - id: route_feedback
    type: condition
    conditions:
      - if: "{{analyze_sentiment.output.sentiment}} == 'negative'"
        then: urgent_response
      - if: "{{classify_topic.output.topic}} == 'billing'"
        then: billing_team
      - else: general_queue

  - id: urgent_response
    type: agent
    agent: response-generator
    input:
      context: "Urgent negative feedback"
      feedback: "{{trigger.body.feedback}}"

  - id: notify_team
    type: action
    action: slack_message
    config:
      channel: "#support-urgent"
      message: "Urgent feedback: {{urgent_response.output}}"
```

## Trigger Types

### Webhook Triggers

Receive external events:

```yaml
trigger:
  type: webhook
  path: /api/workflow/feedback
  method: POST
  authentication:
    type: api_key
    header: X-API-Key
  validation:
    schema:
      type: object
      required: [feedback, customer_id]
      properties:
        feedback:
          type: string
        customer_id:
          type: string
```

### Schedule Triggers

Run on a schedule:

```yaml
trigger:
  type: schedule
  cron: "0 9 * * MON"  # Every Monday at 9 AM
  timezone: America/New_York
```

### Event Triggers

React to system events:

```yaml
trigger:
  type: event
  events:
    - subscription.created
    - subscription.cancelled
    - invoice.payment_failed
```

### Manual Triggers

Start workflows on demand:

```yaml
trigger:
  type: manual
  parameters:
    - name: customer_id
      type: string
      required: true
    - name: action
      type: enum
      values: [analyze, report, escalate]
```

## Agent Nodes

### Basic Agent Node

```yaml
- id: summarize
  type: agent
  agent: summarizer-agent  # Reference existing agent
  input:
    text: "{{previous_node.output}}"
    max_length: 200
  output:
    variable: summary
```

### Inline Agent Configuration

```yaml
- id: custom_analysis
  type: agent
  config:
    provider: openai-production
    model: gpt-4o
    temperature: 0.3
    system_prompt: |
      Analyze the following data and extract key metrics.
      Return results as JSON.
  input:
    data: "{{trigger.body.data}}"
```

### Agent with Tools

```yaml
- id: research
  type: agent
  agent: research-agent
  tools:
    - web_search
    - document_retrieval
    - calculator
  input:
    query: "{{trigger.body.question}}"
  timeout: 60s
```

## Condition Nodes

### If/Else Conditions

```yaml
- id: check_priority
  type: condition
  conditions:
    - if: "{{analyze.output.priority}} == 'high'"
      then: urgent_path
    - if: "{{analyze.output.priority}} == 'medium'"
      then: normal_path
    - else: low_priority_path
```

### Switch Conditions

```yaml
- id: route_by_category
  type: switch
  expression: "{{classify.output.category}}"
  cases:
    billing: billing_handler
    technical: tech_support
    sales: sales_team
    default: general_queue
```

### Complex Conditions

```yaml
- id: complex_routing
  type: condition
  conditions:
    - if: >
        {{sentiment.score}} < -0.5 AND
        {{customer.tier}} == 'enterprise' AND
        {{history.open_tickets}} > 2
      then: executive_escalation
    - if: "{{sentiment.score}} < -0.5"
      then: priority_support
```

## Action Nodes

### API Actions

```yaml
- id: update_crm
  type: action
  action: http_request
  config:
    method: POST
    url: "https://api.crm.example/contacts/{{customer_id}}"
    headers:
      Authorization: "Bearer {{secrets.CRM_TOKEN}}"
    body:
      sentiment: "{{analyze.output.sentiment}}"
      last_feedback: "{{trigger.body.feedback}}"
```

### Database Actions

```yaml
- id: save_analysis
  type: action
  action: database
  config:
    operation: insert
    table: feedback_analysis
    data:
      customer_id: "{{trigger.body.customer_id}}"
      sentiment: "{{analyze.output.sentiment}}"
      topics: "{{classify.output.topics}}"
      created_at: "{{now}}"
```

### Notification Actions

```yaml
- id: send_alert
  type: action
  action: notification
  config:
    channels:
      - type: slack
        channel: "#alerts"
      - type: email
        recipients:
          - "{{customer.account_manager}}"
    message: |
      Urgent feedback received from {{customer.name}}

      Sentiment: {{analyze.output.sentiment}}
      Topics: {{classify.output.topics}}

      Original feedback:
      {{trigger.body.feedback}}
```

## Advanced Patterns

### Parallel Execution

Process multiple items concurrently:

```yaml
- id: parallel_analysis
  type: parallel
  branches:
    - id: sentiment
      type: agent
      agent: sentiment-analyzer
      input:
        text: "{{trigger.body.text}}"

    - id: entities
      type: agent
      agent: entity-extractor
      input:
        text: "{{trigger.body.text}}"

    - id: keywords
      type: agent
      agent: keyword-extractor
      input:
        text: "{{trigger.body.text}}"

- id: combine_results
  type: action
  wait_for: [sentiment, entities, keywords]
  action: merge
  output:
    analysis:
      sentiment: "{{sentiment.output}}"
      entities: "{{entities.output}}"
      keywords: "{{keywords.output}}"
```

### Loop Processing

Iterate over collections:

```yaml
- id: process_items
  type: loop
  collection: "{{trigger.body.items}}"
  item_variable: item
  nodes:
    - id: analyze_item
      type: agent
      agent: item-analyzer
      input:
        item: "{{item}}"

    - id: store_result
      type: action
      action: database
      config:
        operation: insert
        table: analysis_results
        data:
          item_id: "{{item.id}}"
          analysis: "{{analyze_item.output}}"
```

### Error Handling

Handle failures gracefully:

```yaml
- id: risky_operation
  type: agent
  agent: external-api-agent
  error_handling:
    on_error:
      - type: retry
        max_attempts: 3
        backoff: exponential
      - type: fallback
        node: fallback_handler
      - type: notify
        channel: "#errors"

- id: fallback_handler
  type: agent
  agent: simple-agent
  input:
    context: "Fallback due to error"
```

## Variables and Data Flow

### Variable References

```yaml
# Trigger data
"{{trigger.body.field}}"
"{{trigger.headers.X-Custom-Header}}"
"{{trigger.params.id}}"

# Node outputs
"{{node_id.output}}"
"{{node_id.output.nested.field}}"
"{{node_id.output[0].field}}"

# System variables
"{{now}}"  # Current timestamp
"{{workflow.id}}"
"{{execution.id}}"

# Secrets
"{{secrets.API_KEY}}"
```

### Data Transformation

```yaml
- id: transform
  type: transform
  operations:
    - set: combined_text
      value: "{{item.title}}: {{item.description}}"

    - set: formatted_date
      value: "{{format_date(trigger.body.date, 'YYYY-MM-DD')}}"

    - set: score_normalized
      value: "{{(analyze.output.score + 1) / 2 * 100}}"
```

## Testing and Debugging

### Test Execution

```yaml
Test Configuration:
  Mode: debug
  Input:
    feedback: "The product is great but shipping was slow"
    customer_id: "test_customer_123"

  Breakpoints:
    - analyze_sentiment
    - route_feedback

  Assertions:
    - node: analyze_sentiment
      expect:
        sentiment: mixed
    - node: route_feedback
      expect:
        path: normal_path
```

### Execution Logs

View detailed execution history:

```yaml
Execution Log:
  ID: exec_01HQ7EXAMPLE
  Status: completed
  Duration: 4.2s

  Steps:
    1. trigger (0ms)
       Input: {feedback: "...", customer_id: "..."}

    2. analyze_sentiment (1.8s)
       Agent: sentiment-analyzer
       Tokens: 450
       Output: {sentiment: "mixed", score: 0.2}

    3. classify_topic (1.2s)
       Agent: topic-classifier
       Tokens: 320
       Output: {topic: "shipping", confidence: 0.89}

    4. route_feedback (5ms)
       Decision: normal_path
       Reason: sentiment != negative

    5. notify_team (1.2s)
       Action: slack_message
       Status: delivered
```

## Deployment

### Version Management

```yaml
Deployment:
  Current Version: 2.1.0
  Status: active

  Versions:
    2.1.0: Active (production)
    2.0.0: Available (rollback ready)
    1.5.0: Archived

  Rollback:
    Auto-rollback: enabled
    Trigger: error_rate > 10%
    Target: previous_stable
```

### Environment Configuration

```yaml
Environments:
  production:
    trigger_url: https://api.powernode.org/workflows/prod/feedback
    variables:
      LOG_LEVEL: info
      TIMEOUT: 30s

  staging:
    trigger_url: https://api.powernode.org/workflows/staging/feedback
    variables:
      LOG_LEVEL: debug
      TIMEOUT: 60s
```

## Best Practices

1. **Start Simple**
   - Build and test incrementally
   - Add complexity gradually
   - Validate at each step

2. **Handle Errors**
   - Implement retry logic
   - Define fallback paths
   - Log failures for analysis

3. **Optimize Performance**
   - Use parallel execution where possible
   - Cache repeated operations
   - Set appropriate timeouts

4. **Monitor and Iterate**
   - Track execution metrics
   - Review error rates
   - Gather user feedback

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [MCP Servers and Context Management](/kb/mcp-servers-context-management)

---

Need help building workflows? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "building-ai-workflows") do |article|
  article.title = "Building AI Workflows"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Complete guide to creating automated AI pipelines with triggers, agent nodes, conditions, actions, and advanced patterns like parallel execution."
  article.content = ai_workflows_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Building AI Workflows"

# Article 19: MCP Servers and Context Management
mcp_content = <<~MARKDOWN
# MCP Servers and Context Management

Extend AI agent capabilities with Model Context Protocol (MCP) servers and manage knowledge bases for contextual awareness.

## Understanding MCP

### What is MCP?

Model Context Protocol (MCP) is an open standard that allows AI models to interact with external tools and data sources:

- **Tools** - Functions agents can call (APIs, databases, etc.)
- **Resources** - Data sources agents can read
- **Prompts** - Pre-defined prompt templates

### MCP Architecture

```
Agent → MCP Client → MCP Server → External Service
  ↓         ↓            ↓              ↓
Request   Protocol    Handler      Database/API
```

## Adding MCP Servers

### Via Dashboard

1. Navigate to **AI > MCP Servers**
2. Click **Add Server**
3. Configure connection:

```yaml
MCP Server Configuration:
  Name: Database Tools
  Description: Query and update application database
  Transport:
    Type: stdio  # or 'http', 'websocket'
    Command: npx @mcp/database-server
    Args:
      - --connection-string
      - postgresql://...

  Authentication:
    Type: oauth2  # or 'api_key', 'none'
    Client ID: mcp_client_123
    Scopes: [read, write]
```

### Via API

```bash
curl -X POST https://api.powernode.org/api/v1/ai/mcp-servers \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "name": "Database Tools",
    "transport": {
      "type": "stdio",
      "command": "npx",
      "args": ["@mcp/database-server"]
    },
    "config": {
      "connection_string": "postgresql://..."
    }
  }'
```

## Available MCP Tools

### Database Tools

Query and modify databases:

```yaml
Tools:
  - name: db_query
    description: Execute read-only SQL query
    parameters:
      query: string
      params: array (optional)
    returns: array of records

  - name: db_insert
    description: Insert records into table
    parameters:
      table: string
      data: object
    returns: inserted record

  - name: db_update
    description: Update existing records
    parameters:
      table: string
      where: object
      data: object
    returns: updated count
```

### File System Tools

Access and manage files:

```yaml
Tools:
  - name: read_file
    description: Read file contents
    parameters:
      path: string
    returns: file content

  - name: write_file
    description: Write content to file
    parameters:
      path: string
      content: string
    returns: success boolean

  - name: list_directory
    description: List directory contents
    parameters:
      path: string
    returns: array of file info
```

### Web Tools

Interact with web services:

```yaml
Tools:
  - name: web_search
    description: Search the web
    parameters:
      query: string
      num_results: number (default: 10)
    returns: array of search results

  - name: fetch_url
    description: Fetch content from URL
    parameters:
      url: string
    returns: page content

  - name: http_request
    description: Make HTTP request
    parameters:
      method: string
      url: string
      headers: object
      body: object
    returns: response
```

### Custom Tools

Build your own MCP tools:

```typescript
// custom-mcp-server.ts
import { Server } from '@modelcontextprotocol/sdk/server';

const server = new Server({
  name: 'custom-tools',
  version: '1.0.0',
});

server.setRequestHandler('tools/list', async () => ({
  tools: [
    {
      name: 'calculate_shipping',
      description: 'Calculate shipping cost for order',
      inputSchema: {
        type: 'object',
        properties: {
          weight: { type: 'number' },
          destination: { type: 'string' },
          express: { type: 'boolean' },
        },
        required: ['weight', 'destination'],
      },
    },
  ],
}));

server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'calculate_shipping') {
    const { weight, destination, express } = request.params.arguments;
    const cost = calculateShippingCost(weight, destination, express);
    return { result: { cost, currency: 'USD' } };
  }
});

server.connect();
```

## Context Management

### What Are Contexts?

Contexts provide agents with relevant background information:

- **Documents** - Text files, PDFs, documentation
- **Databases** - Structured data queries
- **APIs** - Real-time external data
- **Memory** - Previous conversation history

### Creating Contexts

1. Navigate to **AI > Contexts**
2. Click **Create Context**
3. Configure data sources:

```yaml
Context Configuration:
  Name: Product Documentation
  Description: All product documentation and guides

  Sources:
    - type: files
      path: /docs/**/*.md
      watch: true  # Auto-update on changes

    - type: url
      urls:
        - https://docs.powernode.org/api
        - https://docs.powernode.org/guides
      refresh: daily

    - type: database
      query: |
        SELECT title, content, updated_at
        FROM knowledge_base_articles
        WHERE status = 'published'
      refresh: hourly

  Processing:
    Chunk Size: 1000 tokens
    Chunk Overlap: 200 tokens
    Embedding Model: text-embedding-3-large

  Storage:
    Type: vector_database
    Index: product_docs_v1
```

### Using Contexts with Agents

Attach contexts to agents:

```yaml
Agent Configuration:
  Name: Support Agent
  Contexts:
    - name: Product Documentation
      priority: high
      max_chunks: 10

    - name: FAQ Database
      priority: medium
      max_chunks: 5

  Retrieval:
    Strategy: hybrid  # semantic + keyword
    Rerank: true
    Min Relevance: 0.7
```

### Context Entries

Manually add context entries:

```yaml
Context Entry:
  Type: document
  Title: Refund Policy
  Content: |
    ## Refund Policy

    Customers may request a refund within 30 days of purchase.

    ### Eligible Refunds
    - Subscription not used
    - Technical issues preventing use
    - Billing errors

    ### Process
    1. Submit request via support ticket
    2. Provide order number
    3. Refund processed within 5 business days

  Metadata:
    category: billing
    last_updated: 2024-01-15
    priority: high
```

## RAG Integration

### Retrieval-Augmented Generation

Combine context retrieval with AI generation:

```yaml
RAG Pipeline:
  1. Query Analysis:
     - Extract key terms
     - Identify intent
     - Expand synonyms

  2. Retrieval:
     - Search vector database
     - Apply relevance threshold
     - Rerank results

  3. Context Assembly:
     - Select top chunks
     - Maintain coherence
     - Respect token limits

  4. Generation:
     - Include retrieved context
     - Generate response
     - Cite sources
```

### Configuration

```yaml
RAG Settings:
  Retrieval:
    Top K: 10
    Min Score: 0.7
    Rerank Model: cross-encoder-v1

  Context Window:
    Max Tokens: 4000
    Reserve for Response: 2000

  Generation:
    Include Citations: true
    Citation Format: "[Source: {title}]"
```

## OAuth for MCP Tools

### Configuring OAuth

For MCP servers requiring user authentication:

```yaml
MCP OAuth Configuration:
  Server: Google Drive Tools
  OAuth Provider: google

  Settings:
    Client ID: abc123.apps.googleusercontent.com
    Client Secret: (stored securely)
    Scopes:
      - https://www.googleapis.com/auth/drive.readonly
    Redirect URI: https://powernode.org/oauth/callback

  User Authorization:
    Required: true
    Prompt: "Connect your Google Drive to enable file access"
```

### User Authorization Flow

1. Agent requests tool requiring OAuth
2. User prompted to authorize
3. OAuth flow completes
4. Token stored securely
5. Tool becomes available

## Troubleshooting

### MCP Server Issues

**Server Not Connecting:**
```yaml
Checklist:
  - Verify command/path is correct
  - Check server logs for errors
  - Confirm network connectivity
  - Validate authentication credentials
  - Test server independently
```

**Tool Execution Failures:**
```yaml
Debugging:
  1. Enable debug logging
  2. Check tool parameters
  3. Verify permissions
  4. Review server logs
  5. Test tool in isolation
```

### Context Issues

**Poor Retrieval Quality:**
- Adjust chunk size and overlap
- Review embedding model selection
- Check relevance thresholds
- Verify source data quality

**Slow Retrieval:**
- Optimize vector index
- Reduce search scope
- Cache frequent queries
- Use approximate search

## Best Practices

### MCP Servers

1. **Security**
   - Use minimal permissions
   - Validate all inputs
   - Log tool usage
   - Rotate credentials

2. **Performance**
   - Implement caching
   - Set appropriate timeouts
   - Handle errors gracefully

3. **Monitoring**
   - Track tool usage
   - Monitor error rates
   - Alert on failures

### Context Management

1. **Data Quality**
   - Keep sources updated
   - Remove outdated content
   - Verify accuracy

2. **Organization**
   - Use meaningful categories
   - Add rich metadata
   - Maintain consistent formatting

3. **Optimization**
   - Right-size chunks
   - Balance coverage vs. relevance
   - Regular reindexing

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [Agent Teams and Multi-Agent Orchestration](/kb/agent-teams-multi-agent)

---

Need help with MCP or contexts? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "mcp-servers-context-management") do |article|
  article.title = "MCP Servers and Context Management"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Configure Model Context Protocol (MCP) servers for tool access, manage knowledge bases, and implement RAG for contextual AI responses."
  article.content = mcp_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ MCP Servers and Context Management"

# Article 20: Agent Teams and Multi-Agent Orchestration
agent_teams_content = <<~MARKDOWN
# Agent Teams and Multi-Agent Orchestration

Coordinate multiple AI agents to tackle complex tasks through collaboration, delegation, and specialized roles.

## Multi-Agent Concepts

### Why Multi-Agent?

Single agents have limitations:
- Context window constraints
- Specialized vs. general knowledge
- Complex task decomposition
- Quality through specialization

Multi-agent systems overcome these by:
- **Specialization** - Each agent excels at specific tasks
- **Collaboration** - Agents work together seamlessly
- **Scalability** - Parallel processing of subtasks
- **Robustness** - Redundancy and fallbacks

### Agent Team Patterns

```
                    ┌─────────────┐
                    │ Coordinator │
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ Research   │  │   Writer   │  │  Reviewer  │
    │   Agent    │  │   Agent    │  │   Agent    │
    └────────────┘  └────────────┘  └────────────┘
```

## Creating Agent Teams

### Team Configuration

```yaml
Team Configuration:
  Name: Content Creation Team
  Description: Collaborative team for content production

  Coordinator:
    Agent: project-manager
    Role: Orchestrates team activities

  Members:
    - agent: researcher
      role: Information gathering
      skills: [web_search, document_analysis]

    - agent: writer
      role: Content creation
      skills: [copywriting, technical_writing]

    - agent: editor
      role: Review and refinement
      skills: [grammar, style, fact_checking]

    - agent: seo-specialist
      role: Optimization
      skills: [keyword_research, meta_optimization]

  Communication:
    Pattern: hub_and_spoke  # or 'peer_to_peer', 'hierarchical'
    Shared Context: true
```

### Defining Agent Roles

Each team member has specific responsibilities:

```yaml
Agent: Researcher
  Role: Information Specialist
  Responsibilities:
    - Gather relevant information
    - Verify facts and sources
    - Summarize findings
    - Identify knowledge gaps

  System Prompt: |
    You are a research specialist on a content team.

    Your responsibilities:
    1. Search for accurate, up-to-date information
    2. Verify facts from multiple sources
    3. Organize findings clearly
    4. Flag uncertainties or contradictions

    When presenting research:
    - Include source citations
    - Note confidence levels
    - Highlight key insights

  Tools:
    - web_search
    - document_retrieval
    - fact_checker
```

### Communication Patterns

**Hub and Spoke:**
```
All communication through coordinator

Research ──► Coordinator ──► Writer
                  │
                  ▼
               Editor
```

**Peer to Peer:**
```
Direct agent-to-agent communication

Research ◄──► Writer
    │            │
    ▼            ▼
   Editor ◄──► SEO
```

**Hierarchical:**
```
Structured delegation chain

Lead Writer
    │
    ├── Research Lead
    │       ├── Researcher 1
    │       └── Researcher 2
    │
    └── Editor Lead
            ├── Copy Editor
            └── Fact Checker
```

## Team Workflows

### Sequential Handoff

Tasks flow through agents in order:

```yaml
Workflow: Blog Post Creation
  Steps:
    1. Coordinator:
       - Receive topic and requirements
       - Create task breakdown
       - Assign to researcher

    2. Researcher:
       - Gather information
       - Compile research brief
       - Hand off to writer

    3. Writer:
       - Create draft from research
       - Follow style guidelines
       - Hand off to editor

    4. Editor:
       - Review for clarity and accuracy
       - Suggest improvements
       - Hand off to SEO

    5. SEO Specialist:
       - Optimize for search
       - Add meta descriptions
       - Return to coordinator

    6. Coordinator:
       - Final review
       - Compile deliverable
       - Return to user
```

### Parallel Processing

Multiple agents work simultaneously:

```yaml
Workflow: Comprehensive Analysis

  Parallel Phase:
    - Research Agent: Market analysis
    - Data Agent: Financial data collection
    - Competitor Agent: Competitor review

  Synthesis Phase:
    - Analyst Agent: Combine findings
    - Writer Agent: Generate report

  Review Phase:
    - Reviewer Agent: Quality check
    - Editor Agent: Final polish
```

### Iterative Refinement

Agents collaborate through cycles:

```yaml
Workflow: Code Review Loop

  Loop:
    Max Iterations: 3
    Exit Condition: reviewer.approved == true

    Steps:
      1. Developer Agent:
         - Implement feature
         - Submit for review

      2. Reviewer Agent:
         - Analyze code
         - Provide feedback
         - Approve or request changes

      3. If not approved:
         - Developer receives feedback
         - Makes improvements
         - Resubmits
```

## Task Delegation

### Coordinator Responsibilities

The coordinator agent manages the team:

```yaml
Coordinator Agent: Project Manager

  Responsibilities:
    - Receive and interpret user requests
    - Break down complex tasks
    - Assign tasks to appropriate agents
    - Monitor progress
    - Handle escalations
    - Synthesize final output

  Decision Making:
    - Which agent handles each subtask?
    - Should tasks run in parallel or sequence?
    - Is quality acceptable?
    - When to escalate to user?

  System Prompt: |
    You are a project coordinator managing a team of AI agents.

    Team Members:
    - Researcher: Information gathering
    - Writer: Content creation
    - Editor: Quality review

    Your role:
    1. Understand user requirements
    2. Create actionable task list
    3. Delegate to appropriate agents
    4. Monitor quality and progress
    5. Synthesize final deliverable

    When delegating:
    - Be specific about expectations
    - Provide necessary context
    - Set clear success criteria
```

### Delegation Protocol

```yaml
Task Delegation Message:
  To: Writer Agent
  From: Coordinator
  Task: Create blog post introduction

  Context:
    Topic: "Getting Started with AI Agents"
    Target Audience: Technical managers
    Tone: Professional but accessible
    Length: 150-200 words

  Requirements:
    - Hook reader in first sentence
    - Establish relevance
    - Preview main points
    - End with transition

  Research Summary:
    (Attached from Researcher)

  Deadline: 2 minutes
  Priority: Normal
```

## Monitoring Teams

### Team Dashboard

Monitor team performance:

```yaml
Team Metrics:
  Content Team:
    Active Tasks: 3
    Completed Today: 12
    Average Quality Score: 4.2/5

  Agent Performance:
    Researcher:
      Tasks: 15
      Avg Time: 45s
      Quality: 4.5/5

    Writer:
      Tasks: 12
      Avg Time: 90s
      Quality: 4.0/5

    Editor:
      Tasks: 12
      Avg Time: 30s
      Quality: 4.3/5
```

### Conversation History

Track agent interactions:

```yaml
Team Conversation: Task #12345

  [10:00:15] Coordinator → Team:
    "New request: Create product description for Widget X"

  [10:00:20] Coordinator → Researcher:
    "Gather product specifications and competitor info"

  [10:01:05] Researcher → Coordinator:
    "Research complete. Key features: [...]"

  [10:01:10] Coordinator → Writer:
    "Create description using research. 100-150 words."

  [10:02:30] Writer → Coordinator:
    "Draft complete: [...]"

  [10:02:35] Coordinator → Editor:
    "Review for clarity and accuracy"

  [10:03:00] Editor → Coordinator:
    "Approved with minor suggestions: [...]"

  [10:03:05] Coordinator → User:
    "Task complete. Final description: [...]"
```

## Best Practices

### Team Design

1. **Clear Role Definition**
   - Specific responsibilities
   - Non-overlapping expertise
   - Defined handoff points

2. **Appropriate Team Size**
   - Start small (3-5 agents)
   - Add specialists as needed
   - Avoid over-engineering

3. **Efficient Communication**
   - Structured message formats
   - Relevant context only
   - Clear success criteria

### Coordination

1. **Coordinator Selection**
   - Strong reasoning capability
   - Good task decomposition
   - Effective delegation

2. **Error Handling**
   - Retry mechanisms
   - Fallback agents
   - Escalation paths

3. **Quality Control**
   - Review checkpoints
   - Feedback loops
   - Quality metrics

### Performance

1. **Parallel Where Possible**
   - Independent subtasks
   - Resource availability
   - Coordination overhead

2. **Caching**
   - Shared research
   - Common context
   - Repeated queries

3. **Monitoring**
   - Track completion times
   - Measure quality
   - Identify bottlenecks

## Example: Customer Support Team

Complete team configuration:

```yaml
Team: Enterprise Support

  Coordinator:
    Agent: support-coordinator
    Model: gpt-4o

  Members:
    - agent: triage-agent
      role: Initial classification
      model: gpt-3.5-turbo  # Fast for simple task

    - agent: technical-agent
      role: Technical issues
      model: gpt-4o
      tools: [documentation_search, ticket_system]

    - agent: billing-agent
      role: Billing inquiries
      model: gpt-4o
      tools: [billing_system, refund_processor]

    - agent: escalation-agent
      role: Complex cases
      model: gpt-4o
      tools: [priority_system, manager_notification]

  Workflow:
    1. User submits inquiry
    2. Triage classifies and routes
    3. Specialist handles (technical/billing)
    4. If unresolved → escalation
    5. Coordinator compiles response
    6. Quality check before send

  SLAs:
    Classification: 5 seconds
    Initial Response: 30 seconds
    Resolution: 5 minutes
    Escalation Threshold: 2 attempts
```

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [Building AI Workflows](/kb/building-ai-workflows)

---

Need help with agent teams? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "agent-teams-multi-agent") do |article|
  article.title = "Agent Teams and Multi-Agent Orchestration"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Coordinate multiple AI agents for complex tasks through team collaboration, task delegation, communication patterns, and workflow orchestration."
  article.content = agent_teams_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Agent Teams and Multi-Agent Orchestration"

puts "  ✅ AI Orchestration articles created (6 articles)"
