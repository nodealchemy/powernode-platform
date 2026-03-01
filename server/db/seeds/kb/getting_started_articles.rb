# frozen_string_literal: true

# Getting Started Articles
# Essential guides for new users

puts "  🚀 Creating Getting Started articles..."

getting_started_cat = KnowledgeBase::Category.find_by!(slug: "getting-started")
author = User.find_by!(email: "admin@powernode.org")

# Article 1: Welcome to Powernode Platform (Featured)
welcome_content = <<~MARKDOWN
# Welcome to Powernode Platform

Welcome to Powernode, your comprehensive subscription lifecycle management platform with enterprise-grade AI orchestration, DevOps integration, and supply chain security.

## What You'll Learn

- Core platform components and capabilities
- Getting started checklist
- Common use cases
- Best practices for success

## Platform Overview

Powernode is designed for modern subscription businesses, combining:

- **Subscription Management** - Complete billing and customer lifecycle
- **AI Orchestration** - Enterprise AI with multi-provider support
- **DevOps Integration** - CI/CD pipelines and repository management
- **Supply Chain Security** - SBOM, attestations, and vendor risk
- **Business Analytics** - Real-time insights and reporting

### Core Components

| Component | Purpose |
|-----------|---------|
| Customer Dashboard | Self-service portal for subscribers |
| Admin Dashboard | Complete platform management |
| Billing Engine | Automated recurring payments |
| AI Platform | Agent orchestration and workflows |
| DevOps Hub | Pipelines and integrations |
| Security Center | Supply chain and compliance |

## Getting Started Checklist

### Day 1: Account Setup

- [ ] Complete your profile information
- [ ] Set up company details and branding
- [ ] Configure timezone and currency
- [ ] Invite your first team member
- [ ] Explore the dashboard

### Week 1: Core Configuration

- [ ] Connect payment gateway (Stripe/PayPal)
- [ ] Create your first subscription plan
- [ ] Set up email notifications
- [ ] Configure basic permissions
- [ ] Test subscription flow

### Week 2: Advanced Features

- [ ] Connect Git provider (GitHub/GitLab)
- [ ] Configure AI provider (OpenAI/Claude)
- [ ] Set up first CI/CD pipeline
- [ ] Import SBOM for supply chain visibility
- [ ] Create custom reports

## Use Cases

### SaaS Subscription Business

Manage software subscriptions with:
- Tiered pricing plans
- Usage-based billing
- Customer self-service
- Automated renewals

### Digital Services

Handle recurring service delivery:
- Service packages
- Add-on management
- Customer portals
- Invoice generation

### Enterprise Platform

Scale with confidence:
- Multi-tenant architecture
- Role-based access
- Audit logging
- Compliance reporting

## Best Practices

### Start Simple
- Begin with basic subscription plans
- Add complexity gradually
- Test thoroughly before launch

### Automate Early
- Set up payment automation
- Configure email notifications
- Enable AI-powered support

### Monitor Continuously
- Track key metrics daily
- Review analytics weekly
- Optimize based on data

## Platform Navigation

### Main Dashboard
Access key metrics and quick actions from the home dashboard.

### Business Section
- Plans and Subscriptions
- Payments and Invoices
- Customer Management

### AI Section
- Providers and Agents
- Workflows and Contexts
- MCP Servers

### DevOps Section
- Git Providers
- CI/CD Pipelines
- Webhooks

### Supply Chain Section
- SBOMs and Components
- Attestations
- Vendor Management

## Getting Help

### Self-Service Resources
- **Knowledge Base** - Comprehensive guides
- **API Documentation** - Developer resources
- **Video Tutorials** - Step-by-step walkthroughs

### Support Channels
- **Email**: support@powernode.org
- **Live Chat**: Available for paid plans
- **Community**: community.powernode.org

## Next Steps

Ready to dive deeper? Explore these guides:

1. [Quick Start Guide](/kb/quick-start-guide) - Your first 30 minutes
2. [Understanding the Dashboard](/kb/understanding-dashboard) - Navigation guide
3. [User Roles and Permissions](/kb/user-roles-permissions) - Access control

---

