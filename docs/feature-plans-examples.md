# Feature Plans with Role-Based Access Examples

This document demonstrates how different subscription plans provide specific roles that grant access to features and functionality.

## Plan Structure Overview

Each plan defines:
- **Base Features**: Core functionality included
- **Default Roles**: Roles automatically assigned to users
- **Available Roles**: Additional roles that can be assigned within the plan
- **Feature Gates**: Permissions that unlock specific features

## Example Plans

### 1. Starter Plan ($29/month)
**Target**: Small teams and individuals getting started

#### Included Roles:
- `account.member` (default for new users)
- `content.creator`

#### Available Features:
```yaml
plan: starter
price: 29
currency: USD
billing_cycle: monthly

roles:
  account.member:
    permissions:
      - user.view
      - user.edit_self
      - page.view
      - page.create
      - page.edit
      - analytics.view
      - api.read
    description: "Basic account access with content creation"
    
  content.creator:
    permissions:
      - page.create
      - page.edit
      - page.delete
      - page.publish
      - webhook.view
      - analytics.view
      - analytics.export
    description: "Enhanced content management capabilities"

features:
  - Basic content management (5 pages)
  - Analytics dashboard
  - API read access
  - Community support

limits:
  pages: 5
  api_calls_per_month: 1000
  team_members: 3
```

### 2. Professional Plan ($79/month)
**Target**: Growing businesses with team collaboration needs

#### Included Roles:
- `account.member` (default)
- `team.collaborator`
- `content.manager`
- `analytics.analyst`

#### Available Features:
```yaml
plan: professional
price: 79
currency: USD
billing_cycle: monthly

roles:
  account.member:
    permissions:
      - user.view
      - user.edit_self
      - page.view
      - analytics.view
      - api.read
    description: "Standard account member access"
    
  team.collaborator:
    permissions:
      - team.view
      - team.invite
      - page.create
      - page.edit
      - page.publish
      - webhook.view
      - webhook.create
      - api.read
      - api.write
    description: "Team collaboration and content management"
    
  content.manager:
    permissions:
      - page.create
      - page.edit
      - page.delete
      - page.publish
      - webhook.view
      - webhook.create
      - webhook.edit
      - analytics.view
      - analytics.export
      - report.view
      - report.generate
    description: "Full content and webhook management"
    
  analytics.analyst:
    permissions:
      - analytics.view
      - analytics.export
      - report.view
      - report.generate
      - report.export
      - audit.view
    description: "Advanced analytics and reporting access"

features:
  - Advanced content management (50 pages)
  - Team collaboration tools
  - Advanced analytics & reporting
  - Webhook management
  - API read/write access
  - Priority support

limits:
  pages: 50
  api_calls_per_month: 25000
  team_members: 10
  webhooks: 5
```

### 3. Business Plan ($199/month)
**Target**: Established businesses with complex requirements

#### Included Roles:
- `account.member` (default)
- `team.manager`
- `billing.manager`
- `content.manager`
- `api.developer`
- `support.agent`

#### Available Features:
```yaml
plan: business
price: 199
currency: USD
billing_cycle: monthly

roles:
  account.member:
    permissions:
      - user.view
      - user.edit_self
      - page.view
      - analytics.view
      - api.read
    description: "Standard account access"
    
  team.manager:
    permissions:
      - team.view
      - team.invite
      - team.remove
      - team.assign_roles
      - user.view
      - page.create
      - page.edit
      - page.publish
      - webhook.view
      - webhook.create
      - webhook.edit
      - analytics.view
      - analytics.export
    description: "Team management and content oversight"
    
  billing.manager:
    permissions:
      - billing.view
      - billing.update
      - invoice.view
      - invoice.download
      - team.view
      - user.view
    description: "Billing and subscription management"
    
  content.manager:
    permissions:
      - page.create
      - page.edit
      - page.delete
      - page.publish
      - webhook.view
      - webhook.create
      - webhook.edit
      - webhook.delete
      - analytics.view
      - analytics.export
      - report.view
      - report.generate
      - report.export
      - audit.view
    description: "Complete content and webhook management"
    
  api.developer:
    permissions:
      - api.read
      - api.write
      - api.manage_keys
      - webhook.view
      - webhook.create
      - webhook.edit
      - webhook.delete
      - page.view
      - page.edit
      - analytics.view
    description: "Full API access and development tools"
    
  support.agent:
    permissions:
      - user.view
      - team.view
      - page.view
      - analytics.view
      - report.view
      - audit.view
    description: "Customer support and assistance access"

features:
  - Unlimited content management
  - Advanced team management
  - Billing management tools
  - Full API access
  - Advanced webhooks
  - Comprehensive analytics
  - Audit logging
  - Priority support with dedicated agent

limits:
  pages: unlimited
  api_calls_per_month: 100000
  team_members: 25
  webhooks: 25
```

### 4. Enterprise Plan ($499/month)
**Target**: Large organizations with advanced security and compliance needs

#### Included Roles:
- `account.member` (default)
- `account.manager`
- `team.manager`
- `billing.manager`
- `content.manager`
- `api.developer`
- `support.agent`
- `security.officer`

