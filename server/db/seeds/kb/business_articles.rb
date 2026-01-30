# frozen_string_literal: true

# Business Articles
# Documentation for business operations features including Customers and Reports

puts "  💼 Creating Business articles..."

business_cat = KnowledgeBase::Category.find_by!(slug: "business-analytics")
author = User.find_by!(email: "admin@powernode.org")

# Article: Customer Management Guide
customer_management_content = <<~MARKDOWN
# Customer Management Guide

Manage your subscriber base with comprehensive customer profiles, lifecycle tracking, and engagement tools.

## Customer Overview

### What is Customer Management?

Customer management in Powernode provides:
- **Subscriber Profiles** - Complete customer information
- **Lifecycle Tracking** - From lead to loyal customer
- **Engagement Tools** - Communication and support
- **Analytics** - Customer behavior insights

### Accessing Customers

Navigate to **Business > Customers** to:
- View all customers
- Search and filter
- Access customer profiles
- Manage subscriptions

## Customer List

### Dashboard View

```
┌─────────────────────────────────────────────────────────────────┐
│  Customers                            [Export] [Add Customer]   │
├─────────────────────────────────────────────────────────────────┤
│  Active: 2,450  │  Trial: 125  │  Churned: 180  │  Total: 2,755│
├─────────────────────────────────────────────────────────────────┤
│  Name           │ Email            │ Plan    │ MRR   │ Status  │
├─────────────────┼──────────────────┼─────────┼───────┼─────────┤
│  Acme Corp      │ billing@acme.com │ Enterprise│ $299 │ Active  │
│  TechStart Inc  │ admin@techstart  │ Professional│$49 │ Active  │
│  Jane Smith     │ jane@example     │ Basic   │ $15   │ Trial   │
│  Old Customer   │ old@example      │ Basic   │ $0    │ Churned │
└─────────────────┴──────────────────┴─────────┴───────┴─────────┘
```

### Search and Filtering

```yaml
Search Options:
  Text Search:
    - Customer name
    - Email address
    - Company name
    - Account ID

  Filters:
    Status: [active, trial, past_due, cancelled, churned]
    Plan: [free, basic, professional, enterprise]
    MRR Range: Min - Max
    Joined: Date range
    Last Active: Date range
    Tags: Custom tags
    Health Score: [good, warning, at_risk, critical]
```

### Bulk Actions

```yaml
Bulk Operations:
  - Export to CSV/Excel
  - Add/remove tags
  - Send bulk email
  - Update custom fields
  - Assign account manager
```

## Customer Profile

### Profile Overview

```yaml
Customer: Acme Corporation
Account ID: acc_01HQ7EXAMPLE

Status: Active
Customer Since: January 15, 2023 (12 months)
Health Score: 85 (Good)

Subscription:
  Plan: Enterprise
  MRR: $299.00
  Billing Cycle: Monthly
  Next Invoice: February 1, 2024

Contact:
  Primary: John Smith (john@acme.com)
  Billing: billing@acme.com
  Phone: +1 (555) 123-4567

Tags: enterprise, priority, tech-industry
```

### Profile Sections

| Section | Contents |
|---------|----------|
| **Overview** | Key metrics and status |
| **Subscription** | Plan details, history |
| **Billing** | Invoices, payments, method |
| **Users** | Team members and roles |
| **Activity** | Usage and engagement |
| **Support** | Tickets and interactions |
| **Notes** | Internal notes and tags |

## Subscription Management

### Viewing Subscription

```yaml
Subscription Details:
  Plan: Enterprise
  Status: Active

  Pricing:
    Base Price: $299/month
    Add-ons: $50/month (extra users)
    Discounts: -$35/month (annual discount)
    Total MRR: $314/month

  Billing:
    Cycle: Monthly
    Method: Visa ending 4242
    Next Invoice: $314.00 on Feb 1, 2024

  Features:
    Users: 15/50 used
    API Calls: 45,000/100,000 used
    Storage: 25GB/100GB used
```

### Subscription Actions

| Action | Description |
|--------|-------------|
| **Change Plan** | Upgrade or downgrade |
| **Add/Remove Add-ons** | Modify features |
| **Apply Discount** | Add promotional discount |
| **Pause Subscription** | Temporary pause |
| **Cancel Subscription** | End subscription |
| **Extend Trial** | Grant additional trial days |

