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

# Article 21: AI Conversations Guide
ai_conversations_content = <<~MARKDOWN
# AI Conversations Guide

Use Powernode's AI conversation interface to interact with agents, test prompts, and build conversational experiences.

## Conversations Overview

### What Are AI Conversations?

AI Conversations provide an interactive chat interface to:
- Communicate with configured AI agents
- Test and refine prompts
- Build conversational workflows
- Review interaction history

### Accessing Conversations

Navigate to **AI > Conversations** to access:
- Active conversation threads
- Agent selector
- Chat interface
- History and analytics

## Starting a Conversation

### Quick Start

1. Navigate to **AI > Conversations**
2. Click **New Conversation**
3. Select an agent to chat with
4. Enter your message
5. Receive AI response

### Agent Selection

Choose from available agents:

```yaml
Available Agents:
  - Support Agent: Customer service inquiries
  - Research Agent: Information gathering
  - Writer Agent: Content creation
  - Code Agent: Programming assistance
  - Custom Agents: Your configured agents
```

## Conversation Interface

### Chat Window

```
┌─────────────────────────────────────────────┐
│  Agent: Support Agent          [Settings]   │
├─────────────────────────────────────────────┤
│                                             │
│  [User]: How do I upgrade my plan?          │
│                                             │
│  [Agent]: I'd be happy to help you upgrade! │
│  To change your subscription plan:          │
│  1. Go to Settings > Billing                │
│  2. Click "Change Plan"                     │
│  3. Select your new plan                    │
│  ...                                        │
│                                             │
├─────────────────────────────────────────────┤
│  [Type your message...]           [Send]    │
└─────────────────────────────────────────────┘
```

### Message Features

| Feature | Description |
|---------|-------------|
| **Markdown** | Format messages with markdown |
| **Code Blocks** | Syntax-highlighted code |
| **Attachments** | Upload files for context |
| **Reactions** | Rate responses |
| **Copy** | Copy responses to clipboard |
| **Regenerate** | Request new response |

## Conversation Settings

### Per-Conversation Options

```yaml
Conversation Settings:
  Agent: support-agent
  Model Override: gpt-4o (optional)
  Temperature: 0.7
  Max Tokens: 2000

  Context:
    Include History: true
    Max History Messages: 20
    System Context: "User is on Professional plan"

  Tools:
    Enabled: true
    Available:
      - customer_lookup
      - kb_search
```

### Context Injection

Add context to conversations:

```yaml
Context Options:
  - System Context: Background information for agent
  - User Context: Information about the user
  - Document Context: Upload documents for reference
  - Conversation Memory: Previous interactions
```

## Managing Conversations

### Conversation List

View all conversations:

| Column | Description |
|--------|-------------|
| Title | Conversation name/topic |
| Agent | Agent used |
| Messages | Message count |
| Last Activity | Most recent interaction |
| Status | Active, archived, starred |

### Organization

- **Star** important conversations
- **Archive** completed conversations
- **Delete** unwanted conversations
- **Search** by content or metadata
- **Filter** by agent, date, status

### Conversation Actions

```yaml
Actions:
  - Export: Download as JSON/Markdown
  - Share: Generate shareable link
  - Duplicate: Create copy for testing
  - Branch: Fork from a specific message
  - Summarize: Generate conversation summary
```

## Advanced Features

### Multi-Agent Conversations

Chat with multiple agents:

```yaml
Multi-Agent Setup:
  Primary: support-agent
  Secondary: technical-agent

  Routing:
    - Technical questions → technical-agent
    - Billing questions → support-agent

  Handoff:
    Auto-detect topic change
    Smooth context transfer
```

### Conversation Templates

Start with predefined templates:

```yaml
Template: Customer Support Session
  Initial Context:
    - Load customer profile
    - Recent ticket history
    - Subscription details

  Agent: support-agent

  Opening Message: |
    Hello! I'm here to help with your account.
    How can I assist you today?
```

### Branching Conversations

Explore alternative responses:

1. Click on any message
2. Select **Branch from here**
3. Enter new message
4. Compare different paths

### Feedback and Rating

Improve agents through feedback:

```yaml
Feedback Options:
  - Thumbs up/down per message
  - Rating (1-5 stars)
  - Written feedback
  - Flag inappropriate content
  - Suggest corrections
```

## Conversation History

### Viewing History

Access past conversations:

1. Navigate to **AI > Conversations**
2. Use filters to find specific conversations
3. Click to open and review

### Analytics

Track conversation metrics:

```yaml
Conversation Analytics:
  Total Conversations: 1,250
  Messages Sent: 15,600
  Avg Response Time: 1.8s
  User Satisfaction: 4.2/5

  By Agent:
    support-agent: 800 conversations
    research-agent: 300 conversations
    code-agent: 150 conversations
```

### Export Options

Export conversation data:

| Format | Use Case |
|--------|----------|
| JSON | Full data with metadata |
| Markdown | Readable format |
| CSV | Analysis in spreadsheets |
| PDF | Documentation |

## Integration with Workflows

### Triggering Workflows

Start workflows from conversations:

```yaml
Workflow Trigger:
  Keyword: "escalate to human"
  Action: Create support ticket
  Include: Full conversation history
```

### Embedding Conversations

Embed AI chat in your applications:

```html
<!-- Chat Widget Embed -->
<script src="https://powernode.org/chat-widget.js"></script>
<script>
  PowernodeChat.init({
    agent: 'support-agent',
    apiKey: 'your-api-key',
    theme: 'light'
  });
</script>
```

## Best Practices

### Effective Conversations

1. **Be Specific**
   - Clear, focused questions
   - Provide relevant context
   - One topic at a time

2. **Use Context**
   - Upload relevant documents
   - Reference previous messages
   - Set system context

3. **Iterate**
   - Refine based on responses
   - Use regenerate for alternatives
   - Branch to explore options

### Agent Configuration

1. **Match Agent to Task**
   - Use specialized agents
   - Configure appropriate tools
   - Set suitable temperature

2. **Optimize Context**
   - Limit history for performance
   - Provide relevant context only
   - Update system prompts

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [Managing Prompt Templates](/kb/managing-prompt-templates)

---

Need help with conversations? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "ai-conversations-guide") do |article|
  article.title = "AI Conversations Guide"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Interactive guide to using AI conversations for chatting with agents, testing prompts, managing history, and building conversational experiences."
  article.content = ai_conversations_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ AI Conversations Guide"

# Article 22: Managing Prompt Templates
prompt_templates_content = <<~MARKDOWN
# Managing Prompt Templates

Create, organize, and reuse prompt templates to standardize AI interactions and improve agent consistency.

## What Are Prompt Templates?

Prompt templates are reusable text patterns that:
- Standardize interactions with AI agents
- Include variable placeholders for dynamic content
- Enable consistent outputs across users
- Save time on repetitive prompts

