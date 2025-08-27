# Automated MCP Specialist Delegation Configuration

## Overview

This configuration enables automatic delegation to appropriate MCP specialists based on task analysis, keywords, file patterns, and context. The platform architect will proactively route tasks to specialists while maintaining architectural oversight.

## Delegation Rules & Triggers

### 1. Backend Development Tasks

#### Rails Architect (`rails_architect`)
**Trigger Conditions:**
- **Keywords**: "Rails", "API endpoint", "controller", "middleware", "authentication", "JWT", "routes", "Rails server", "API design"
- **File Patterns**: `server/app/controllers/`, `server/config/routes.rb`, `server/config/application.rb`
- **Task Types**: API architecture, Rails configuration, authentication setup, middleware configuration
- **Examples**: "Create user authentication API", "Set up JWT middleware", "Design RESTful endpoints"

```markdown
**Auto-Delegation Trigger:**
When user requests involve Rails API development, authentication systems, or backend architecture decisions.
```

#### Data Modeler (`data_modeler`)
**Trigger Conditions:**
- **Keywords**: "database", "model", "migration", "ActiveRecord", "schema", "associations", "PostgreSQL", "database design"
- **File Patterns**: `server/db/migrate/`, `server/app/models/`, `server/db/schema.rb`, `server/db/seeds.rb`
- **Task Types**: Database schema design, model relationships, migrations, data modeling
- **Examples**: "Create subscription model", "Design billing relationships", "Add database indexes"

```markdown
**Auto-Delegation Trigger:**
When user requests involve database schema changes, model creation, or data relationship design.
```

#### API Developer (`api_developer`)
**Trigger Conditions:**
- **Keywords**: "API endpoint", "REST", "JSON", "serialization", "API response", "API documentation", "endpoint"
- **File Patterns**: `server/app/controllers/api/`, serializer files, API specs
- **Task Types**: API endpoint implementation, serialization, response formatting, API optimization
- **Examples**: "Create subscription API endpoints", "Add pagination to API", "Fix API response format"

```markdown
**Auto-Delegation Trigger:**
When user requests focus on API endpoint creation, modification, or optimization.
```

#### Background Job Engineer (`background_job_engineer`)
**Trigger Conditions:**
- **Keywords**: "background job", "Sidekiq", "queue", "worker", "async", "job", "scheduled", "cron"
- **File Patterns**: `worker/app/jobs/`, `server/app/jobs/`, Sidekiq configuration
- **Task Types**: Background job creation, queue management, scheduled tasks, worker optimization
- **Examples**: "Create email notification job", "Set up recurring billing job", "Fix job queue issues"

```markdown
**Auto-Delegation Trigger:**
When user requests involve background processing, job queues, or asynchronous task management.
```

#### Payment Integration Specialist (`payment_integration_specialist`)
**Trigger Conditions:**
- **Keywords**: "payment", "Stripe", "PayPal", "billing", "subscription", "webhook", "payment method", "invoice"
- **File Patterns**: Payment-related models, payment controllers, webhook handlers
- **Task Types**: Payment gateway integration, webhook handling, payment processing, billing automation
- **Examples**: "Integrate Stripe webhooks", "Add PayPal support", "Fix payment processing"

```markdown
**Auto-Delegation Trigger:**
When user requests involve payment processing, billing systems, or payment gateway integration.
```

#### Billing Engine Developer (`billing_engine_developer`)
**Trigger Conditions:**
- **Keywords**: "subscription lifecycle", "billing cycle", "proration", "renewal", "billing logic", "plan management"
- **File Patterns**: Subscription models, billing controllers, plan management
- **Task Types**: Subscription management, billing logic, plan creation, billing automation
- **Examples**: "Implement subscription proration", "Create billing cycle logic", "Add plan upgrade flow"

```markdown
**Auto-Delegation Trigger:**
When user requests involve complex billing logic, subscription lifecycle management, or plan operations.
```

### 2. Frontend Development Tasks