### Changing Plans

```yaml
Plan Change:
  Current: Professional ($49/month)
  New: Enterprise ($299/month)

  Proration:
    Days Remaining: 15
    Credit: $24.50
    New Charge: $149.50 (prorated)

  Effective: Immediate

  Changes:
    + Unlimited users (was 10)
    + Priority support
    + Custom integrations
    + SLA guarantee
```

## Customer Health

### Health Score

```yaml
Health Score Calculation:
  Acme Corporation: 85/100 (Good)

  Components:
    Usage Activity: 90/100
      - Login frequency: High
      - Feature adoption: Good
      - API usage: Active

    Payment Health: 95/100
      - On-time payments: 100%
      - Payment method: Valid

    Engagement: 75/100
      - Support tickets: Low (good)
      - NPS response: Positive
      - Feature requests: Active

    Tenure: 80/100
      - Customer for 12 months
      - No downgrade history
```

### Health Indicators

| Score | Status | Action |
|-------|--------|--------|
| 90-100 | Excellent | Upsell opportunity |
| 70-89 | Good | Maintain engagement |
| 50-69 | Warning | Proactive outreach |
| 0-49 | At Risk | Immediate intervention |

### Risk Alerts

```yaml
Risk Indicators:
  ⚠️ Login frequency decreased 50%
  ⚠️ Support ticket volume increased
  ✅ Payments on time
  ✅ No plan downgrade

  Recommended Actions:
    - Schedule customer success call
    - Review recent support tickets
    - Check for product issues
```

## Activity Tracking

### Usage Metrics

```yaml
Usage (Last 30 Days):
  Logins: 145 (12 users)
  API Calls: 45,234
  Features Used: 18/25

  Top Users:
    1. john@acme.com - 45 logins
    2. sarah@acme.com - 38 logins
    3. mike@acme.com - 32 logins

  Feature Usage:
    - Dashboard: 89% of sessions
    - Analytics: 67% of sessions
    - AI Agents: 45% of sessions
    - Reports: 23% of sessions
```

### Activity Timeline

```yaml
Recent Activity:
  Today:
    - 10:30 AM: john@acme.com logged in
    - 10:15 AM: Report generated
    - 09:00 AM: API sync completed

  Yesterday:
    - 4:30 PM: New user added (mike@acme.com)
    - 2:00 PM: Plan upgraded to Enterprise
    - 11:00 AM: Support ticket resolved

  Last Week:
    - Payment received ($299.00)
    - New integration connected
    - Feature request submitted
```

## Communication

### Email History

```yaml
Email History:
  Sent: 45 emails
  Opened: 38 (84%)
  Clicked: 12 (27%)

  Recent:
    - Jan 15: Invoice notification (opened)
    - Jan 10: Feature announcement (opened, clicked)
    - Jan 5: Renewal reminder (opened)
```

### Sending Communications

```yaml
Communication Options:
  Email:
    - Send individual email
    - Use template
    - Schedule delivery

  In-App:
    - Notification
    - Banner message
    - Chat message

  Bulk:
    - Segment by criteria
    - Campaign tracking
```

## Notes and Tags

### Internal Notes

```yaml
Notes:
  - Jan 15, 2024 (Sarah, Customer Success):
    "Discussed expansion to additional departments.
    They're interested in Enterprise features.
    Follow up in 2 weeks."

  - Jan 5, 2024 (Mike, Support):
    "Resolved API integration issue.
    Customer satisfied with response time."

  - Dec 20, 2023 (John, Sales):
    "Initial onboarding completed.
    Primary use case: AI workflow automation."
```

### Tags

```yaml
Tags:
  Customer Type: enterprise, priority
  Industry: tech-industry, saas
  Status: expansion-opportunity
  Account Manager: sarah-jones
```

## Customer Actions

### Common Operations

| Action | Use Case |
|--------|----------|
| **Edit Profile** | Update contact info |
| **Change Subscription** | Plan modifications |
| **Issue Credit** | Service credits |
| **Merge Customers** | Consolidate accounts |
| **Export Data** | GDPR/compliance |
| **Delete Customer** | Account removal |

