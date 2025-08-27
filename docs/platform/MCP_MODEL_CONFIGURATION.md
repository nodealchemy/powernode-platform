# MCP Specialist Claude Model Configuration

## Model Selection Strategy

Each MCP specialist requires different levels of computational complexity, reasoning depth, and domain expertise. This configuration optimizes model assignments for performance, cost-effectiveness, and quality outcomes.

## Available Claude Models & Capabilities

### Claude-3.5-Sonnet (Current Default)
- **Strengths**: Balanced performance, code generation, complex reasoning
- **Best For**: General development tasks, architectural decisions, complex integrations
- **Use Cases**: Multi-step planning, code architecture, system design

### Claude-3-Haiku  
- **Strengths**: Fast response, cost-effective, good for routine tasks
- **Best For**: Simple code generation, documentation, straightforward implementations
- **Use Cases**: CRUD operations, basic configurations, simple fixes

### Claude-3-Opus
- **Strengths**: Highest reasoning capability, complex problem solving
- **Best For**: Architecture design, complex debugging, system optimization
- **Use Cases**: Performance analysis, complex integrations, strategic decisions

## Specialist Model Assignments

### 🏗️ Architecture & System Design (Opus/Sonnet)

#### Rails Architect → **Claude-3.5-Sonnet**
**Reasoning**: Requires deep understanding of Rails conventions, API design patterns, and system architecture decisions.
- **Complexity**: High - System architecture, security patterns, middleware design
- **Context**: Large codebase understanding, pattern recognition
- **Output**: Complex Rails configurations, architectural decisions
- **Thinking Budget**: "think harder" for complex architectural decisions

#### React Architect → **Claude-3.5-Sonnet** 
**Reasoning**: Needs comprehensive understanding of React patterns, TypeScript, and frontend architecture.
- **Complexity**: High - Component architecture, state management, routing systems
- **Context**: Modern React patterns, performance optimization
- **Output**: Architectural decisions, complex component hierarchies
- **Thinking Budget**: "think harder" for architectural planning

#### DevOps Engineer → **Claude-3-Opus**
**Reasoning**: Requires highest level of systems thinking, infrastructure optimization, and production troubleshooting.
- **Complexity**: Very High - Infrastructure as code, deployment pipelines, system optimization
- **Context**: Multi-service architecture, production environments
- **Output**: Complex deployment strategies, infrastructure automation
- **Thinking Budget**: "ultrathink" for production deployments and optimization

### 🔧 Implementation Specialists (Sonnet/Haiku)

#### API Developer → **Claude-3.5-Sonnet**
**Reasoning**: Needs solid understanding of RESTful design, serialization patterns, and API optimization.
- **Complexity**: Medium-High - API design patterns, serialization, performance
- **Context**: API standards, integration patterns
- **Output**: Well-structured endpoints, proper error handling
- **Thinking Budget**: "think hard" for complex API integrations

#### UI Component Developer → **Claude-3-Haiku**
**Reasoning**: Often handles routine component creation following established patterns.
- **Complexity**: Medium - Component creation, styling, responsive design
- **Context**: Design system, component patterns
- **Output**: React components, styling implementations
- **Thinking Budget**: "think" for standard components, "think hard" for complex interactions

#### Background Job Engineer → **Claude-3.5-Sonnet**
**Reasoning**: Requires understanding of async patterns, queue management, and system integration.
- **Complexity**: Medium-High - Job patterns, queue optimization, error handling
- **Context**: Sidekiq patterns, system integration
- **Output**: Robust job implementations, queue configurations
- **Thinking Budget**: "think hard" for complex job orchestration

### 💾 Data & Business Logic (Sonnet/Opus)

#### Data Modeler → **Claude-3.5-Sonnet**
**Reasoning**: Needs deep understanding of database design, relationships, and data integrity.
- **Complexity**: High - Database design, complex relationships, performance
- **Context**: ActiveRecord patterns, database optimization
- **Output**: Well-designed schemas, optimized queries
- **Thinking Budget**: "think harder" for complex data modeling

#### Payment Integration Specialist → **Claude-3-Opus**
**Reasoning**: Handles mission-critical payment processing requiring highest reliability and security awareness.
- **Complexity**: Very High - Payment processing, PCI compliance, financial regulations
- **Context**: Payment gateways, compliance requirements, financial accuracy
- **Output**: Secure payment integrations, compliant implementations  
- **Thinking Budget**: "ultrathink" for payment security and compliance

