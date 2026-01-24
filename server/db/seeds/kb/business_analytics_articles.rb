# frozen_string_literal: true

# Business Analytics Articles
# Documentation for analytics and reporting

puts "  📊 Creating Business Analytics articles..."

analytics_cat = KnowledgeBase::Category.find_by!(slug: "business-analytics")
author = User.find_by!(email: "admin@powernode.org")

# Article 12: Business Analytics Overview (Featured)
analytics_overview_content = <<~MARKDOWN
# Business Analytics Overview

Leverage Powernode's analytics to make data-driven decisions and optimize your subscription business.

## Analytics Dashboard

### Key Metrics at a Glance

The analytics dashboard provides real-time visibility:

| Metric | Description | Update Frequency |
|--------|-------------|------------------|
| MRR | Monthly Recurring Revenue | Real-time |
| ARR | Annual Recurring Revenue | Real-time |
| Active Subscribers | Current paid customers | Real-time |
| Churn Rate | Monthly customer loss | Daily |
| ARPU | Average Revenue Per User | Daily |

### Dashboard Sections

```
┌─────────────────────────────────────────────┐
│     Revenue Overview      │   Growth Trend  │
├───────────────────────────┼─────────────────┤
│                           │                 │
│   MRR: $125,000          │    [Chart]      │
│   ARR: $1,500,000        │                 │
│   Growth: +12% MoM       │                 │
│                           │                 │
├───────────────────────────┴─────────────────┤
│              Customer Metrics               │
├─────────────────────────────────────────────┤
│  Active: 2,450  │  Trial: 125  │  Churn: 3% │
└─────────────────────────────────────────────┘
```

## Real-Time vs Historical

### Real-Time Data

Updated continuously:
- Current MRR/ARR
- Active subscription count
- Recent transactions
- Live payment status

### Historical Data

Aggregated periodically:
- Trend analysis
- Cohort reports
- Churn analysis
- Growth projections

## Date Range Selection

Filter all reports by period:

| Range | Use Case |
|-------|----------|
| Today | Current activity |
| Last 7 days | Weekly review |
| Last 30 days | Monthly analysis |
| This quarter | Quarterly reporting |
| Year to date | Annual tracking |
| Custom | Specific periods |

## Export Capabilities

### Export Formats

| Format | Best For |
|--------|----------|
| CSV | Spreadsheet analysis |
| PDF | Executive reports |
| Excel | Detailed analysis |
| JSON | API integration |

### Scheduled Reports

Automate report delivery:

```yaml
Scheduled Report:
  Name: Weekly Revenue Summary
  Format: PDF
  Schedule: Every Monday 9 AM
  Recipients:
    - ceo@company.com
    - finance@company.com
  Contents:
    - Revenue metrics
    - Customer growth
    - Churn analysis
```

## Custom Reports

### Report Builder

Create custom reports:

1. Navigate to **Analytics > Reports**
2. Click **Create Report**
3. Select metrics and dimensions
4. Apply filters
5. Save and schedule

### Available Metrics

| Category | Metrics |
|----------|---------|
| Revenue | MRR, ARR, ARPU, LTV |
| Customers | Active, New, Churned, Trial |
| Subscriptions | By plan, status, tenure |
| Payments | Success rate, failures, refunds |

## Permissions

### Analytics Access

| Permission | Access Level |
|------------|--------------|
| `analytics.read` | View dashboards and reports |
| `analytics.export` | Download data exports |
| `reports.generate` | Create custom reports |

---

Explore detailed metrics in [Revenue Metrics and KPIs](/kb/revenue-metrics-kpis) and [Customer Insights](/kb/customer-insights-reporting).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "business-analytics-overview") do |article|
  article.title = "Business Analytics Overview"
  article.category = analytics_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Master Powernode's analytics dashboard with real-time metrics, historical analysis, export capabilities, and custom report creation."
  article.content = analytics_overview_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Business Analytics Overview"

# Article 13: Revenue Metrics and KPIs
revenue_metrics_content = <<~MARKDOWN
# Revenue Metrics and KPIs

Track the key performance indicators that drive subscription business success.

## Core Revenue Metrics

### Monthly Recurring Revenue (MRR)

The foundation of subscription metrics:

```yaml
MRR Calculation:
  Formula: Sum of all monthly subscription values

  Example:
    - 100 customers × $50/month = $5,000
    - 50 customers × $100/month = $5,000
    - Total MRR = $10,000
```

### MRR Components