### Issuing Credits

```yaml
Credit Application:
  Customer: Acme Corporation
  Amount: $50.00
  Reason: Service interruption on Jan 10

  Application:
    ○ Apply to next invoice
    ● Apply to account balance
    ○ Refund to payment method

  Notes: "Compensation for 2-hour outage"
```

## Importing Customers

### Import Options

```yaml
Import Methods:
  CSV Upload:
    - Download template
    - Fill customer data
    - Upload and map fields
    - Review and confirm

  API Integration:
    - Sync from CRM
    - Webhook imports
    - Scheduled syncs

  Manual Entry:
    - Add individual customers
    - Quick add form
```

### Import Template

```csv
name,email,company,plan,mrr,tags
John Smith,john@example.com,Acme Corp,professional,49,enterprise
Jane Doe,jane@example.com,TechStart,basic,15,startup
```

## Best Practices

### Customer Success

1. **Regular Check-ins**
   - Schedule periodic reviews
   - Monitor health scores
   - Proactive outreach

2. **Data Hygiene**
   - Keep contacts updated
   - Tag consistently
   - Document interactions

3. **Segmentation**
   - Group by characteristics
   - Personalize communication
   - Target appropriately

### Retention

1. **Monitor Signals**
   - Usage patterns
   - Support volume
   - Payment issues

2. **Act Early**
   - Intervene at warning signs
   - Offer assistance
   - Address concerns

## Related Articles

- [Business Analytics Overview](/kb/business-analytics-overview)
- [Customer Insights and Reporting](/kb/customer-insights-reporting)
- [Business Reports Guide](/kb/business-reports-guide)

---

Need help with customers? Contact success@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "customer-management-guide") do |article|
  article.title = "Customer Management Guide"
  article.category = business_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Manage your subscriber base with customer profiles, subscription management, health scoring, activity tracking, and engagement tools."
  article.content = customer_management_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Customer Management Guide"

# Article: Business Reports Guide
business_reports_content = <<~MARKDOWN
# Business Reports Guide

Generate comprehensive business reports for revenue analysis, customer insights, and operational metrics.

## Reports Overview

### What Are Business Reports?

Business reports provide:
- **Financial Analysis** - Revenue, MRR, ARR tracking
- **Customer Metrics** - Churn, retention, LTV
- **Operational Insights** - Usage, engagement, trends
- **Executive Summaries** - High-level business health

### Accessing Reports

Navigate to **Business > Reports** to:
- View pre-built reports
- Create custom reports
- Schedule report delivery
- Export report data

## Reports Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│  Business Reports                        [Create Report]        │
├─────────────────────────────────────────────────────────────────┤
│  Quick Reports:                                                 │
│  [MRR Summary] [Customer List] [Churn Analysis] [Revenue]       │
├─────────────────────────────────────────────────────────────────┤
│  Report Name        │ Type     │ Last Run   │ Schedule │ Action │
├─────────────────────┼──────────┼────────────┼──────────┼────────┤
│  Weekly Revenue     │ Revenue  │ Jan 15     │ Weekly   │ Run    │
│  Monthly Churn      │ Customer │ Jan 1      │ Monthly  │ Run    │
│  Executive Summary  │ Summary  │ Jan 15     │ Daily    │ Run    │
│  Customer Health    │ Customer │ Jan 14     │ Weekly   │ Run    │
└─────────────────────┴──────────┴────────────┴──────────┴────────┘
```

## Pre-Built Reports

### Revenue Reports

**MRR Summary Report**
```yaml
MRR Summary:
  Period: January 2024

  Overview:
    Starting MRR: $125,000
    New MRR: +$8,500
    Expansion MRR: +$3,200
    Contraction MRR: -$1,500
    Churned MRR: -$2,800
    Ending MRR: $132,400
    Net Growth: +$7,400 (+5.9%)

  Breakdown by Plan:
    Enterprise: $45,000 (34%)
    Professional: $52,000 (39%)
    Basic: $28,000 (21%)
    Free: $0 (0%)
    Other: $7,400 (6%)