#### React Architect (`react_architect`)
**Trigger Conditions:**
- **Keywords**: "React", "component architecture", "routing", "state management", "TypeScript", "React server", "frontend architecture"
- **File Patterns**: `frontend/src/`, React components, routing files, state management
- **Task Types**: Component architecture, routing setup, state management, React optimization
- **Examples**: "Set up React routing", "Implement global state", "Fix component structure"

```markdown
**Auto-Delegation Trigger:**
When user requests involve React architecture, component organization, or frontend system design.
```

#### UI Component Developer (`ui_component_developer`)
**Trigger Conditions:**
- **Keywords**: "component", "UI", "design system", "theme", "styling", "responsive", "accessibility", "UX"
- **File Patterns**: `frontend/src/shared/components/`, styling files, UI components
- **Task Types**: UI component creation, design system implementation, styling, responsive design
- **Examples**: "Create dashboard components", "Fix responsive design", "Implement design tokens"

```markdown
**Auto-Delegation Trigger:**
When user requests involve UI component creation, styling, or design system work.
```

#### Dashboard Specialist (`dashboard_specialist`)
**Trigger Conditions:**
- **Keywords**: "dashboard", "analytics", "charts", "metrics", "visualization", "reporting", "KPI"
- **File Patterns**: Analytics components, dashboard pages, chart components
- **Task Types**: Dashboard development, data visualization, analytics interfaces, reporting features
- **Examples**: "Create analytics dashboard", "Add revenue charts", "Build metrics overview"

```markdown
**Auto-Delegation Trigger:**
When user requests involve dashboard creation, data visualization, or analytics interfaces.
```

#### Admin Panel Developer (`admin_panel_developer`)
**Trigger Conditions:**
- **Keywords**: "admin", "administration", "management panel", "system management", "admin interface"
- **File Patterns**: Admin-related components, management interfaces, admin pages
- **Task Types**: Admin interface development, system management tools, administrative features
- **Examples**: "Create user management interface", "Build admin settings", "Add system monitoring"

```markdown
**Auto-Delegation Trigger:**
When user requests involve administrative interfaces or system management features.
```

### 3. Testing Tasks

#### Backend Test Engineer (`backend_test_engineer`)
**Trigger Conditions:**
- **Keywords**: "RSpec", "API test", "backend test", "integration test", "model test", "controller test"
- **File Patterns**: `server/spec/`, test files, RSpec configurations
- **Task Types**: Backend testing, API testing, model testing, integration testing
- **Examples**: "Write API tests", "Add model validation tests", "Create integration tests"

```markdown
**Auto-Delegation Trigger:**
When user requests involve backend testing, API testing, or Rails application testing.
```

#### Frontend Test Engineer (`frontend_test_engineer`)
**Trigger Conditions:**
- **Keywords**: "Jest", "Cypress", "component test", "frontend test", "E2E test", "unit test"
- **File Patterns**: `frontend/src/**/*.test.ts`, `frontend/cypress/`, test configurations
- **Task Types**: Frontend testing, component testing, E2E testing, test automation
- **Examples**: "Write component tests", "Add E2E tests", "Fix test failures"

```markdown
**Auto-Delegation Trigger:**
When user requests involve frontend testing, component testing, or test automation.
```

### 4. Infrastructure & Operations Tasks

#### DevOps Engineer (`devops_engineer`)
**Trigger Conditions:**
- **Keywords**: "deployment", "CI/CD", "Docker", "infrastructure", "monitoring", "production", "environment", "service restart", "build"
- **File Patterns**: `.github/workflows/`, Docker files, deployment scripts, infrastructure configs
- **Task Types**: Deployment automation, CI/CD setup, infrastructure management, monitoring setup
- **Examples**: "Set up CI/CD pipeline", "Deploy to production", "Fix deployment issues", "Restart services"

```markdown
**Auto-Delegation Trigger:**
When user requests involve deployment, infrastructure, CI/CD, or production environment management.
```

#### Security Specialist (`security_specialist`)
**Trigger Conditions:**
- **Keywords**: "security", "vulnerability", "authentication", "authorization", "encryption", "SSL", "PCI compliance"
- **File Patterns**: Security configurations, authentication files, security middleware
- **Task Types**: Security audits, vulnerability fixes, compliance implementation, security configuration
- **Examples**: "Security audit", "Fix authentication vulnerability", "Implement PCI compliance"