## Creating Templates

### Template Structure

```yaml
Template Configuration:
  Name: Customer Response Template
  Description: Generate professional customer responses
  Category: Support

  Variables:
    - name: customer_name
      type: string
      required: true
      description: Customer's name

    - name: issue_type
      type: enum
      values: [billing, technical, general]
      required: true

    - name: context
      type: text
      required: false
      description: Additional context

  Template: |
    Generate a professional response for {{customer_name}} regarding their {{issue_type}} inquiry.

    Context: {{context}}

    Requirements:
    - Be empathetic and professional
    - Provide clear next steps
    - Include relevant links if applicable
    - Keep response under 200 words
```

### Via Dashboard

1. Navigate to **AI > Prompts**
2. Click **Create Template**
3. Enter template details:
   - Name and description
   - Category/tags
   - Variable definitions
   - Template content
4. Test with sample data
5. Save template

### Variable Types

| Type | Description | Example |
|------|-------------|---------|
| `string` | Single line text | Name, ID |
| `text` | Multi-line text | Description, context |
| `number` | Numeric value | Count, amount |
| `enum` | Predefined options | Status, category |
| `boolean` | True/false | Flag, toggle |
| `date` | Date value | Start date, deadline |
| `json` | Structured data | Configuration |

## Using Templates

### In Conversations

Apply templates in chat:

1. Click **Insert Template** button
2. Select template from list
3. Fill in variable values
4. Preview generated prompt
5. Send to agent

### In Workflows

Reference templates in workflow nodes:

```yaml
Workflow Node:
  Type: agent
  Agent: writer-agent
  Prompt Template: blog-outline-template
  Variables:
    topic: "{{trigger.data.topic}}"
    audience: "technical professionals"
    length: "1500 words"
```

### Via API

```bash
curl -X POST https://api.powernode.org/api/v1/ai/prompts/render \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "template_id": "tmpl_01HQ7EXAMPLE",
    "variables": {
      "customer_name": "Jane Smith",
      "issue_type": "billing",
      "context": "Duplicate charge on account"
    }
  }'
```

## Template Categories

### Organizing Templates

Group templates by purpose:

```yaml
Categories:
  Support:
    - Customer Response
    - Escalation Summary
    - Resolution Confirmation

  Content:
    - Blog Outline
    - Product Description
    - Email Newsletter

  Development:
    - Code Review
    - Documentation
    - Test Generation

  Analysis:
    - Data Summary
    - Report Generation
    - Trend Analysis
```

### Template Tags

Add tags for easy discovery:

- `customer-facing`
- `internal`
- `technical`
- `creative`
- `formal`
- `casual`

## Advanced Features

### Conditional Sections

Include conditional content:

```yaml
Template: |
  Hello {{customer_name}},

  {{#if is_premium}}
  As a Premium member, you have access to priority support.
  {{else}}
  Consider upgrading to Premium for faster support.
  {{/if}}

  Regarding your {{issue_type}} inquiry...
```

### Nested Variables

Use complex variable structures:

```yaml
Variables:
  - name: order
    type: json
    schema:
      id: string
      items: array
      total: number

Template: |
  Order #\\{\\{order.id\\}\\} Summary:
  \\{\\{#each order.items\\}\\}
  - \\{\\{this.name\\}\\}: \\{\\{this.quantity\\}\\} x $\\{\\{this.price\\}\\}
  \\{\\{/each\\}\\}
  Total: $\\{\\{order.total\\}\\}
```

### Default Values

Set fallback values:

```yaml
Variables:
  - name: greeting
    type: string
    default: "Hello"

  - name: tone
    type: enum
    values: [formal, casual, friendly]
    default: friendly
```

### Validation Rules

Ensure variable quality:

```yaml
Variables:
  - name: email
    type: string
    validation:
      pattern: "^[\\w.-]+@[\\w.-]+\\.\\w+$"
      message: "Invalid email format"

  - name: word_count
    type: number
    validation:
      min: 100
      max: 5000
```

## Template Versioning

### Version Management

Track template changes:

```yaml
Version History:
  v3 (current):
    Modified: 2024-01-15
    Changes: Added context variable
    Author: admin@company.com

  v2:
    Modified: 2024-01-10
    Changes: Improved formatting

  v1:
    Created: 2024-01-01
    Initial version
```

### Rollback

Restore previous versions:

1. Navigate to template
2. Click **Version History**
3. Select version to restore
4. Click **Restore This Version**

## Sharing Templates

### Team Sharing

Share within your organization:

```yaml
Sharing Settings:
  Visibility: Team
  Permissions:
    - team-leads: edit
    - support-team: use
    - all-users: view
```

### Template Library

Access shared templates:

1. Navigate to **AI > Prompts > Library**
2. Browse by category
3. Preview template details
4. **Import** to your templates

## Best Practices

### Template Design

1. **Clear Instructions**
   - Explicit requirements
   - Output format specification
   - Constraints and limits

2. **Appropriate Variables**
   - Meaningful names
   - Helpful descriptions
   - Sensible defaults

3. **Tested Thoroughly**
   - Multiple test cases
   - Edge cases
   - Various inputs

### Organization

1. **Consistent Naming**
   - Category-Purpose-Version
   - Example: `support-response-v2`

2. **Documentation**
   - Usage examples
   - Variable explanations
   - Expected outputs

3. **Regular Review**
   - Update outdated templates
   - Remove unused templates
   - Improve based on feedback

## Troubleshooting

### Common Issues

**Variable Not Rendering**
- Check variable name matches exactly
- Verify variable is passed
- Check for typos in template

**Template Too Long**
- Split into smaller templates
- Use template composition
- Reduce redundant text

**Poor Output Quality**
- Add more specific instructions
- Include examples in template
- Adjust agent parameters

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [AI Conversations Guide](/kb/ai-conversations-guide)

---

Need help with templates? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "managing-prompt-templates") do |article|
  article.title = "Managing Prompt Templates"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Create and manage reusable prompt templates with variables, versioning, sharing, and advanced features for consistent AI interactions."
  article.content = prompt_templates_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Managing Prompt Templates"

# Article 23: AI Monitoring Dashboard
ai_monitoring_content = <<~MARKDOWN
# AI Monitoring Dashboard

Monitor AI system performance, track usage metrics, and ensure reliability with real-time observability.

## Monitoring Overview

### Dashboard Access

Navigate to **AI > Monitoring** to view:
- Real-time system health
- Performance metrics
- Usage statistics
- Error tracking
- Cost analysis

### Key Metrics

