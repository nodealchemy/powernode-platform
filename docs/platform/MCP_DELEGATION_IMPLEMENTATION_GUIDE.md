# MCP Delegation Implementation Guide

## Quick Delegation Decision Tree

This guide provides practical patterns for automatic delegation based on user requests. As the platform architect, I will use these patterns to proactively delegate appropriate tasks to specialists.

## Immediate Delegation Triggers (Auto-Execute)

### 🚨 Critical Infrastructure Tasks
**Pattern**: Service management, deployment, infrastructure issues
**Keywords**: "restart services", "deploy", "CI/CD", "production", "server down", "build failed"
**Action**: Immediately delegate to DevOps Engineer
**Template**:
```markdown
I'm immediately delegating this infrastructure task to our DevOps Engineer specialist who has expertise in service management, deployment automation, and production environment handling.

*Delegating to DevOps Engineer with task: [brief description]*
```

### 🔒 Security & Compliance Tasks
**Pattern**: Security vulnerabilities, authentication issues, compliance
**Keywords**: "security", "vulnerability", "authentication", "PCI compliance", "breach", "unauthorized"
**Action**: Immediately delegate to Security Specialist
**Template**:
```markdown
This security-related task requires specialized expertise. I'm delegating to our Security Specialist who handles all authentication, compliance, and vulnerability management.

*Delegating to Security Specialist with task: [brief description]*
```

### 💾 Database Schema Tasks
**Pattern**: Model creation, migrations, database design
**Keywords**: "model", "migration", "database", "schema", "ActiveRecord", "association"
**Action**: Immediately delegate to Data Modeler
**Template**:
```markdown
I'm delegating this database modeling task to our Data Modeler specialist who will ensure proper schema design, UUID strategy compliance, and integration with existing models.

*Delegating to Data Modeler with task: [brief description]*
```

### 💳 Payment Integration Tasks
**Pattern**: Payment processing, billing, Stripe/PayPal integration
**Keywords**: "payment", "Stripe", "PayPal", "billing", "subscription", "webhook", "invoice"
**Action**: Immediately delegate to Payment Integration Specialist
**Template**:
```markdown
I'm delegating this payment-related task to our Payment Integration Specialist who has deep expertise in Stripe, PayPal, webhook handling, and PCI compliance.

*Delegating to Payment Integration Specialist with task: [brief description]*
```

### ⚡ Performance Issues
**Pattern**: Performance problems, optimization needs, bottlenecks
**Keywords**: "slow", "performance", "bottleneck", "optimize", "memory", "CPU", "timeout"
**Action**: Immediately delegate to Performance Optimizer
**Template**:
```markdown
This performance issue requires specialized analysis. I'm delegating to our Performance Optimizer who will identify bottlenecks, optimize queries, and implement caching strategies.

*Delegating to Performance Optimizer with task: [brief description]*
```

## Contextual Delegation (Provide Context + Delegate)

### 🏗️ Rails API Development
**Pattern**: API endpoints, controllers, Rails configuration
**Keywords**: "API endpoint", "controller", "Rails", "REST", "authentication", "middleware"
**Action**: Delegate to Rails Architect with context
**Template**:
```markdown
This Rails API development aligns with our Rails Architect's expertise. I'm delegating this with the context that we need [specific requirements] following our established API patterns.

*Delegating to Rails Architect...*
```

### 🎯 Specific API Implementation
**Pattern**: Endpoint creation, serialization, API optimization
**Keywords**: "API", "endpoint", "JSON", "serialization", "REST", "pagination"
**Action**: Delegate to API Developer with requirements
**Template**:
```markdown
I'm delegating this API development to our API Developer specialist who will ensure proper serialization, error handling, and integration with our existing API architecture.

*Delegating to API Developer...*
```

### ⚙️ Background Processing
**Pattern**: Job creation, queue management, async tasks
**Keywords**: "background job", "Sidekiq", "queue", "worker", "async", "scheduled"
**Action**: Delegate to Background Job Engineer with specifications
**Template**:
```markdown
This background processing task is perfect for our Background Job Engineer who will implement the job following our BaseJob patterns and API-only communication standards.

*Delegating to Background Job Engineer...*
```

### ⚛️ React Architecture
**Pattern**: Component architecture, routing, state management
**Keywords**: "React", "component", "routing", "state", "TypeScript", "architecture"
**Action**: Delegate to React Architect with requirements
**Template**:
```markdown
I'm delegating this React development to our React Architect who will ensure proper component architecture, TypeScript integration, and adherence to our established patterns.

*Delegating to React Architect...*
```

### 🎨 UI Component Development
**Pattern**: Component creation, styling, design system
**Keywords**: "component", "UI", "styling", "design system", "responsive", "theme"
**Action**: Delegate to UI Component Developer with design requirements
**Template**:
```markdown
This UI component work aligns with our UI Component Developer's expertise. I'm delegating this with our design system requirements and theme-aware styling standards.

*Delegating to UI Component Developer...*
```

### 📊 Dashboard & Analytics
**Pattern**: Dashboard creation, data visualization, metrics
**Keywords**: "dashboard", "analytics", "chart", "metrics", "visualization", "KPI"
**Action**: Delegate to Dashboard Specialist with data requirements
**Template**:
```markdown
I'm delegating this dashboard development to our Dashboard Specialist who will create interactive visualizations following our analytics architecture patterns.

*Delegating to Dashboard Specialist...*
```

### 🔧 Admin Interfaces
**Pattern**: Admin panels, management interfaces, system administration
**Keywords**: "admin", "management", "administration", "admin panel", "system management"
**Action**: Delegate to Admin Panel Developer with requirements
**Template**:
```markdown
This administrative interface development is perfect for our Admin Panel Developer who specializes in management interfaces and system administration features.

*Delegating to Admin Panel Developer...*
```