```

**ARR Projection Report**
```yaml
ARR Analysis:
  Current ARR: $1,588,800

  Projection (12 months):
    Conservative: $1,750,000 (+10%)
    Moderate: $1,900,000 (+20%)
    Optimistic: $2,100,000 (+32%)

  Assumptions:
    - Churn rate: 5% monthly
    - Growth rate: 8% monthly
    - Expansion rate: 15% of existing
```

### Customer Reports

**Churn Analysis Report**
```yaml
Churn Report: January 2024

  Customer Churn:
    Churned Customers: 45
    Churn Rate: 3.2%
    Lost MRR: $4,500

  Churn Reasons:
    Price: 35%
    Switched to competitor: 25%
    No longer needed: 20%
    Poor experience: 12%
    Other: 8%

  Churn by Plan:
    Free → Basic: 15 (33%)
    Basic: 18 (40%)
    Professional: 10 (22%)
    Enterprise: 2 (5%)

  Churn by Tenure:
    < 3 months: 25 (56%)
    3-12 months: 15 (33%)
    > 12 months: 5 (11%)
```

**Customer Cohort Report**
```yaml
Cohort Analysis: Retention

            Month 1  Month 3  Month 6  Month 12
Jan 2023    100%     92%      85%      72%
Apr 2023    100%     90%      82%      --
Jul 2023    100%     88%      --       --
Oct 2023    100%     91%      --       --
Jan 2024    100%     --       --       --

Insights:
  - Best retention: Jan 2023 cohort
  - Improvement trend in recent cohorts
  - Critical period: Month 1-3
```

### Operational Reports

**Usage Report**
```yaml
Platform Usage: January 2024

  Active Users:
    DAU: 850
    WAU: 1,200
    MAU: 2,100

  Feature Adoption:
    Dashboard: 95%
    Analytics: 78%
    AI Features: 45%
    API: 32%
    Workflows: 28%

  API Usage:
    Total Calls: 2.5M
    Avg per Customer: 1,200
    Peak Hour: 10 AM UTC
```

**Support Report**
```yaml
Support Metrics: January 2024

  Tickets:
    Created: 234
    Resolved: 220
    Open: 14
    Avg Resolution: 4.2 hours

  By Category:
    Billing: 45 (19%)
    Technical: 120 (51%)
    Feature Request: 35 (15%)
    Other: 34 (15%)

  Satisfaction:
    CSAT: 4.5/5
    Response Rate: 92%
```

## Creating Custom Reports

### Report Builder

1. Navigate to **Reports > Create Report**
2. Select report type
3. Configure data sources
4. Add metrics and dimensions
5. Apply filters
6. Choose visualization
7. Save and schedule

### Configuration Options

```yaml
Report Configuration:
  Name: Monthly Revenue by Plan
  Type: Revenue Analysis

  Data:
    Source: Subscriptions
    Metrics:
      - MRR
      - Customer Count
      - ARPU
    Dimensions:
      - Plan Name
      - Billing Cycle

  Filters:
    Status: Active
    Date Range: Last 30 days

  Grouping:
    Primary: Plan Name
    Secondary: None

  Visualization:
    Type: Bar Chart + Table
    Sort: MRR Descending
```

### Available Metrics

| Category | Metrics |
|----------|---------|
| **Revenue** | MRR, ARR, ARPU, LTV, Revenue |
| **Customers** | Count, New, Churned, Active |
| **Subscriptions** | By Plan, By Status, Changes |
| **Usage** | Logins, API Calls, Features |
| **Support** | Tickets, Resolution Time, CSAT |

### Available Dimensions

| Dimension | Description |
|-----------|-------------|
| **Time** | Day, Week, Month, Quarter, Year |
| **Plan** | Subscription plan |
| **Status** | Customer/subscription status |
| **Geography** | Country, Region |
| **Segment** | Custom segments |
| **Tags** | Customer tags |

## Scheduling Reports

### Schedule Configuration

```yaml
Report Schedule:
  Report: Weekly Revenue Summary
  Frequency: Weekly (Monday 9 AM)
  Timezone: America/New_York

  Recipients:
    - ceo@company.com
    - finance@company.com
    - sales-team@company.com

  Format: PDF + CSV attachment

  Options:
    Include Charts: Yes
    Include Raw Data: Yes
    Only if Data Changed: No