| Component | Description | Example |
|-----------|-------------|---------|
| **New MRR** | Revenue from new customers | +$2,000 |
| **Expansion MRR** | Revenue from upgrades | +$500 |
| **Contraction MRR** | Revenue from downgrades | -$200 |
| **Churn MRR** | Revenue from cancellations | -$300 |
| **Net New MRR** | Sum of all changes | +$2,000 |

### Annual Recurring Revenue (ARR)

```yaml
ARR Calculation:
  Formula: MRR × 12

  Example:
    MRR: $10,000
    ARR: $120,000
```

## Customer Value Metrics

### Average Revenue Per User (ARPU)

```yaml
ARPU Calculation:
  Formula: MRR ÷ Active Customers

  Example:
    MRR: $10,000
    Customers: 200
    ARPU: $50
```

### Customer Lifetime Value (LTV)

```yaml
LTV Calculation:
  Formula: ARPU × Average Customer Lifespan

  Example:
    ARPU: $50/month
    Avg Lifespan: 24 months
    LTV: $1,200
```

### LTV:CAC Ratio

```yaml
LTV:CAC Ratio:
  Formula: LTV ÷ Customer Acquisition Cost

  Benchmarks:
    < 1:1 = Losing money
    1:1 to 3:1 = Break even to good
    > 3:1 = Excellent
    > 5:1 = Under-investing in growth
```

## Churn Metrics

### Customer Churn Rate

```yaml
Customer Churn:
  Formula: (Customers Lost ÷ Starting Customers) × 100

  Example:
    Starting: 200 customers
    Churned: 6 customers
    Churn Rate: 3%

  Benchmarks:
    Excellent: < 2%
    Good: 2-5%
    Needs Work: > 5%
```

### Revenue Churn Rate

```yaml
Revenue Churn:
  Formula: (MRR Lost ÷ Starting MRR) × 100

  Note: Can be negative (net expansion)
```

### Net Revenue Retention (NRR)

```yaml
NRR Calculation:
  Formula: (Starting MRR + Expansion - Contraction - Churn) ÷ Starting MRR × 100

  Example:
    Starting MRR: $100,000
    Expansion: $10,000
    Contraction: $2,000
    Churn: $3,000
    NRR: 105%

  Benchmarks:
    Excellent: > 120%
    Good: 100-120%
    Needs Work: < 100%
```

## Growth Metrics

### MRR Growth Rate

```yaml
MRR Growth:
  Formula: ((Current MRR - Previous MRR) ÷ Previous MRR) × 100

  Example:
    Previous: $10,000
    Current: $11,500
    Growth: 15%
```

### Quick Ratio

```yaml
Quick Ratio:
  Formula: (New MRR + Expansion MRR) ÷ (Contraction MRR + Churn MRR)

  Benchmarks:
    > 4 = Hypergrowth
    2-4 = Healthy growth
    < 2 = Struggling
```

## Efficiency Metrics

### Customer Acquisition Cost (CAC)

```yaml
CAC Calculation:
  Formula: Total Sales & Marketing Cost ÷ New Customers

  Example:
    Marketing Spend: $10,000
    Sales Cost: $5,000
    New Customers: 30
    CAC: $500
```

### CAC Payback Period

```yaml
Payback Period:
  Formula: CAC ÷ (ARPU × Gross Margin)

  Example:
    CAC: $500
    ARPU: $50
    Gross Margin: 80%
    Payback: 12.5 months
```

## Dashboard Configuration

### Setting Up KPI Dashboard

1. Navigate to **Analytics > Dashboard**
2. Click **Customize**
3. Add metric widgets:
   - MRR trend chart
   - Churn rate gauge
   - NRR indicator
   - Growth rate trend
4. Save configuration

### Alert Thresholds

```yaml
KPI Alerts:
  - metric: churn_rate
    threshold: 5%
    condition: greater_than
    notify: management@company.com

  - metric: mrr_growth
    threshold: 0%
    condition: less_than
    notify: leadership@company.com
```

---

For customer-level analysis, see [Customer Insights and Reporting](/kb/customer-insights-reporting).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "revenue-metrics-kpis") do |article|
  article.title = "Revenue Metrics and KPIs"
  article.category = analytics_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Track critical subscription metrics: MRR, ARR, ARPU, LTV, churn rates, Net Revenue Retention, and growth indicators with benchmarks."
  article.content = revenue_metrics_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Revenue Metrics and KPIs"