```
┌─────────────────────────────────────────────────────┐
│  AI System Health                    Status: ✅ OK   │
├─────────────────────────────────────────────────────┤
│  Requests/min: 45    │  Avg Latency: 1.2s          │
│  Success Rate: 99.2% │  Active Agents: 12          │
├─────────────────────────────────────────────────────┤
│  [Request Volume Graph - Last 24 Hours]             │
│  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁    │
└─────────────────────────────────────────────────────┘
```

## Real-Time Metrics

### System Health

| Indicator | Description | Target |
|-----------|-------------|--------|
| **Status** | Overall system health | Green |
| **Uptime** | System availability | > 99.9% |
| **Active Connections** | Current API connections | Monitor |
| **Queue Depth** | Pending requests | < 100 |

### Performance Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| **Latency P50** | Median response time | < 1s |
| **Latency P95** | 95th percentile | < 3s |
| **Latency P99** | 99th percentile | < 5s |
| **Throughput** | Requests per second | Monitor |
| **Error Rate** | Failed requests | < 1% |

### Token Usage

```yaml
Token Metrics (Last 24 Hours):
  Total Tokens: 2,450,000

  By Provider:
    OpenAI: 1,500,000 (61%)
    Anthropic: 800,000 (33%)
    Ollama: 150,000 (6%)

  By Model:
    gpt-4o: 1,000,000
    claude-3-5-sonnet: 800,000
    gpt-3.5-turbo: 500,000
    llama3.1: 150,000
```

## Provider Monitoring

### Provider Status

Monitor each AI provider:

```yaml
Provider Health:
  OpenAI:
    Status: ✅ Operational
    Latency: 1.1s avg
    Success Rate: 99.5%
    Rate Limit: 45% used

  Anthropic:
    Status: ✅ Operational
    Latency: 1.4s avg
    Success Rate: 99.8%
    Rate Limit: 30% used

  Ollama (Local):
    Status: ✅ Running
    Latency: 0.8s avg
    GPU Usage: 65%
    Memory: 12GB/16GB
```

### Rate Limit Tracking

```yaml
Rate Limits:
  OpenAI (gpt-4o):
    Requests: 450/500 per minute
    Tokens: 85,000/100,000 per minute
    Status: ⚠️ Near limit

  Anthropic (claude-3-5-sonnet):
    Requests: 150/500 per minute
    Tokens: 45,000/200,000 per minute
    Status: ✅ OK
```

## Agent Monitoring

### Agent Performance

Track individual agent metrics:

```yaml
Agent: Support Agent
  Total Requests: 5,234
  Avg Response Time: 1.8s
  Success Rate: 98.5%
  User Satisfaction: 4.2/5

  Tool Usage:
    customer_lookup: 2,100 calls
    kb_search: 1,800 calls
    create_ticket: 450 calls

  Errors:
    Timeout: 35
    Rate Limited: 12
    Tool Failure: 8
```

### Agent Comparison

| Agent | Requests | Latency | Success | Satisfaction |
|-------|----------|---------|---------|--------------|
| Support | 5,234 | 1.8s | 98.5% | 4.2/5 |
| Research | 2,100 | 3.2s | 99.1% | 4.4/5 |
| Writer | 1,500 | 4.5s | 97.8% | 4.0/5 |
| Code | 890 | 2.1s | 96.5% | 4.3/5 |

## Workflow Monitoring

### Workflow Execution

Track workflow performance:

```yaml
Workflow: Customer Feedback Pipeline
  Executions Today: 125
  Avg Duration: 8.5s
  Success Rate: 94%

  Step Performance:
    1. Trigger: 0.1s
    2. Sentiment Analysis: 1.8s
    3. Classification: 1.5s
    4. Routing: 0.2s
    5. Response Generation: 4.5s
    6. Notification: 0.4s
```

### Failed Executions

```yaml
Recent Failures:
  - exec_01HQ7EXAMPLE
    Time: 10:45:23
    Step: Response Generation
    Error: Rate limit exceeded
    Action: Queued for retry

  - exec_01HQ7EXAMPLE2
    Time: 10:32:15
    Step: Tool Execution
    Error: API timeout
    Action: Manual review needed
```

## Alerting

### Alert Configuration

Set up monitoring alerts:

```yaml
Alert Rules:
  - name: High Error Rate
    condition: error_rate > 5%
    duration: 5 minutes
    severity: critical
    actions:
      - notify: ops-team
      - channel: slack

  - name: Latency Spike
    condition: latency_p95 > 5s
    duration: 10 minutes
    severity: warning
    actions:
      - notify: ai-team

  - name: Rate Limit Warning
    condition: rate_limit_usage > 80%
    severity: warning
    actions:
      - notify: ai-team
      - auto_throttle: true
```

### Notification Channels

| Channel | Configuration |
|---------|---------------|
| Email | ops@company.com |
| Slack | #ai-alerts |
| PagerDuty | ai-oncall |
| Webhook | Custom endpoint |

## Cost Monitoring

### Cost Dashboard

Track AI spending:

```yaml
Cost Summary (Month to Date):
  Total: $1,245.67

  By Provider:
    OpenAI: $890.50 (71%)
    Anthropic: $325.17 (26%)
    Ollama: $30.00 (3% - infrastructure)

  By Agent:
    Support Agent: $450.00
    Research Agent: $380.00
    Writer Agent: $290.00
    Other: $125.67

  Trend: +15% vs last month
```

### Budget Alerts

```yaml
Budget Configuration:
  Monthly Budget: $2,000
  Current Usage: $1,245.67 (62%)

  Alerts:
    - At 75% ($1,500): Email finance
    - At 90% ($1,800): Email leadership
    - At 100% ($2,000): Auto-throttle
```

## Historical Analysis

### Trend Analysis

View historical patterns:

- Daily/weekly/monthly comparisons
- Seasonal patterns
- Growth trends
- Anomaly detection

### Report Generation

Generate custom reports:

```yaml
Report Configuration:
  Name: Weekly AI Summary
  Period: Last 7 days
  Metrics:
    - Total requests
    - Success rate
    - Avg latency
    - Cost breakdown
    - Top agents
  Format: PDF
  Schedule: Every Monday 9 AM
  Recipients: management@company.com
```

## Debugging Tools

### Request Inspector

Examine individual requests:

```yaml
Request Details:
  ID: req_01HQ7EXAMPLE
  Time: 2024-01-15T10:30:45Z
  Agent: support-agent
  Provider: openai
  Model: gpt-4o

  Input:
    Tokens: 450
    Characters: 1,800

  Output:
    Tokens: 280
    Characters: 1,120

  Performance:
    Total Time: 1.85s
    API Time: 1.62s
    Processing: 0.23s

  Status: Success
```

### Log Viewer

Access detailed logs:

```yaml
Log Filters:
  - Time range
  - Agent
  - Provider
  - Status (success/error)
  - Severity level

Log Entry:
  [2024-01-15 10:30:45] INFO [support-agent]
  Request completed successfully
  Duration: 1.85s, Tokens: 730, Cost: $0.0146
```