```

### Schedule Options

| Frequency | Best For |
|-----------|----------|
| **Daily** | Operations, alerts |
| **Weekly** | Team meetings, reviews |
| **Monthly** | Executive summaries |
| **Quarterly** | Board reports |
| **Custom** | Specific needs |

## Exporting Reports

### Export Formats

| Format | Use Case |
|--------|----------|
| **PDF** | Sharing, presentations |
| **CSV** | Spreadsheet analysis |
| **Excel** | Detailed analysis, pivot tables |
| **JSON** | API integration |
| **PNG** | Charts for presentations |

### Export Options

```yaml
Export Configuration:
  Format: Excel
  Data Range: Full report
  Include:
    ✅ Summary metrics
    ✅ Charts
    ✅ Raw data
    ✅ Filters applied

  Advanced:
    Date Format: YYYY-MM-DD
    Number Format: Localized
    Compression: None
```

## Report Sharing

### Sharing Options

```yaml
Share Report:
  Share Link:
    URL: https://app.powernode.org/reports/abc123
    Expires: 7 days
    Password Protected: Yes

  Permissions:
    View Only: executives@company.com
    Edit: finance-team

  Embedding:
    Embed Code: <iframe src="..."></iframe>
    Dashboard Widget: Enabled
```

### Permissions

| Level | Capabilities |
|-------|--------------|
| **View** | See report results |
| **Export** | Download data |
| **Edit** | Modify configuration |
| **Admin** | Delete, share settings |

## Report Templates

### Using Templates

```yaml
Available Templates:
  Revenue:
    - MRR Dashboard
    - Revenue by Plan
    - Growth Analysis

  Customers:
    - Customer List
    - Churn Analysis
    - Cohort Retention

  Operations:
    - Usage Summary
    - Feature Adoption
    - Support Metrics

  Executive:
    - Executive Summary
    - Board Report
    - Investor Update
```

### Creating Templates

1. Build report with desired configuration
2. Click **Save as Template**
3. Name and describe template
4. Set visibility (personal, team, org)
5. Use template for future reports

## Dashboard Integration

### Adding to Dashboard

```yaml
Dashboard Widget:
  Report: Weekly Revenue
  Display: Chart + Key Metrics

  Refresh: Daily
  Size: Large (2x2 grid)

  Metrics Shown:
    - Current MRR
    - MRR Change
    - Net New Customers
    - Churn Rate
```

### Dashboard Layout

```
┌─────────────────────────────────────────────────┐
│  Business Dashboard                              │
├──────────────────────┬──────────────────────────┤
│  MRR Trend           │  Customer Health         │
│  [Line Chart]        │  [Pie Chart]             │
├──────────────────────┼──────────────────────────┤
│  Revenue by Plan     │  Recent Activity         │
│  [Bar Chart]         │  [List]                  │
└──────────────────────┴──────────────────────────┘
```

## Best Practices

### Report Design

1. **Clear Objectives**
   - Know what question you're answering
   - Include relevant metrics only
   - Make insights actionable

2. **Appropriate Visualizations**
   - Trends: Line charts
   - Comparisons: Bar charts
   - Composition: Pie charts
   - Detailed data: Tables

3. **Consistent Format**
   - Standard date ranges
   - Consistent naming
   - Clear labeling

### Report Management

1. **Regular Review**
   - Audit report relevance
   - Update filters as needed
   - Remove unused reports

2. **Access Control**
   - Appropriate permissions
   - Sensitive data handling
   - Audit access logs

## Related Articles

- [Business Analytics Overview](/kb/business-analytics-overview)
- [Revenue Metrics and KPIs](/kb/revenue-metrics-kpis)
- [Customer Management Guide](/kb/customer-management-guide)

---

Need help with reports? Contact analytics@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "business-reports-guide") do |article|
  article.title = "Business Reports Guide"
  article.category = business_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Generate comprehensive business reports for revenue analysis, customer metrics, operational insights, with scheduling and export options."
  article.content = business_reports_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Business Reports Guide"

puts "  ✅ Business articles created (2 articles)"