#### Billing Engine Developer → **Claude-3-Opus**
**Reasoning**: Complex business logic, financial calculations, and subscription lifecycle management.
- **Complexity**: Very High - Complex billing logic, proration, subscription lifecycles
- **Context**: Financial calculations, business rules, compliance
- **Output**: Accurate billing systems, complex proration logic
- **Thinking Budget**: "ultrathink" for billing logic accuracy

### 📊 Analytics & Reporting (Sonnet/Opus)

#### Dashboard Specialist → **Claude-3.5-Sonnet**
**Reasoning**: Requires understanding of data visualization, user experience, and performance optimization.
- **Complexity**: Medium-High - Data visualization, interactive components, performance
- **Context**: Chart libraries, data processing, user experience
- **Output**: Interactive dashboards, optimized visualizations
- **Thinking Budget**: "think hard" for complex data visualizations

#### Analytics Engineer → **Claude-3-Opus**
**Reasoning**: Complex data analysis, business intelligence, and statistical reasoning required.
- **Complexity**: Very High - Statistical analysis, business intelligence, data modeling
- **Context**: Business metrics, statistical methods, data science
- **Output**: Sophisticated analytics systems, business insights
- **Thinking Budget**: "ultrathink" for complex analytics and business intelligence

#### Performance Optimizer → **Claude-3-Opus**
**Reasoning**: Requires deep system analysis, bottleneck identification, and optimization strategies.
- **Complexity**: Very High - Performance analysis, system optimization, bottleneck resolution
- **Context**: System performance, database optimization, caching strategies
- **Output**: Performance improvements, optimization strategies
- **Thinking Budget**: "ultrathink" for performance optimization

### 🔒 Security & Compliance (Opus)

#### Security Specialist → **Claude-3-Opus**
**Reasoning**: Security requires highest level of reasoning for threat analysis and vulnerability assessment.
- **Complexity**: Very High - Security analysis, vulnerability assessment, compliance
- **Context**: Security best practices, threat models, compliance requirements
- **Output**: Security implementations, vulnerability fixes
- **Thinking Budget**: "ultrathink" for security analysis and compliance

### 🧪 Testing & Quality (Sonnet/Haiku)

#### Backend Test Engineer → **Claude-3.5-Sonnet**
**Reasoning**: Needs understanding of testing patterns, integration complexity, and quality assurance.
- **Complexity**: Medium-High - Test strategy, integration testing, quality patterns
- **Context**: RSpec patterns, API testing, integration complexity
- **Output**: Comprehensive test suites, quality assurance
- **Thinking Budget**: "think hard" for complex integration testing

#### Frontend Test Engineer → **Claude-3-Haiku**
**Reasoning**: Often handles routine component testing following established patterns.
- **Complexity**: Medium - Component testing, E2E testing, test automation
- **Context**: Jest/Cypress patterns, testing best practices
- **Output**: Component tests, E2E test suites
- **Thinking Budget**: "think" for routine tests, "think hard" for complex E2E scenarios

### 📝 Content & Communication (Haiku/Sonnet)

#### Documentation Specialist → **Claude-3-Haiku**
**Reasoning**: Documentation often follows established patterns and doesn't require complex reasoning.
- **Complexity**: Low-Medium - Documentation creation, technical writing
- **Context**: Documentation standards, technical communication
- **Output**: Clear documentation, user guides
- **Thinking Budget**: "think" for standard documentation

#### Notification Engineer → **Claude-3.5-Sonnet**
**Reasoning**: Requires understanding of communication patterns, integration complexity, and user experience.
- **Complexity**: Medium-High - Communication systems, integration patterns, user experience
- **Context**: Notification patterns, messaging systems, user workflows
- **Output**: Notification systems, communication workflows
- **Thinking Budget**: "think hard" for complex notification workflows

#### Admin Panel Developer → **Claude-3.5-Sonnet**
**Reasoning**: Requires understanding of complex admin workflows, permissions, and system management.
- **Complexity**: Medium-High - Admin interfaces, complex permissions, system management
- **Context**: Admin patterns, permission systems, management workflows
- **Output**: Administrative interfaces, management systems
- **Thinking Budget**: "think hard" for complex admin systems

## Model Configuration Implementation

### Configuration Commands

Each specialist can be configured with specific model and thinking budget settings:

```bash
# High Complexity Specialists (Opus + ultrathink)
mcp__devops_engineer__task --thinking_budget "ultrathink" --model "claude-3-opus"
mcp__payment_integration_specialist__task --thinking_budget "ultrathink" --model "claude-3-opus"
mcp__billing_engine_developer__task --thinking_budget "ultrathink" --model "claude-3-opus"
mcp__analytics_engineer__task --thinking_budget "ultrathink" --model "claude-3-opus"
mcp__performance_optimizer__task --thinking_budget "ultrathink" --model "claude-3-opus"
mcp__security_specialist__task --thinking_budget "ultrathink" --model "claude-3-opus"

# Medium-High Complexity (Sonnet + think harder)
mcp__rails_architect__task --thinking_budget "think harder" --model "claude-3.5-sonnet"
mcp__react_architect__task --thinking_budget "think harder" --model "claude-3.5-sonnet"
mcp__data_modeler__task --thinking_budget "think harder" --model "claude-3.5-sonnet"
mcp__api_developer__task --thinking_budget "think hard" --model "claude-3.5-sonnet"
mcp__background_job_engineer__task --thinking_budget "think hard" --model "claude-3.5-sonnet"
mcp__dashboard_specialist__task --thinking_budget "think hard" --model "claude-3.5-sonnet"
mcp__backend_test_engineer__task --thinking_budget "think hard" --model "claude-3.5-sonnet"
mcp__notification_engineer__task --thinking_budget "think hard" --model "claude-3.5-sonnet"
mcp__admin_panel_developer__task --thinking_budget "think hard" --model "claude-3.5-sonnet"

# Standard Complexity (Haiku + think)
mcp__ui_component_developer__task --thinking_budget "think" --model "claude-3-haiku"
mcp__frontend_test_engineer__task --thinking_budget "think" --model "claude-3-haiku"
mcp__documentation_specialist__task --thinking_budget "think" --model "claude-3-haiku"
```

### Dynamic Model Selection

For specialists that handle varying complexity:

```markdown
**UI Component Developer**:
- Simple components → Claude-3-Haiku + "think"
- Complex interactive components → Claude-3.5-Sonnet + "think hard"

**Frontend Test Engineer**:
- Unit tests → Claude-3-Haiku + "think" 
- Complex E2E scenarios → Claude-3.5-Sonnet + "think hard"

**Documentation Specialist**:
- Standard docs → Claude-3-Haiku + "think"
- Complex technical architecture docs → Claude-3.5-Sonnet + "think hard"
```

## Cost-Performance Optimization

### Model Usage Guidelines

**Claude-3-Opus (Premium)**
- Use for: Mission-critical systems (payments, security, performance, infrastructure)
- Reasoning: Highest quality needed for business-critical operations
- Cost: Highest, but justified by critical nature

**Claude-3.5-Sonnet (Balanced)**  
- Use for: Core development work requiring architectural thinking
- Reasoning: Best balance of capability and cost for complex development
- Cost: Moderate, optimal for most development tasks

**Claude-3-Haiku (Efficient)**
- Use for: Routine tasks following established patterns
- Reasoning: Fast and cost-effective for straightforward implementations
- Cost: Lowest, ideal for high-volume routine tasks

### Thinking Budget Optimization

**"ultrathink"** - Reserved for:
- Production deployments and infrastructure changes
- Payment processing and financial calculations
- Security vulnerability analysis
- Complex performance optimization
- Business-critical decision making

**"think harder"** - Used for:
- Architectural decisions and system design
- Complex data modeling and relationships
- Integration planning and API design
- Advanced testing scenarios

**"think hard"** - Applied to:
- Feature implementation with complexity
- Component architecture decisions
- Integration development
- Quality assurance planning

**"think"** - Standard for:
- Routine development tasks
- Standard component creation
- Basic documentation
- Simple configurations

## Implementation Strategy

### Phase 1: Core Specialist Configuration
Configure high-impact specialists first:
1. DevOps Engineer (Opus + ultrathink)
2. Security Specialist (Opus + ultrathink)  
3. Payment Integration Specialist (Opus + ultrathink)
4. Rails Architect (Sonnet + think harder)
5. React Architect (Sonnet + think harder)

### Phase 2: Specialized Domain Configuration  
Configure domain-specific specialists:
1. Data Modeler (Sonnet + think harder)
2. Performance Optimizer (Opus + ultrathink)
3. Analytics Engineer (Opus + ultrathink)
4. API Developer (Sonnet + think hard)
5. Background Job Engineer (Sonnet + think hard)

### Phase 3: Support Specialist Configuration
Configure support and routine specialists:
1. UI Component Developer (Haiku + think)
2. Frontend Test Engineer (Haiku + think)
3. Documentation Specialist (Haiku + think)
4. Backend Test Engineer (Sonnet + think hard)

### Configuration Validation

Test each specialist configuration with sample tasks:
- Verify appropriate model selection for task complexity
- Confirm thinking budget matches reasoning requirements
- Validate output quality meets domain standards
- Ensure cost-effectiveness for task volume

This model configuration ensures optimal performance, quality, and cost-effectiveness across all MCP specialists while maintaining the highest standards for business-critical operations.