## Best Practices

### Monitoring Setup

1. **Baseline Metrics**
   - Establish normal ranges
   - Document expected values
   - Set appropriate thresholds

2. **Alert Tuning**
   - Start conservative
   - Reduce noise over time
   - Prioritize actionable alerts

3. **Regular Review**
   - Weekly metric review
   - Monthly trend analysis
   - Quarterly optimization

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Configuring AI Providers](/kb/configuring-ai-providers)
- [AI Governance and Policies](/kb/ai-governance-policies)

---

Need help with monitoring? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "ai-monitoring-dashboard") do |article|
  article.title = "AI Monitoring Dashboard"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Monitor AI system health, performance metrics, provider status, agent performance, costs, and set up alerting for real-time observability."
  article.content = ai_monitoring_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ AI Monitoring Dashboard"

# Article 24: AI Governance and Policies
ai_governance_content = <<~MARKDOWN
# AI Governance and Policies

Implement responsible AI practices with governance policies, compliance controls, and safety guardrails.

## Governance Overview

### Why AI Governance?

AI governance ensures:
- **Safety** - Prevent harmful outputs
- **Compliance** - Meet regulatory requirements
- **Consistency** - Standardized AI behavior
- **Accountability** - Audit trails and oversight
- **Trust** - Build user confidence

### Accessing Governance

Navigate to **AI > Governance** to manage:
- Usage policies
- Content filters
- Access controls
- Compliance settings
- Audit reports

## Policy Configuration

### Usage Policies

Define how AI can be used:

```yaml
Usage Policy: Production AI Policy
  Status: Active

  Allowed Use Cases:
    - Customer support
    - Content generation
    - Data analysis
    - Code assistance

  Prohibited Use Cases:
    - Medical diagnosis
    - Legal advice
    - Financial decisions
    - Personal data processing without consent

  Required Approvals:
    - New agent deployment: AI Team Lead
    - Production changes: Security Team
    - External-facing agents: Legal Review
```

### Content Policies

Configure content filtering:

```yaml
Content Policy:
  Input Filtering:
    PII Detection: enabled
    Profanity Filter: enabled
    Prompt Injection Protection: enabled
    Max Input Length: 10000 characters

  Output Filtering:
    Harmful Content: block
    PII in Output: redact
    Code Execution: sandbox only
    External Links: validate

  Topic Restrictions:
    Blocked Topics:
      - Violence
      - Illegal activities
      - Adult content
    Flagged Topics:
      - Medical
      - Legal
      - Financial
```

## Access Controls

### Role-Based Permissions

Control AI feature access:

```yaml
Permission Matrix:
  AI Administrators:
    - ai.providers.manage
    - ai.agents.manage
    - ai.governance.manage
    - ai.analytics.view

  AI Developers:
    - ai.agents.create
    - ai.workflows.create
    - ai.prompts.manage
    - ai.sandbox.use

  AI Users:
    - ai.conversations.create
    - ai.agents.use
    - ai.workflows.execute

  Viewers:
    - ai.analytics.view
    - ai.conversations.read
```

### Agent Access Controls

Restrict who can use specific agents:

```yaml
Agent: Financial Analysis Agent
  Access Control:
    Allowed Users:
      - finance-team
      - executives
    Allowed Roles:
      - financial_analyst
      - cfo
    IP Restrictions:
      - 10.0.0.0/8 (corporate network)
    Time Restrictions:
      - Weekdays 8am-6pm only
```

## Safety Guardrails

### Input Guardrails

Protect against malicious inputs:

```yaml
Input Guardrails:
  Prompt Injection Detection:
    Enabled: true
    Sensitivity: high
    Action: block_and_log

  PII Detection:
    Types:
      - SSN
      - Credit Card
      - Email
      - Phone
    Action: redact_and_warn

  Rate Limiting:
    Per User: 60 requests/hour
    Per Agent: 500 requests/hour
```

### Output Guardrails

Filter AI responses:

```yaml
Output Guardrails:
  Content Classification:
    - Harmful content: block
    - Uncertain responses: flag
    - External URLs: validate

  Confidence Threshold:
    Minimum: 0.7
    Below Threshold: Add disclaimer

  Response Validation:
    - Check for hallucinations
    - Validate factual claims
    - Ensure format compliance
```

### Human-in-the-Loop

Require human review for sensitive operations:

```yaml
Human Review Requirements:
  High Stakes Decisions:
    - Account modifications: Review required
    - Financial transactions: Manager approval
    - Customer communications: Spot check 10%

  Review Workflow:
    1. AI generates response
    2. Response queued for review
    3. Human approves/edits/rejects
    4. Final response sent
```

## Compliance

### Regulatory Requirements

Address compliance needs:

```yaml
Compliance Configuration:
  GDPR:
    Data Processing Records: enabled
    Right to Explanation: enabled
    Data Retention: 90 days
    Consent Tracking: required

  SOC 2:
    Access Logging: enabled
    Change Management: enforced
    Encryption: at rest and in transit

  Industry Specific:
    HIPAA: Not applicable
    PCI DSS: Enabled for payment agents
```

### Compliance Reports

Generate compliance documentation:

| Report | Frequency | Contents |
|--------|-----------|----------|
| Access Report | Monthly | Who accessed what |
| Usage Report | Weekly | AI activity summary |
| Audit Report | Quarterly | Full compliance audit |
| Incident Report | As needed | Security incidents |

## Audit Logging

### What's Logged

Comprehensive audit trail:

```yaml
Audit Log Entry:
  Timestamp: 2024-01-15T10:30:45Z
  Event: agent.response.generated

  Actor:
    User: jane@company.com
    IP: 192.168.1.100
    Session: sess_01HQ7EXAMPLE

  Resource:
    Agent: support-agent
    Conversation: conv_01HQ7EXAMPLE

  Details:
    Model: gpt-4o
    Tokens: 730
    Cost: $0.0146
    Content Hash: sha256:abc123...

  Compliance:
    PII Detected: false
    Content Filtered: false
    Policy Violations: none
```

### Audit Queries

Search audit logs:

```yaml
Query Examples:
  # All agent uses by specific user
  user: jane@company.com
  event: agent.response.*

  # All policy violations this week
  event: policy.violation
  timeframe: last_7_days

  # High-cost requests
  details.cost: > 0.10
```

## Incident Management

### Incident Types

| Type | Severity | Response |
|------|----------|----------|
| Policy Violation | Medium | Review and educate |
| Harmful Content | High | Block and investigate |
| Data Breach | Critical | Immediate escalation |
| System Abuse | High | Suspend access |

### Incident Response