# Article 14: Customer Insights and Reporting
customer_insights_content = <<~MARKDOWN
# Customer Insights and Reporting

Understand your customers through data analysis, segmentation, and behavioral insights.

## Customer Overview

### Customer List

Navigate to **Business > Customers** to view:

| Column | Description |
|--------|-------------|
| Name | Customer/company name |
| Plan | Current subscription |
| Status | Active, trial, cancelled |
| MRR | Monthly contribution |
| Since | Customer tenure |

### Customer Search

Search and filter by:
- Name or email
- Subscription plan
- Status
- Date range
- Custom fields

## Customer Profile

### Profile Sections

```yaml
Customer Profile:
  Overview:
    - Name and contact info
    - Company details
    - Account manager

  Subscription:
    - Current plan
    - Billing cycle
    - Next invoice

  Billing:
    - Payment method
    - Invoice history
    - Payment status

  Activity:
    - Usage metrics
    - Support tickets
    - Login history
```

### Activity Timeline

Track customer interactions:
- Subscription changes
- Payment events
- Support tickets
- Feature usage

## Cohort Analysis

### Signup Cohorts

Analyze customers by signup month:

```
          Month 1   Month 2   Month 3   Month 6   Month 12
Jan '24   100%      95%       90%       80%       70%
Feb '24   100%      92%       88%       75%       --
Mar '24   100%      94%       89%       --        --
```

### Cohort Insights

- **Retention curves** - How long customers stay
- **Revenue patterns** - When expansion occurs
- **Churn timing** - When customers leave

## Segmentation

### Segment by Plan

| Plan | Customers | MRR | ARPU | Churn |
|------|-----------|-----|------|-------|
| Starter | 500 | $9,500 | $19 | 8% |
| Pro | 200 | $9,800 | $49 | 4% |
| Enterprise | 50 | $14,950 | $299 | 1% |

### Segment by Tenure

| Tenure | Customers | MRR | Churn Risk |
|--------|-----------|-----|------------|
| < 3 months | 150 | $6,000 | High |
| 3-12 months | 400 | $18,000 | Medium |
| > 12 months | 200 | $12,000 | Low |

### Custom Segments

Create custom segments:

```yaml
Segment: High-Value at Risk
  Criteria:
    - MRR > $100
    - Last login > 30 days
    - Support tickets > 3

  Action:
    - Alert account manager
    - Trigger outreach workflow
```

## Churn Prediction

### Risk Indicators

| Indicator | Weight | Description |
|-----------|--------|-------------|
| Login frequency | High | Decreasing activity |
| Feature usage | High | Declining engagement |
| Support tickets | Medium | Frustration signals |
| Payment failures | Medium | Financial issues |
| Plan downgrade | Low | Value concerns |

### Health Score

```yaml
Customer Health Score:
  Formula: Weighted average of indicators

  Scoring:
    90-100: Healthy (Green)
    70-89: Watch (Yellow)
    50-69: At Risk (Orange)
    0-49: Critical (Red)
```

## Custom Reports

### Report Templates

| Report | Purpose |
|--------|---------|
| Customer List | Full customer export |
| Churn Report | Cancelled customers |
| Expansion Report | Upgrade activity |
| Revenue by Segment | Segment analysis |

### Building Custom Reports

1. Navigate to **Analytics > Reports**
2. Click **New Report**
3. Select data source (Customers)
4. Add columns and metrics
5. Apply filters
6. Save and schedule

### Report Scheduling

```yaml
Scheduled Report:
  Name: Weekly Customer Health
  Schedule: Every Monday 8 AM
  Format: Excel
  Recipients: success-team@company.com
  Filters:
    - Health score < 70
    - MRR > $50
```

## Data Export

### Export Options

| Format | Use Case |
|--------|----------|
| CSV | Spreadsheet analysis |
| Excel | Detailed workbooks |
| JSON | API/system integration |
| PDF | Executive summaries |

### Bulk Export

For large datasets:
1. Configure export parameters
2. Submit export job
3. Receive notification when ready
4. Download from export history

---

For revenue analysis, see [Revenue Metrics and KPIs](/kb/revenue-metrics-kpis).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "customer-insights-reporting") do |article|
  article.title = "Customer Insights and Reporting"
  article.category = analytics_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Analyze customers through profiles, cohort analysis, segmentation, health scoring, churn prediction, and custom reporting."
  article.content = customer_insights_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Customer Insights and Reporting"

puts "  ✅ Business Analytics articles created (3 articles)"