Welcome aboard! We're excited to help you succeed with Powernode.
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "welcome-to-powernode-platform") do |article|
  article.title = "Welcome to Powernode Platform"
  article.category = getting_started_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Complete introduction to Powernode's subscription management, AI orchestration, DevOps integration, and supply chain security capabilities."
  article.content = welcome_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Welcome to Powernode Platform"

# Article 2: Quick Start Guide
quick_start_content = <<~MARKDOWN
# Quick Start Guide - Your First 30 Minutes

Get up and running with Powernode in 30 minutes or less with this hands-on quickstart guide.

## Prerequisites

Before starting:
- Valid email address
- Payment gateway credentials (Stripe or PayPal)
- Basic understanding of subscription models

## Step 1: Account Creation (5 minutes)

### Sign Up

1. Visit powernode.org/register
2. Enter your email and create password
3. Verify email via confirmation link
4. Complete profile setup

### Initial Configuration

```yaml
Profile Setup:
  First Name: Your name
  Last Name: Your last name
  Company: Your company name
  Role: Your role (Owner, Admin, etc.)
  Timezone: Select your timezone
```

## Step 2: Company Setup (5 minutes)

### Company Information

Navigate to **Settings > Company**:

1. Upload company logo
2. Enter business details
3. Set default currency
4. Configure billing address

### Branding

Customize your customer-facing portal:
- Primary color
- Logo placement
- Custom domain (optional)

## Step 3: Payment Gateway (5 minutes)

### Connect Stripe

1. Navigate to **Settings > Payments**
2. Click **Connect Stripe**
3. Sign in to your Stripe account
4. Authorize Powernode
5. Configure webhook endpoints

### Test Connection

```bash
# Verify connection
- Go to Settings > Payments
- Click "Test Connection"
- Verify "Connected" status
```

## Step 4: Create First Plan (5 minutes)

### Basic Plan Setup

Navigate to **Business > Plans**:

1. Click **Create Plan**
2. Enter plan details:

```yaml
Plan Configuration:
  Name: Starter Plan
  Description: Perfect for small teams
  Price: $29/month
  Billing Cycle: Monthly
  Trial Period: 14 days
  Features:
    - 5 team members
    - 1,000 API calls
    - Email support
```

3. Set visibility to Public
4. Save and activate

## Step 5: Invite Team Member (5 minutes)

### Send Invitation

Navigate to **Settings > Team**:

1. Click **Invite Member**
2. Enter email address
3. Select permissions
4. Send invitation

### Permission Recommendations

| Role | Permissions |
|------|-------------|
| Co-founder | users.manage, billing.manage, admin.access |
| Developer | users.read, analytics.read |
| Support | users.read, billing.read |

## Step 6: Test Subscription (5 minutes)

### Create Test Customer

1. Navigate to **Business > Customers**
2. Click **Add Customer**
3. Enter test customer details
4. Select your Starter Plan
5. Use Stripe test card: 4242 4242 4242 4242

### Verify

- Check subscription status
- Review invoice generation
- Confirm email notifications

## What's Next?

### Immediate Next Steps
- [ ] Create additional subscription plans
- [ ] Set up automated emails
- [ ] Configure analytics dashboard
- [ ] Add more team members

### Advanced Features
- [AI Orchestration](/kb/ai-orchestration-overview) - Set up AI agents
- [DevOps Integration](/kb/devops-overview) - Connect repositories
- [Supply Chain](/kb/supply-chain-security-overview) - Security setup

## Quick Reference

### Key URLs
| Page | Path |
|------|------|
| Dashboard | /app/dashboard |
| Plans | /app/business/plans |
| Customers | /app/business/customers |
| Settings | /app/settings |

### Test Cards (Stripe)
| Card | Number |
|------|--------|
| Success | 4242 4242 4242 4242 |
| Decline | 4000 0000 0000 0002 |
| 3D Secure | 4000 0027 6000 3184 |

---

Congratulations! You've completed the quick start. Explore the Knowledge Base for detailed guides on each feature.
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "quick-start-guide") do |article|
  article.title = "Quick Start Guide - Your First 30 Minutes"
  article.category = getting_started_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Get up and running with Powernode in 30 minutes. Create your account, connect payments, set up plans, and make your first test subscription."
  article.content = quick_start_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Quick Start Guide"