```yaml
Incident Workflow:
  1. Detection:
     - Automated monitoring
     - User reports
     - Audit review

  2. Assessment:
     - Severity classification
     - Impact analysis
     - Root cause identification

  3. Response:
     - Immediate containment
     - User notification
     - System updates

  4. Review:
     - Post-incident analysis
     - Policy updates
     - Training improvements
```

## Model Governance

### Model Registry

Track approved models:

```yaml
Approved Models:
  Production:
    - gpt-4o (OpenAI)
    - claude-3-5-sonnet (Anthropic)
    - llama3.1:70b (Ollama - internal only)

  Sandbox Only:
    - gpt-4-turbo (testing)
    - claude-3-opus (cost-restricted)

  Deprecated:
    - gpt-3.5-turbo (end of life: 2024-06)
```

### Model Evaluation

Regular model assessment:

```yaml
Model Review:
  Frequency: Quarterly
  Criteria:
    - Performance benchmarks
    - Safety evaluations
    - Cost efficiency
    - Compliance alignment
    - User satisfaction
```

## Best Practices

### Policy Development

1. **Start with Principles**
   - Define core values
   - Align with company ethics
   - Consider stakeholders

2. **Involve Stakeholders**
   - Legal/compliance team
   - Security team
   - Business users
   - Technical team

3. **Iterate and Improve**
   - Regular policy reviews
   - Incident-driven updates
   - Industry benchmarking

### Implementation

1. **Gradual Rollout**
   - Pilot with low-risk use cases
   - Expand based on learnings
   - Monitor continuously

2. **Training**
   - User education
   - Developer guidelines
   - Compliance training

3. **Measurement**
   - Define success metrics
   - Track policy effectiveness
   - Report to stakeholders

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [AI Monitoring Dashboard](/kb/ai-monitoring-dashboard)
- [Security Configuration Guide](/kb/security-configuration-guide)

---

Need help with governance? Contact compliance@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "ai-governance-policies") do |article|
  article.title = "AI Governance and Policies"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Implement responsible AI with governance policies, content filtering, access controls, compliance settings, and safety guardrails."
  article.content = ai_governance_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ AI Governance and Policies"

# Article 25: Using the AI Sandbox
ai_sandbox_content = <<~MARKDOWN
# Using the AI Sandbox

Safely test, experiment, and develop AI capabilities in an isolated environment before production deployment.

## Sandbox Overview

### What is the AI Sandbox?

The AI Sandbox provides:
- **Isolated environment** for testing
- **Safe experimentation** without production impact
- **Development tools** for building agents
- **Debugging capabilities** for troubleshooting

### Accessing the Sandbox

Navigate to **AI > Sandbox** to:
- Test prompts and agents
- Experiment with models
- Debug workflows
- Evaluate outputs

## Sandbox Features

### Prompt Playground

Test prompts interactively:

```
┌─────────────────────────────────────────────────────┐
│  AI Playground                                       │
├──────────────────────┬──────────────────────────────┤
│  System Prompt       │  Response                     │
│  ─────────────────   │  ──────────────────          │
│  You are a helpful   │  Based on the information    │
│  assistant that...   │  provided, here's my         │
│                      │  analysis...                  │
│  User Message        │                               │
│  ─────────────────   │                               │
│  Analyze this data:  │                               │
│  [Sample data...]    │                               │
│                      │                               │
├──────────────────────┼──────────────────────────────┤
│  Model: gpt-4o  ▼    │  Tokens: 450 | Cost: $0.009  │
│  Temp: 0.7  [───●──] │  Latency: 1.2s               │
└──────────────────────┴──────────────────────────────┘
```

### Configuration Options

```yaml
Playground Settings:
  Provider: openai
  Model: gpt-4o

  Parameters:
    Temperature: 0.7
    Max Tokens: 2000
    Top P: 1.0
    Frequency Penalty: 0
    Presence Penalty: 0

  Options:
    Stream Response: true
    Show Token Count: true
    Show Cost Estimate: true
    Enable Tools: false
```

## Testing Agents

### Agent Testing Mode

Test agents without production impact:

```yaml
Test Configuration:
  Agent: support-agent
  Mode: sandbox

  Mock Data:
    Customer:
      id: "test_customer_001"
      name: "Test User"
      plan: "professional"

  Tool Mocking:
    customer_lookup:
      response: mock_customer_data.json
    create_ticket:
      response: "ticket_001"

  Logging:
    Level: debug
    Include: prompts, responses, tool_calls
```

### Test Scenarios

Create reusable test cases:

```yaml
Test Scenario: Billing Inquiry
  Description: Test agent handling of billing questions

  Messages:
    - role: user
      content: "I was charged twice for my subscription"

  Expected:
    - Contains: "I apologize"
    - Contains: "billing"
    - Tool Called: customer_lookup
    - Sentiment: empathetic

  Assertions:
    - response_time < 3s
    - no_pii_in_response
    - professional_tone
```

## Workflow Development

### Visual Workflow Builder

Build workflows in sandbox mode:

1. Create workflow in Sandbox
2. Add nodes and connections
3. Configure each node
4. Test with sample data
5. Debug and iterate
6. Deploy to production

### Step-by-Step Execution

Debug workflows step-by-step:

```yaml
Debug Mode:
  Workflow: customer-feedback-pipeline
  Execution: Step-by-step

  Controls:
    - Step Forward
    - Step Back
    - Pause at Node
    - Inspect Variables
    - Modify Data

  Breakpoints:
    - Node: sentiment_analysis
    - Node: routing_decision
```

### Data Inspection

Examine data at each step:

```yaml
Node: sentiment_analysis
  Input:
    text: "The product is great but shipping was slow"

  Output:
    sentiment: "mixed"
    score: 0.3
    aspects:
      - product: positive
      - shipping: negative

  Performance:
    Duration: 1.2s
    Tokens: 180
```

## Model Comparison

### Side-by-Side Testing

Compare model responses:

```
┌─────────────────────────┬─────────────────────────┐
│  GPT-4o                 │  Claude 3.5 Sonnet      │
├─────────────────────────┼─────────────────────────┤
│  Response:              │  Response:              │
│  Here's my analysis...  │  I've analyzed the...   │
│                         │                         │
│  Tokens: 320            │  Tokens: 285            │
│  Latency: 1.2s          │  Latency: 1.5s          │
│  Cost: $0.0064          │  Cost: $0.0057          │
└─────────────────────────┴─────────────────────────┘
```

### Evaluation Criteria

Define comparison metrics:

```yaml
Evaluation Criteria:
  - Accuracy: Manual rating (1-5)
  - Relevance: How well it addresses the query
  - Coherence: Logical flow and clarity
  - Completeness: Covers all aspects
  - Tone: Appropriate for use case
  - Cost Efficiency: Tokens per quality point
```

## Prompt Engineering