```markdown
**Auto-Delegation Trigger:**
When user requests involve security concerns, compliance, or authentication issues.
```

#### Performance Optimizer (`performance_optimizer`)
**Trigger Conditions:**
- **Keywords**: "performance", "optimization", "slow", "bottleneck", "memory", "CPU", "database performance", "caching"
- **File Patterns**: Performance-related configurations, caching setups, optimization code
- **Task Types**: Performance analysis, optimization implementation, bottleneck resolution, caching strategies
- **Examples**: "Fix slow API responses", "Optimize database queries", "Implement caching"

```markdown
**Auto-Delegation Trigger:**
When user requests involve performance issues, optimization needs, or system bottlenecks.
```

### 5. Service & Communication Tasks

#### Notification Engineer (`notification_engineer`)
**Trigger Conditions:**
- **Keywords**: "notification", "email", "SMS", "push notification", "alert", "messaging", "communication"
- **File Patterns**: Notification-related files, email templates, messaging configurations
- **Task Types**: Notification system setup, email/SMS integration, alert configuration, messaging features
- **Examples**: "Set up email notifications", "Add SMS alerts", "Create push notifications"

```markdown
**Auto-Delegation Trigger:**
When user requests involve notification systems, messaging, or communication features.
```

#### Documentation Specialist (`documentation_specialist`)
**Trigger Conditions:**
- **Keywords**: "documentation", "docs", "README", "API docs", "guide", "tutorial", "help", "knowledge base"
- **File Patterns**: Documentation files, README files, API documentation, help content
- **Task Types**: Documentation creation, API documentation, user guides, knowledge base content
- **Examples**: "Update API documentation", "Create user guide", "Write technical docs"

```markdown
**Auto-Delegation Trigger:**
When user requests involve documentation creation, updates, or knowledge base content.
```

#### Analytics Engineer (`analytics_engineer`)
**Trigger Conditions:**
- **Keywords**: "analytics", "metrics", "KPI", "business intelligence", "reporting", "data analysis", "insights"
- **File Patterns**: Analytics-related files, reporting features, metrics implementations
- **Task Types**: Analytics implementation, KPI tracking, business intelligence features, reporting systems
- **Examples**: "Implement user analytics", "Create business reports", "Add KPI tracking"

```markdown
**Auto-Delegation Trigger:**
When user requests involve business analytics, KPI tracking, or business intelligence features.
```

## Delegation Decision Matrix

### High Priority Auto-Delegation (Immediate)
Tasks that should be **immediately delegated** without question:

1. **Service Management Issues** → DevOps Engineer
2. **Database Schema Changes** → Data Modeler
3. **Payment Integration** → Payment Integration Specialist
4. **Security Vulnerabilities** → Security Specialist
5. **Performance Bottlenecks** → Performance Optimizer

### Medium Priority Auto-Delegation (With Context)
Tasks that should be **delegated with brief context**:

1. **API Development** → API Developer (with requirements summary)
2. **UI Component Work** → UI Component Developer (with design requirements)
3. **Testing Tasks** → Respective Test Engineers (with scope definition)
4. **Background Jobs** → Background Job Engineer (with job specifications)

### Low Priority Auto-Delegation (User Choice)
Tasks that should **offer delegation** as an option:

1. **Documentation Updates** → Documentation Specialist
2. **Analytics Features** → Analytics Engineer
3. **Admin Interface** → Admin Panel Developer

## Implementation Strategy