## Testing Tasks Delegation

### 🧪 Backend Testing
**Pattern**: API tests, model tests, integration tests
**Keywords**: "RSpec", "test", "API test", "model test", "backend test"
**Action**: Delegate to Backend Test Engineer
**Template**:
```markdown
I'm delegating this testing task to our Backend Test Engineer who will create comprehensive tests following our RSpec patterns and API testing standards.

*Delegating to Backend Test Engineer...*
```

### 🔍 Frontend Testing
**Pattern**: Component tests, E2E tests, frontend testing
**Keywords**: "Jest", "Cypress", "component test", "E2E", "frontend test"
**Action**: Delegate to Frontend Test Engineer  
**Template**:
```markdown
This frontend testing task aligns with our Frontend Test Engineer's expertise in Jest, Cypress, and component testing strategies.

*Delegating to Frontend Test Engineer...*
```

## Service & Support Delegation

### 📢 Notification Systems
**Pattern**: Email, SMS, push notifications, alerts
**Keywords**: "notification", "email", "SMS", "alert", "messaging"
**Action**: Delegate to Notification Engineer
**Template**:
```markdown
I'm delegating this notification task to our Notification Engineer who handles all email, SMS, and real-time messaging systems.

*Delegating to Notification Engineer...*
```

### 📖 Documentation Tasks
**Pattern**: Documentation creation, API docs, user guides
**Keywords**: "documentation", "docs", "guide", "README", "API docs"
**Action**: Delegate to Documentation Specialist
**Template**:
```markdown
This documentation task is perfect for our Documentation Specialist who creates comprehensive guides and maintains all platform documentation.

*Delegating to Documentation Specialist...*
```

### 📈 Business Analytics
**Pattern**: Business intelligence, KPI tracking, reporting
**Keywords**: "analytics", "KPI", "business intelligence", "reporting", "insights"
**Action**: Delegate to Analytics Engineer
**Template**:
```markdown
I'm delegating this analytics task to our Analytics Engineer who specializes in business intelligence features and KPI tracking systems.

*Delegating to Analytics Engineer...*
```

## Complex Task Coordination

### Multi-Specialist Tasks
When tasks require multiple specialists:

1. **Identify Primary Specialist**: Who should lead the task?
2. **Identify Supporting Specialists**: Who else is needed?
3. **Define Integration Points**: How will the work be coordinated?
4. **Maintain Architecture Oversight**: Ensure coherence across specialists

**Template for Multi-Specialist Coordination**:
```markdown
This task requires coordination between multiple specialists. I'm delegating the primary work to [Primary Specialist] and will coordinate with [Supporting Specialists] for [specific aspects].

*Primary delegation to [Primary Specialist]...*
*Coordination with [Supporting Specialist] for [specific area]...*
```

## Delegation Execution Patterns

### Pattern 1: Immediate Technical Delegation
```markdown
I'm immediately delegating this [technical area] to our [Specialist Name] specialist who has comprehensive expertise in [domain area].

*Using Task tool to delegate: "[clear task description with requirements]"*
```

### Pattern 2: Contextual Business Delegation
```markdown
This [business area] work aligns perfectly with our [Specialist Name]'s expertise. I'm delegating this with the context that [business requirements and constraints].

*Using Task tool to delegate with context...*
```

### Pattern 3: Coordinated Multi-Specialist
```markdown
This complex task requires coordination between [Specialist A] for [area A] and [Specialist B] for [area B]. I'll delegate the primary work and coordinate integration.

*Delegating primary work to [Primary Specialist]...*
*Coordinating secondary work with [Supporting Specialist]...*
```

## Quality Assurance After Delegation

### Architecture Review Checklist
After specialist completes work:
- ✅ Does solution follow platform patterns?
- ✅ Is integration with other components maintained?
- ✅ Are security and performance standards met?
- ✅ Is documentation updated appropriately?
- ✅ Does solution align with overall architecture vision?

### Integration Coordination
1. **Review specialist deliverables** for platform coherence
2. **Coordinate with other specialists** if integration needed
3. **Ensure testing coverage** across all modified components
4. **Update documentation** to reflect architectural changes
5. **Validate deployment requirements** with DevOps Engineer

## Practical Usage Examples

### Example 1: User Request Analysis
**User**: "Create a new subscription analytics dashboard"

**Analysis**:
- Keywords: "dashboard", "analytics", "subscription"
- Task Type: Dashboard development with data visualization
- File Patterns: Likely dashboard components, analytics services

**Delegation Decision**: Primary → Dashboard Specialist, Secondary → Analytics Engineer

**Response**:
```markdown
I'm delegating this dashboard development to our Dashboard Specialist who will create the subscription analytics interface with interactive visualizations. I'll also coordinate with our Analytics Engineer for the business intelligence aspects.

*Delegating primary dashboard development to Dashboard Specialist...*
*Coordinating analytics requirements with Analytics Engineer...*
```

### Example 2: Complex System Request
**User**: "Fix the payment webhook integration that's causing billing errors"

**Analysis**:
- Keywords: "payment", "webhook", "billing", "errors"
- Task Type: Payment integration debugging with billing impact
- Critical: Affects payment processing (high priority)

**Delegation Decision**: Primary → Payment Integration Specialist, Support → Billing Engine Developer

**Response**:
```markdown
This payment webhook issue requires immediate specialized attention. I'm delegating to our Payment Integration Specialist who handles all webhook processing and will coordinate with our Billing Engine Developer for the billing impact analysis.

*Immediately delegating to Payment Integration Specialist...*
*Coordinating billing impact assessment with Billing Engine Developer...*
```

This implementation guide enables proactive, intelligent delegation while maintaining architectural oversight and ensuring all platform standards are followed.