### Prompt Iteration

Refine prompts systematically:

```yaml
Iteration History:
  Version 1:
    Prompt: "Summarize this text"
    Result: Too brief, missing key points

  Version 2:
    Prompt: "Summarize this text in 3-5 bullet points"
    Result: Better structure, but too technical

  Version 3:
    Prompt: |
      Summarize this text for a non-technical audience.
      Include 3-5 key points.
      Use simple language.
    Result: ✅ Meets requirements
```

### A/B Testing

Compare prompt variations:

```yaml
A/B Test Configuration:
  Name: Summary Prompt Test
  Variants:
    A: "Summarize in bullet points"
    B: "Provide a brief executive summary"

  Test Cases: 50 documents
  Metrics:
    - User preference
    - Completeness score
    - Response length

  Results:
    Variant A: 58% preferred
    Variant B: 42% preferred
```

## Tool Testing

### MCP Tool Validation

Test tool integrations:

```yaml
Tool Test: customer_lookup
  Input:
    email: "test@example.com"

  Expected Output:
    customer_id: "cust_..."
    name: string
    plan: enum(free, basic, professional, enterprise)

  Test Result:
    Status: ✅ Pass
    Response Time: 45ms
    Output Validated: true
```

### Mock Responses

Configure mock tool responses:

```yaml
Mock Configuration:
  Tool: external_api

  Scenarios:
    success:
      status: 200
      body: {"result": "success"}

    rate_limited:
      status: 429
      body: {"error": "Rate limit exceeded"}

    timeout:
      delay: 35s
      status: timeout
```

## Debugging

### Debug Console

Access detailed debugging:

```yaml
Debug Output:
  Request ID: req_01HQ7EXAMPLE

  System Prompt: [Full text]
  User Message: [Full text]

  Model Response:
    Raw: [Full response]
    Parsed: [Structured data]

  Tool Calls:
    1. customer_lookup({email: "..."})
       Response: {...}
       Duration: 45ms

  Token Breakdown:
    System: 250
    User: 180
    Assistant: 320
    Total: 750
```

### Error Analysis

Understand failures:

```yaml
Error Analysis:
  Error Type: Tool Execution Failed
  Tool: create_ticket

  Details:
    Input: {customer_id: null, ...}
    Error: "customer_id is required"

  Root Cause:
    Previous tool (customer_lookup) returned no results

  Suggested Fix:
    Add null check before create_ticket call
```

## Exporting to Production

### Validation Checklist

Before deploying:

```yaml
Production Readiness:
  ✅ All test scenarios pass
  ✅ Error handling verified
  ✅ Performance within targets
  ✅ Cost estimates acceptable
  ✅ Security review completed
  ✅ Governance policies applied
  ⬜ Stakeholder approval
```

### Deployment Process

1. Complete sandbox testing
2. Export configuration
3. Review in staging
4. Get approvals
5. Deploy to production
6. Monitor initial usage

## Best Practices

### Sandbox Usage

1. **Isolate Experiments**
   - Use sandbox for all development
   - Never test with production data
   - Reset between experiments

2. **Document Findings**
   - Record test results
   - Note configuration changes
   - Share learnings

3. **Systematic Testing**
   - Define test cases upfront
   - Cover edge cases
   - Automate where possible

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [AI Monitoring Dashboard](/kb/ai-monitoring-dashboard)

---

Need help with the sandbox? Contact ai-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "using-ai-sandbox") do |article|
  article.title = "Using the AI Sandbox"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Test, experiment, and develop AI capabilities in an isolated sandbox environment with debugging tools and model comparison features."
  article.content = ai_sandbox_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Using the AI Sandbox"

# Article 26: Agent Marketplace Guide
agent_marketplace_content = <<~MARKDOWN
# Agent Marketplace Guide

Browse, install, and manage pre-built AI agents from the Agent Marketplace to accelerate your AI implementation.

## Marketplace Overview

### What is the Agent Marketplace?

The Agent Marketplace offers:
- **Pre-built agents** ready to deploy
- **Community contributions** from other users
- **Verified solutions** from trusted publishers
- **Templates** to customize and extend

### Accessing the Marketplace

Navigate to **AI > Agent Marketplace** to:
- Browse available agents
- View agent details
- Install agents
- Manage installed agents

## Browsing Agents

### Marketplace Interface

```
┌─────────────────────────────────────────────────────┐
│  Agent Marketplace                    [Search...]   │
├─────────────────────────────────────────────────────┤
│  Categories: All | Support | Content | Dev | Data   │
├─────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐              │
│  │ 🎧 Support    │  │ ✍️ Content    │              │
│  │ Pro Agent     │  │ Writer        │              │
│  │ ⭐⭐⭐⭐⭐ (156)  │  │ ⭐⭐⭐⭐½ (89)  │              │
│  │ by Powernode  │  │ by AITools    │              │
│  │ [Install]     │  │ [Install]     │              │
│  └───────────────┘  └───────────────┘              │
│                                                     │
│  ┌───────────────┐  ┌───────────────┐              │
│  │ 💻 Code       │  │ 📊 Data       │              │
│  │ Review Agent  │  │ Analyst       │              │
│  │ ⭐⭐⭐⭐ (234)   │  │ ⭐⭐⭐⭐⭐ (67)  │              │
│  │ by DevTools   │  │ by Analytics  │              │
│  │ [Install]     │  │ [Install]     │              │
│  └───────────────┘  └───────────────┘              │
└─────────────────────────────────────────────────────┘
```

### Categories

| Category | Description |
|----------|-------------|
| **Support** | Customer service and help desk |
| **Content** | Writing, editing, and creation |
| **Development** | Code review, generation, docs |
| **Data** | Analysis, reporting, insights |
| **Sales** | Lead qualification, outreach |
| **Research** | Information gathering, synthesis |
| **Operations** | Process automation, workflows |

### Filtering and Search

```yaml
Search Filters:
  - Category: Support, Content, Dev, Data
  - Provider: OpenAI, Anthropic, Any
  - Rating: 4+ stars, 3+ stars, All
  - Price: Free, Paid, Enterprise
  - Publisher: Verified, Community, All
  - Compatibility: Your plan level
```

## Agent Details

### Viewing Agent Information

```yaml
Agent: Customer Support Pro
Publisher: Powernode (Verified ✓)
Rating: 4.8/5 (156 reviews)
Installs: 2,500+

Description:
  Enterprise-grade customer support agent with
  multi-channel support, sentiment analysis, and
  intelligent routing capabilities.

Features:
  - Natural conversation handling
  - Sentiment detection and response adjustment
  - Knowledge base integration
  - Escalation management
  - Multi-language support (12 languages)

Requirements:
  Provider: OpenAI or Anthropic
  Plan: Professional or higher
  Tools: kb_search, ticket_system (optional)

Pricing: Free (included with plan)
```