### Phase 1: Proactive Pattern Recognition
```javascript
// Pseudo-code for delegation logic
const shouldDelegate = (userMessage, currentContext) => {
  const keywords = extractKeywords(userMessage);
  const filePaths = extractFilePaths(currentContext);
  const taskType = classifyTask(userMessage);
  
  // Check for high-priority immediate delegation
  for (const rule of HIGH_PRIORITY_RULES) {
    if (matchesRule(rule, keywords, filePaths, taskType)) {
      return { delegate: true, specialist: rule.specialist, priority: 'high' };
    }
  }
  
  // Check for medium-priority contextual delegation
  for (const rule of MEDIUM_PRIORITY_RULES) {
    if (matchesRule(rule, keywords, filePaths, taskType)) {
      return { delegate: true, specialist: rule.specialist, priority: 'medium', needsContext: true };
    }
  }
  
  // Check for low-priority optional delegation
  for (const rule of LOW_PRIORITY_RULES) {
    if (matchesRule(rule, keywords, filePaths, taskType)) {
      return { delegate: false, suggestSpecialist: rule.specialist, priority: 'low' };
    }
  }
  
  return { delegate: false };
};
```

### Phase 2: Delegation Execution Patterns

#### Immediate Delegation (High Priority)
```markdown
I'm delegating this [task type] to our [Specialist Name] who specializes in [area]. 
They have comprehensive expertise in [specific domain] and will handle this efficiently.
```

#### Contextual Delegation (Medium Priority)  
```markdown
This [task type] aligns perfectly with our [Specialist Name]'s expertise. 
Let me delegate this to them with the context that [brief summary of requirements].
```

#### Suggested Delegation (Low Priority)
```markdown
I can handle this [task], or would you prefer me to delegate to our [Specialist Name] 
who specializes in [area]? They might provide more specialized insights.
```

### Phase 3: Coordination and Oversight

#### Delegation Coordination
1. **Task Handoff**: Clear specification of requirements and expected deliverables
2. **Progress Monitoring**: Regular check-ins on delegated work
3. **Integration Review**: Ensure specialist work aligns with overall architecture
4. **Quality Assurance**: Review specialist deliverables for platform coherence

#### Architecture Coherence
- Maintain oversight of all specialist work
- Ensure cross-component integration remains intact
- Coordinate between multiple specialists when tasks overlap
- Final review and approval of all architectural decisions

## Usage Examples

### Example 1: Database Schema Request
**User**: "Add a new subscription tier model with pricing options"

**Auto-Delegation Response**:
```markdown
I'm delegating this database modeling task to our Data Modeler specialist who will:
1. Design the subscription tier model with proper associations
2. Create the migration with UUID strategy
3. Set up model validations and relationships
4. Ensure integration with existing billing system

*Delegating to Data Modeler...*
```

### Example 2: Performance Issue
**User**: "The analytics page is loading very slowly"

**Auto-Delegation Response**:
```markdown
This performance issue requires specialized analysis. I'm immediately delegating to our Performance Optimizer who will:
1. Analyze the analytics page performance bottlenecks
2. Identify database query optimization opportunities  
3. Implement caching strategies if needed
4. Provide performance improvement recommendations

*Delegating to Performance Optimizer...*
```

### Example 3: UI Component Request
**User**: "Create a new dashboard widget for subscription metrics"

**Auto-Delegation Response**:
```markdown
This UI component work aligns perfectly with our Dashboard Specialist's expertise. I'm delegating this to them with the context that we need a subscription metrics widget that:
- Follows our design system standards
- Integrates with existing analytics data
- Maintains responsive design principles

*Delegating to Dashboard Specialist...*
```

## Benefits of Automated Delegation

### For Users
- **Faster Resolution**: Tasks routed to most qualified specialist immediately
- **Higher Quality**: Specialists provide deep domain expertise
- **Comprehensive Solutions**: Specialists consider all domain-specific requirements
- **Consistent Patterns**: All specialists follow established platform standards

### For Development
- **Specialized Expertise**: Each area handled by domain experts
- **Parallel Processing**: Multiple specialists can work simultaneously
- **Knowledge Consistency**: Specialists maintain up-to-date domain knowledge
- **Quality Assurance**: Specialists ensure domain-specific best practices

### For Platform Architecture
- **Architectural Coherence**: Platform architect maintains oversight and integration
- **Scalable Development**: Specialists handle complexity while maintaining standards
- **Documentation Consistency**: All specialists follow documented patterns
- **Cross-Component Integration**: Coordinated approach ensures system coherence

This automated delegation system ensures that every task is handled by the most qualified specialist while maintaining overall architectural coherence and platform standards.