# Article 3: Understanding the Dashboard
dashboard_content = <<~MARKDOWN
# Understanding the Dashboard

Master Powernode's dashboard to monitor your business, access features quickly, and make data-driven decisions.

## Dashboard Layout

### Navigation Structure

```
┌──────────────────────────────────────────────────────┐
│  Logo   │  Main Navigation  │  Search  │  User Menu │
├─────────┴───────────────────┴──────────┴────────────┤
│                                                      │
│   ┌─────────────────────────────────────────────┐   │
│   │            Quick Stats Row                  │   │
│   └─────────────────────────────────────────────┘   │
│                                                      │
│   ┌──────────────────┐  ┌──────────────────────┐   │
│   │                  │  │                      │   │
│   │   Main Widget    │  │    Side Widget       │   │
│   │                  │  │                      │   │
│   └──────────────────┘  └──────────────────────┘   │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Main Navigation

| Section | Features |
|---------|----------|
| **Dashboard** | Overview, metrics, quick actions |
| **Business** | Plans, subscriptions, payments, customers |
| **AI** | Providers, agents, workflows, contexts |
| **DevOps** | Git providers, pipelines, webhooks |
| **Supply Chain** | SBOMs, attestations, vendors |
| **Content** | Pages, knowledge base, files |
| **Analytics** | Reports, insights, exports |
| **Settings** | Account, team, integrations |

## Key Metrics

### Revenue Metrics

| Metric | Description | Calculation |
|--------|-------------|-------------|
| **MRR** | Monthly Recurring Revenue | Sum of all monthly subscriptions |
| **ARR** | Annual Recurring Revenue | MRR × 12 |
| **ARPU** | Average Revenue Per User | MRR ÷ Active subscribers |

### Growth Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| **New MRR** | Revenue from new customers | Track growth |
| **Expansion MRR** | Revenue from upgrades | > 20% of MRR |
| **Churn MRR** | Revenue lost | < 5% monthly |
| **Net MRR Growth** | New + Expansion - Churn | Positive |

### Customer Metrics

| Metric | Description |
|--------|-------------|
| **Active Subscriptions** | Currently active customers |
| **Trial Conversions** | Trials converting to paid |
| **Churn Rate** | Customer loss percentage |
| **LTV** | Customer Lifetime Value |

## Quick Actions

Access common tasks instantly:

- **Create Plan** - New subscription plan
- **Add Customer** - Manual customer creation
- **Generate Report** - Custom analytics
- **View Notifications** - System alerts
- **Access Settings** - Quick configuration

## Customizing Your View

### Date Range Selection

Filter data by time period:
- Today
- Last 7 days
- Last 30 days
- This month
- This quarter
- Custom range

### Widget Configuration

Customize dashboard widgets:
1. Click widget menu (⋮)
2. Select "Configure"
3. Choose metrics to display
4. Set refresh interval
5. Save changes

## Notifications

### Notification Types

| Type | Icon | Priority |
|------|------|----------|
| Payment Failed | 💳 | High |
| New Customer | 👤 | Medium |
| Subscription Changed | 📋 | Medium |
| System Alert | ⚠️ | Varies |

### Managing Notifications

Configure in **Settings > Notifications**:
- Email preferences
- In-app settings
- Slack integration
- Mobile push (coming soon)

## Mobile Responsiveness

The dashboard adapts to different screen sizes:

**Desktop** (1200px+)
- Full sidebar navigation
- Multi-column layouts
- Expanded widgets

**Tablet** (768px-1199px)
- Collapsible sidebar
- Adjusted layouts
- Touch-optimized controls

**Mobile** (< 768px)
- Bottom navigation
- Single column
- Swipe gestures

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘/Ctrl + K` | Search |
| `⌘/Ctrl + N` | New item |
| `⌘/Ctrl + /` | Help |
| `Esc` | Close modal |

---

Master the dashboard to get the most out of Powernode. For detailed guides on specific features, browse the Knowledge Base.
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "understanding-dashboard") do |article|
  article.title = "Understanding the Dashboard"
  article.category = getting_started_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Navigate Powernode's dashboard effectively. Learn about key metrics, quick actions, customization, and keyboard shortcuts."
  article.content = dashboard_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Understanding the Dashboard"