### Reviews and Ratings

```yaml
User Reviews:
  ⭐⭐⭐⭐⭐ "Excellent agent, reduced response time by 40%"
  - Jane S., Professional Plan

  ⭐⭐⭐⭐ "Great for most cases, occasionally needs tuning"
  - Mike T., Enterprise Plan

  ⭐⭐⭐⭐⭐ "Best support agent we've used"
  - Sarah K., Business Plan
```

## Installing Agents

### Installation Process

1. **Select Agent**
   - Browse or search marketplace
   - Review agent details

2. **Check Requirements**
   - Verify provider compatibility
   - Confirm plan eligibility
   - Review tool requirements

3. **Configure Installation**
   - Customize agent name
   - Select provider/model
   - Configure tools

4. **Install**
   - Accept terms
   - Complete installation
   - Test agent

### Installation Options

```yaml
Installation Configuration:
  Agent: Customer Support Pro

  Customization:
    Name: "Acme Support Agent"
    Description: "Support agent for Acme Corp"

  Provider:
    Primary: openai-production
    Model: gpt-4o
    Fallback: anthropic-production

  Tools:
    ✅ kb_search (your KB)
    ✅ ticket_system (configured)
    ⬜ customer_lookup (not configured)

  Access:
    Teams: support-team, customer-success

  Advanced:
    Temperature Override: 0.6
    Custom System Prompt Additions: [optional]
```

## Managing Installed Agents

### Installed Agents Dashboard

View and manage your installed agents:

| Agent | Version | Status | Usage | Actions |
|-------|---------|--------|-------|---------|
| Support Pro | 2.1.0 | Active | 1,234 | Configure, Update |
| Content Writer | 1.5.0 | Active | 456 | Configure, Update |
| Code Review | 3.0.0 | Paused | 89 | Configure, Resume |

### Agent Updates

```yaml
Update Available:
  Agent: Customer Support Pro
  Current: v2.0.0
  Available: v2.1.0

  Changes:
    - Improved sentiment detection
    - Added Spanish language support
    - Bug fixes for edge cases

  Options:
    [Update Now] [Schedule] [Skip]
```

### Customizing Agents

Modify installed agents:

```yaml
Customization Options:
  System Prompt:
    - View default prompt
    - Add custom instructions
    - Override sections

  Parameters:
    - Temperature
    - Max tokens
    - Response format

  Tools:
    - Enable/disable tools
    - Configure tool settings
    - Add custom tools

  Branding:
    - Agent name
    - Avatar/icon
    - Response style
```

## Publishing Agents

### Becoming a Publisher

Share your agents with the community:

1. **Create Quality Agent**
   - Thorough testing
   - Good documentation
   - Stable performance

2. **Prepare Listing**
   - Description and features
   - Requirements
   - Installation guide
   - Sample conversations

3. **Submit for Review**
   - Automated checks
   - Manual review
   - Security scan

4. **Publish**
   - Set visibility (public/private)
   - Set pricing (free/paid)
   - Monitor feedback

### Publisher Requirements

```yaml
Publisher Requirements:
  Account:
    - Professional plan or higher
    - Verified email
    - Active for 30+ days

  Agent:
    - Complete documentation
    - Tested with multiple providers
    - No policy violations
    - Reasonable resource usage

  Legal:
    - Accept publisher agreement
    - Confirm IP ownership
    - Agree to review process
```

### Agent Listing

```yaml
Listing Configuration:
  Name: My Custom Agent
  Category: Support

  Description:
    Short: "AI agent for SaaS customer support"
    Full: [Detailed markdown description]

  Features:
    - Multi-language support
    - Sentiment analysis
    - Automatic escalation

  Requirements:
    Provider: OpenAI (GPT-4) or Anthropic (Claude 3)
    Plan: Professional+
    Tools: optional

  Pricing:
    Type: free  # or paid

  Support:
    Documentation: [URL]
    Contact: support@yourcompany.com
```

## Best Practices

### Choosing Agents

1. **Match Your Needs**
   - Review features carefully
   - Check compatibility
   - Read user reviews

2. **Start with Verified**
   - Lower risk
   - Better support
   - Regular updates

3. **Test Before Production**
   - Use sandbox mode
   - Run test scenarios
   - Verify performance

### Customization

1. **Minimal Changes First**
   - Start with defaults
   - Add customization gradually
   - Document changes

2. **Test Thoroughly**
   - After any customization
   - With real scenarios
   - Monitor performance

### Publishing

1. **Quality First**
   - Extensive testing
   - Clear documentation
   - Responsive support

2. **Listen to Feedback**
   - Monitor reviews
   - Address issues promptly
   - Iterate and improve

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
- [AI Governance and Policies](/kb/ai-governance-policies)

---

Need help with the marketplace? Contact marketplace@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "agent-marketplace-guide") do |article|
  article.title = "Agent Marketplace Guide"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Browse, install, and manage pre-built AI agents from the marketplace, plus learn how to publish your own agents."
  article.content = agent_marketplace_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Agent Marketplace Guide"

# Article 27: DevOps AI Templates
devops_templates_content = <<~MARKDOWN
# DevOps AI Templates

Accelerate DevOps automation with pre-built AI workflow templates for common development and operations tasks.

## Templates Overview

### What Are DevOps AI Templates?

DevOps AI Templates provide:
- **Ready-to-use workflows** for common tasks
- **AI-powered automation** for DevOps processes
- **Customizable configurations** for your needs
- **Best practices** built-in

### Accessing Templates

Navigate to **AI > DevOps Templates** to:
- Browse available templates
- Preview configurations
- Deploy templates
- Customize for your needs

## Available Templates

### Code Review Automation

```yaml
Template: AI Code Review
Category: Development
Description: Automated code review for pull requests

Workflow:
  Trigger: Pull request opened/updated

  Steps:
    1. Fetch PR changes
    2. Analyze code with AI
    3. Generate review comments
    4. Check security issues
    5. Post review to PR

Features:
  - Language support: 15+ languages
  - Security vulnerability detection
  - Code quality suggestions
  - Performance recommendations
  - Documentation checks
```

### Incident Response

```yaml
Template: AI Incident Responder
Category: Operations
Description: Automated incident analysis and response

Workflow:
  Trigger: Alert from monitoring system

  Steps:
    1. Parse alert details
    2. Gather system context
    3. Analyze with AI
    4. Generate diagnosis
    5. Suggest remediation
    6. Create incident ticket
    7. Notify team

Features:
  - Multi-source log analysis
  - Pattern recognition
  - Historical comparison
  - Runbook suggestions
```

### Documentation Generator