#### Available Features:
```yaml
plan: enterprise
price: 499
currency: USD
billing_cycle: monthly

roles:
  account.member:
    permissions:
      - user.view
      - user.edit_self
      - page.view
      - analytics.view
      - api.read
    description: "Standard enterprise account access"
    
  account.manager:
    permissions:
      - team.view
      - team.invite
      - team.remove
      - team.assign_roles
      - user.view
      - billing.view
      - billing.update
      - page.create
      - page.edit
      - page.delete
      - page.publish
      - webhook.view
      - webhook.create
      - webhook.edit
      - webhook.delete
      - analytics.view
      - analytics.export
      - report.view
      - report.generate
      - report.export
      - audit.view
      - audit.export
      - api.read
      - api.write
      - api.manage_keys
    description: "Full account management capabilities"
    
  team.manager:
    permissions:
      - team.view
      - team.invite
      - team.remove
      - team.assign_roles
      - user.view
      - page.create
      - page.edit
      - page.publish
      - webhook.view
      - webhook.create
      - webhook.edit
      - analytics.view
      - analytics.export
      - report.view
      - report.generate
    description: "Comprehensive team management"
    
  billing.manager:
    permissions:
      - billing.view
      - billing.update
      - billing.cancel
      - invoice.view
      - invoice.download
      - team.view
      - user.view
      - analytics.view
      - report.view
    description: "Complete billing and financial management"
    
  content.manager:
    permissions:
      - page.create
      - page.edit
      - page.delete
      - page.publish
      - webhook.view
      - webhook.create
      - webhook.edit
      - webhook.delete
      - analytics.view
      - analytics.export
      - report.view
      - report.generate
      - report.export
      - audit.view
      - audit.export
    description: "Enterprise content management"
    
  api.developer:
    permissions:
      - api.read
      - api.write
      - api.manage_keys
      - webhook.view
      - webhook.create
      - webhook.edit
      - webhook.delete
      - page.view
      - page.edit
      - page.create
      - analytics.view
      - analytics.export
    description: "Full API development access"
    
  support.agent:
    permissions:
      - user.view
      - team.view
      - page.view
      - analytics.view
      - report.view
      - audit.view
      - audit.export
    description: "Enterprise support and assistance"
    
  security.officer:
    permissions:
      - user.view
      - team.view
      - billing.view
      - audit.view
      - audit.export
      - analytics.view
      - report.view
      - report.generate
      - report.export
    description: "Security monitoring and compliance oversight"

features:
  - Unlimited everything
  - Advanced security features
  - Compliance reporting
  - Dedicated support team
  - Custom integrations
  - Advanced audit logging
  - SSO integration
  - Advanced user management

limits:
  pages: unlimited
  api_calls_per_month: unlimited
  team_members: unlimited
  webhooks: unlimited
  audit_retention_days: 365
```

## Role Assignment Examples

### Scenario 1: Marketing Agency (Professional Plan)
```yaml
team_setup:
  - name: "Sarah (Agency Owner)"
    roles: [account.member, team.collaborator, content.manager, analytics.analyst]
    
  - name: "Mike (Content Writer)"
    roles: [account.member, team.collaborator]
    
  - name: "Lisa (Data Analyst)"
    roles: [account.member, analytics.analyst]
    
  - name: "Tom (Developer)"
    roles: [account.member, team.collaborator] # Can't assign api.developer (not in Professional plan)
```

### Scenario 2: E-commerce Company (Business Plan)
```yaml
team_setup:
  - name: "Alex (CEO)"
    roles: [account.member, team.manager, billing.manager]
    
  - name: "Emma (Marketing Director)"
    roles: [account.member, content.manager, analytics.analyst]
    
  - name: "David (Lead Developer)"
    roles: [account.member, api.developer, content.manager]
    
  - name: "Sophie (Customer Support)"
    roles: [account.member, support.agent]
    
  - name: "James (Content Creator)"
    roles: [account.member, team.collaborator]
```

### Scenario 3: Enterprise Corporation (Enterprise Plan)
```yaml
team_setup:
  - name: "Patricia (VP of Operations)"
    roles: [account.member, account.manager]
    
  - name: "Robert (IT Director)"
    roles: [account.member, api.developer, security.officer]
    
  - name: "Maria (Finance Manager)"
    roles: [account.member, billing.manager]
    
  - name: "Kevin (Team Lead)"
    roles: [account.member, team.manager, content.manager]
    
  - name: "Jennifer (Security Analyst)"
    roles: [account.member, security.officer]
    
  - name: "Michael (Support Manager)"
    roles: [account.member, support.agent, team.manager]
```

## Feature Gates by Plan

| Feature | Starter | Professional | Business | Enterprise |
|---------|---------|-------------|----------|------------|
| Basic Content Management | ✅ | ✅ | ✅ | ✅ |
| Team Collaboration | ❌ | ✅ | ✅ | ✅ |
| Advanced Analytics | ❌ | ✅ | ✅ | ✅ |
| Webhook Management | ❌ | ✅ | ✅ | ✅ |
| API Write Access | ❌ | ✅ | ✅ | ✅ |
| Billing Management | ❌ | ❌ | ✅ | ✅ |
| API Key Management | ❌ | ❌ | ✅ | ✅ |
| Audit Logging | ❌ | ❌ | ✅ | ✅ |
| Security Roles | ❌ | ❌ | ❌ | ✅ |
| Unlimited Resources | ❌ | ❌ | ❌ | ✅ |

## Implementation Notes

1. **Role Inheritance**: Higher plans include all roles from lower plans
2. **Feature Gating**: Permissions control access to specific features
3. **Upgrade Path**: Users can upgrade to access more roles and features
4. **Flexibility**: Plans can be customized for specific customer needs
5. **Security**: Role-based access ensures users only see what they need