# Article 4: User Roles and Permissions
roles_permissions_content = <<~MARKDOWN
# User Roles and Permissions Overview

Understand Powernode's permission-based access control system to secure your account and enable team collaboration.

## Permission-Based System

Powernode uses **permissions** (not roles) for granular access control:

```
User → Permissions → Features
  ↓         ↓           ↓
Account  Specific    Allowed
Member   Grants      Actions
```

### Why Permissions?

- **Granular Control** - Exact access per feature
- **Flexibility** - Custom permission sets
- **Security** - Principle of least privilege
- **Auditability** - Clear access tracking

## Permission Categories

### User Management

| Permission | Access Granted |
|------------|----------------|
| `users.read` | View team members |
| `users.create` | Invite new members |
| `users.update` | Edit member details |
| `users.delete` | Remove members |
| `users.manage` | Full user control |
| `team.manage` | Team-wide management |

### Billing & Finance

| Permission | Access Granted |
|------------|----------------|
| `billing.read` | View billing info |
| `billing.update` | Modify settings |
| `billing.manage` | Full billing control |
| `invoices.create` | Generate invoices |
| `payments.process` | Process payments |

### Subscriptions

| Permission | Access Granted |
|------------|----------------|
| `subscriptions.read` | View subscriptions |
| `subscriptions.create` | Create new |
| `subscriptions.update` | Modify existing |
| `subscriptions.delete` | Cancel/remove |
| `subscriptions.manage` | Full control |

### Analytics

| Permission | Access Granted |
|------------|----------------|
| `analytics.read` | View reports |
| `analytics.export` | Export data |
| `reports.generate` | Create reports |

### Administration

| Permission | Access Granted |
|------------|----------------|
| `admin.access` | Admin interface |
| `system.admin` | Full system control |
| `settings.update` | Modify settings |

## Standard Permission Sets

### System Administrator
Full platform access:
```yaml
Permissions:
  - system.admin
  - users.manage
  - billing.manage
  - subscriptions.manage
  - analytics.read
  - admin.access
```

### Account Manager
Business operations:
```yaml
Permissions:
  - users.read
  - billing.manage
  - subscriptions.manage
  - analytics.read
```

### Billing Manager
Financial operations:
```yaml
Permissions:
  - billing.manage
  - invoices.create
  - payments.process
  - analytics.read
```

### Account Member
Basic access:
```yaml
Permissions:
  - users.read
  - billing.read
  - subscriptions.read
```

## Assigning Permissions

### Via Dashboard

1. Navigate to **Settings > Team**
2. Select team member
3. Click **Edit Permissions**
4. Check/uncheck permissions
5. Save changes

### Permission Effects

Changes take effect immediately:
- User may need to refresh page
- Active sessions updated
- Audit log entry created

## Best Practices

### Principle of Least Privilege

Grant only necessary permissions:

✅ **Good**: Support team has `users.read`, `billing.read`
❌ **Bad**: Everyone has `system.admin`

### Regular Audits

Review permissions quarterly:
- Remove unused access
- Verify role alignment
- Check for privilege creep

### Separation of Duties

Separate sensitive functions:
- Different users for billing vs. admin
- Approval workflows for critical actions
- Multi-person authorization for changes

## Checking Permissions

### Your Permissions

View your own access:
1. Click profile menu
2. Select "My Permissions"
3. Review granted permissions

### Team Permissions

As an admin:
1. Go to **Settings > Team**
2. View permission matrix
3. Export for auditing

## Troubleshooting

### "Access Denied" Errors

1. Verify permission assignment
2. Check account status
3. Clear browser cache
4. Contact administrator

### Features Not Visible

Missing permissions cause features to hide:
- Request needed permissions
- Contact team admin
- Review permission requirements

---

For detailed permission management, see the [Team Management Guide](/kb/team-management-permissions-guide).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "user-roles-permissions") do |article|
  article.title = "User Roles and Permissions Overview"
  article.category = getting_started_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Understand Powernode's permission-based access control including permission categories, standard sets, and best practices for security."
  article.content = roles_permissions_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ User Roles and Permissions"

puts "  ✅ Getting Started articles created (4 articles)"