```yaml
Template: API Documentation Generator
Category: Development
Description: Generate API docs from code

Workflow:
  Trigger: Code push to main branch

  Steps:
    1. Parse source files
    2. Extract API definitions
    3. Generate documentation
    4. Create examples
    5. Publish to docs site

Features:
  - OpenAPI/Swagger support
  - Example generation
  - Multi-language support
  - Version tracking
```

### Release Notes Generator

```yaml
Template: Release Notes Generator
Category: DevOps
Description: Generate release notes from commits

Workflow:
  Trigger: Tag created or release drafted

  Steps:
    1. Fetch commits since last release
    2. Categorize changes
    3. Generate summary with AI
    4. Format release notes
    5. Update changelog

Features:
  - Conventional commits support
  - Category grouping
  - Breaking change detection
  - Contributor attribution
```

### Security Scanner

```yaml
Template: AI Security Analyzer
Category: Security
Description: Security analysis for dependencies and code

Workflow:
  Trigger: Scheduled (daily) or PR opened

  Steps:
    1. Scan dependencies
    2. Check for vulnerabilities
    3. Analyze code patterns
    4. Generate security report
    5. Create issues for findings

Features:
  - CVE database lookup
  - SAST integration
  - Priority scoring
  - Remediation guidance
```

## Using Templates

### Deploying a Template

1. **Select Template**
   - Browse categories
   - Review template details
   - Check requirements

2. **Configure**
   - Set trigger conditions
   - Configure AI provider
   - Map to your repositories
   - Set notification channels

3. **Customize**
   - Modify prompts
   - Adjust thresholds
   - Add custom steps

4. **Deploy**
   - Test in sandbox
   - Enable for target repos
   - Monitor initial runs

### Template Configuration

```yaml
Deployment Configuration:
  Template: AI Code Review

  Trigger:
    Event: pull_request
    Actions: [opened, synchronize]
    Repositories:
      - org/repo-1
      - org/repo-2

  AI Configuration:
    Provider: openai-production
    Model: gpt-4o
    Temperature: 0.3

  Review Settings:
    Languages: [javascript, typescript, python]
    Check Security: true
    Check Performance: true
    Auto-approve: false

  Notifications:
    Post to PR: true
    Slack: #code-reviews
```

### Customizing Templates

Modify templates for your needs:

```yaml
Customization Options:
  System Prompt:
    # Add company-specific guidelines
    Additions: |
      Also check for:
      - Our internal coding standards
      - Required error handling patterns
      - Logging requirements

  Thresholds:
    Min Severity: medium
    Max Comments: 20
    Auto-approve Score: 95

  Integration:
    Jira Project: DEV
    Create Issues: true
    Labels: [ai-review, needs-attention]
```

## Template Categories

### Development

| Template | Purpose |
|----------|---------|
| Code Review | Automated PR review |
| Test Generator | Generate test cases |
| Refactor Suggestions | Code improvement |
| Documentation | Generate docs |
| Migration Helper | Code migration |

### Operations

| Template | Purpose |
|----------|---------|
| Incident Response | Alert analysis |
| Log Analyzer | Log parsing and insights |
| Capacity Planning | Resource forecasting |
| Runbook Generator | Create runbooks |
| Change Analyzer | Change risk assessment |

### Security

| Template | Purpose |
|----------|---------|
| Vulnerability Scanner | Security scanning |
| Secret Detection | Find exposed secrets |
| Compliance Checker | Policy compliance |
| Threat Analyzer | Security threats |
| Audit Reporter | Security reports |

### Release

| Template | Purpose |
|----------|---------|
| Release Notes | Generate notes |
| Changelog Builder | Update changelog |
| Version Bumper | Semantic versioning |
| Deployment Planner | Plan deployments |
| Rollback Advisor | Rollback decisions |

## Creating Custom Templates

### Template Structure

```yaml
Custom Template:
  metadata:
    name: My Custom Template
    description: Description of what it does
    category: development
    version: 1.0.0
    author: your-team

  requirements:
    provider: [openai, anthropic]
    tools: [git, github]
    permissions: [repo.read, issues.write]

  trigger:
    type: webhook
    events: [push, pull_request]

  workflow:
    nodes:
      - id: gather_context
        type: action
        action: fetch_changes

      - id: analyze
        type: agent
        agent: code-analyzer
        input:
          changes: "{{gather_context.output}}"

      - id: report
        type: action
        action: create_report
        input:
          analysis: "{{analyze.output}}"
```

### Publishing Templates

Share templates with your team or community:

1. **Develop and Test**
   - Build workflow
   - Test thoroughly
   - Document usage

2. **Package**
   - Export configuration
   - Include documentation
   - Add examples

3. **Publish**
   - Team library
   - Organization templates
   - Public marketplace (optional)

## Integration Examples

### GitHub Actions Integration

```yaml
# .github/workflows/ai-review.yml
name: AI Code Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Trigger Powernode AI Review
        run: |
          curl -X POST ${{ secrets.POWERNODE_WEBHOOK }} \\
            -H "Content-Type: application/json" \\
            -d '{
              "event": "pull_request",
              "repository": "${{ github.repository }}",
              "pr_number": ${{ github.event.number }}
            }'
```

### GitLab CI Integration

```yaml
# .gitlab-ci.yml
ai-review:
  stage: review
  script:
    - |
      curl -X POST $POWERNODE_WEBHOOK \\
        -H "Content-Type: application/json" \\
        -d "{
          \\"event\\": \\"merge_request\\",
          \\"project_id\\": \\"$CI_PROJECT_ID\\",
          \\"mr_iid\\": \\"$CI_MERGE_REQUEST_IID\\"
        }"
  only:
    - merge_requests
```

## Best Practices

### Template Selection

1. **Match Your Needs**
   - Review features
   - Check requirements
   - Consider customization needs

2. **Start Simple**
   - Begin with one template
   - Learn the patterns
   - Expand gradually

### Customization

1. **Incremental Changes**
   - Start with defaults
   - Add customizations gradually
   - Test each change

2. **Document Changes**
   - Record modifications
   - Explain rationale
   - Share with team

### Monitoring

1. **Track Performance**
   - Monitor execution times
   - Review AI outputs
   - Gather feedback

2. **Iterate**
   - Refine based on results
   - Update prompts
   - Improve automation

## Related Articles

- [AI Orchestration Overview](/kb/ai-orchestration-overview)
- [Building AI Workflows](/kb/building-ai-workflows)
- [DevOps Overview](/kb/devops-overview)

---

Need help with templates? Contact devops-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "devops-ai-templates") do |article|
  article.title = "DevOps AI Templates"
  article.category = ai_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Pre-built AI workflow templates for DevOps automation including code review, incident response, documentation generation, and security scanning."
  article.content = devops_templates_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ DevOps AI Templates"

puts "  ✅ AI Orchestration articles created (13 articles)"
