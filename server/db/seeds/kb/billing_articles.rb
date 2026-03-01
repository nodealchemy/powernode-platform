# frozen_string_literal: true

# Billing & Subscriptions Articles
# Documentation for billing features

puts "  💰 Creating Billing articles..."

billing_cat = KnowledgeBase::Category.find_by!(slug: "billing-subscriptions")
author = User.find_by!(email: "admin@powernode.org")

# Article 8: Understanding Subscription Plans (Featured)
plans_content = <<~MARKDOWN
# Understanding Subscription Plans

Master subscription plan creation and configuration to monetize your service effectively.

## Plan Types

### Flat-Rate Plans

Simple fixed-price subscriptions:

```yaml
Flat-Rate Example:
  Name: Professional Plan
  Price: $49/month
  Billing: Monthly or Annual
  Features: Unlimited usage
```

**Best For**: Predictable services, simple pricing

### Tiered Plans

Volume-based pricing tiers:

```yaml
Tiered Example:
  Name: API Plan
  Tiers:
    - 0-1,000 calls: $0.01/call
    - 1,001-10,000: $0.008/call
    - 10,001+: $0.005/call
```

**Best For**: Usage-based services, scaling businesses

### Usage-Based Plans

Pay-per-use pricing:

```yaml
Usage-Based Example:
  Name: Compute Plan
  Base: $10/month
  Usage:
    - CPU Hours: $0.05/hour
    - Storage: $0.10/GB
    - Bandwidth: $0.05/GB
```

**Best For**: Cloud services, variable consumption

### Hybrid Plans

Combined fixed and usage pricing:

```yaml
Hybrid Example:
  Name: Business Plan
  Base: $99/month (includes 5 users)
  Additional Users: $15/user/month
  Storage: $0.10/GB over 100GB
```

**Best For**: Complex pricing models

## Creating Plans

### Step 1: Basic Information

```yaml
Plan Details:
  Name: Choose descriptive name
  Slug: auto-generated-from-name
  Description: Customer-facing description
  Internal Notes: Team-only notes
```

### Step 2: Pricing Configuration

```yaml
Pricing:
  Amount: 49.00
  Currency: USD
  Billing Interval: monthly | quarterly | yearly | custom
  Trial Period: 14 days (optional)
```

### Step 3: Features and Limits

```yaml
Features:
  - name: Team Members
    limit: 10
    overage: $5/member

  - name: API Calls
    limit: 50,000/month
    overage: $0.001/call

  - name: Storage
    limit: 100GB
    overage: $0.10/GB
```

### Step 4: Visibility and Status

```yaml
Settings:
  Status: active | draft | archived
  Visibility: public | private | hidden
  Available For:
    - New signups
    - Upgrades
    - Downgrades
```

## Billing Intervals

| Interval | Use Case | Discount |
|----------|----------|----------|
| Monthly | Low commitment | Base price |
| Quarterly | Medium commitment | 5-10% |
| Annual | High commitment | 15-20% |
| Custom | Enterprise | Negotiated |

### Annual Discount Example

```yaml
Monthly: $49/month ($588/year)
Annual: $39/month ($468/year)
Savings: $120/year (20% discount)
```

## Trial Periods

### Configuration

```yaml
Trial Settings:
  Duration: 14 days
  Require Payment: false
  Features: Full access
  Conversion Reminder: 3 days before end
```

### Trial Best Practices

- **Duration**: 7-14 days typical
- **Access**: Full features preferred
- **Communication**: Email at start, middle, end
- **Conversion**: Clear CTA before expiry

## Plan Comparison

Create effective plan comparison:

| Feature | Starter | Professional | Enterprise |
|---------|---------|--------------|------------|
| Price | $19/mo | $49/mo | $149/mo |
| Users | 3 | 10 | Unlimited |
| Storage | 10GB | 100GB | 1TB |
| Support | Email | Priority | Dedicated |
| API | 10K calls | 100K calls | Unlimited |

## Best Practices

### Pricing Strategy

1. **Value-Based**: Align price with customer value
2. **Competitive**: Research market rates
3. **Scalable**: Allow room for upgrades
4. **Simple**: Easy to understand

### Plan Structure

1. **3-4 Plans Maximum**: Avoid choice paralysis
2. **Clear Differentiation**: Obvious value gaps
3. **Anchor Pricing**: Position middle tier attractively
4. **Enterprise Option**: Custom for large customers

### Feature Gating

Strategically limit features:
- **Core Features**: Available to all
- **Advanced Features**: Higher tiers
- **Premium Features**: Top tier only

---

For plan changes and migrations, see [Upgrading and Downgrading](/kb/upgrading-downgrading-cancellations).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "understanding-subscription-plans") do |article|
  article.title = "Understanding Subscription Plans"
  article.category = billing_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Master subscription plan creation with flat-rate, tiered, usage-based, and hybrid pricing models, plus trial periods and best practices."
  article.content = plans_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Understanding Subscription Plans"

# Article 9: Managing Payment Methods
payment_methods_content = <<~MARKDOWN
# Managing Payment Methods

Configure payment methods to accept payments globally with multiple gateways and methods.

## Supported Payment Methods

### Credit/Debit Cards

| Network | Support | Regions |
|---------|---------|---------|
| Visa | ✅ Full | Global |
| Mastercard | ✅ Full | Global |
| American Express | ✅ Full | Global |
| Discover | ✅ Full | US primarily |

### Digital Wallets

| Wallet | Gateway | Regions |
|--------|---------|---------|
| Apple Pay | Stripe | US, EU, UK, etc. |
| Google Pay | Stripe | Global |
| PayPal | PayPal | Global |

### Bank Transfers

| Method | Gateway | Regions |
|--------|---------|---------|
| ACH | Stripe | US |
| SEPA | Stripe | EU |
| BACS | Stripe | UK |

## Gateway Configuration

### Stripe Setup

1. Navigate to **Settings > Payments**
2. Click **Connect Stripe**
3. Authorize via OAuth
4. Configure settings:

```yaml
Stripe Configuration:
  Mode: live | test
  Webhook Secret: whsec_...
  Statement Descriptor: POWERNODE
  Supported Methods:
    - card
    - apple_pay
    - google_pay
```

### PayPal Setup

1. Navigate to **Settings > Payments**
2. Click **Connect PayPal**
3. Enter API credentials
4. Configure webhook

```yaml
PayPal Configuration:
  Mode: live | sandbox
  Client ID: ...
  Client Secret: ...
  Webhook ID: ...
```

## Customer Payment Methods

### Adding Payment Method

Customers can add methods via:
- Customer portal self-service
- Admin dashboard (manual)
- API integration

### Default Payment Method

```yaml
Payment Method Priority:
  1. Customer's default method
  2. Most recently added
  3. Fallback method
```

### Updating Methods

For card updates:
- Expiration date changes
- New card replacement
- Billing address updates

## PCI Compliance

### Security Requirements

- Never store full card numbers
- Use tokenization (Stripe/PayPal)
- HTTPS for all transactions
- Regular security audits

### Powernode Compliance

- PCI DSS Level 1 compliant
- No raw card data stored
- Encrypted transmissions
- Secure payment forms

## Troubleshooting

### Common Decline Reasons

| Code | Reason | Solution |
|------|--------|----------|
| insufficient_funds | Low balance | Try different card |
| card_declined | General decline | Contact bank |
| expired_card | Card expired | Update expiration |
| invalid_cvc | Wrong security code | Re-enter CVC |

### Testing Cards (Stripe)

| Scenario | Card Number |
|----------|-------------|
| Success | 4242 4242 4242 4242 |
| Decline | 4000 0000 0000 0002 |
| Insufficient | 4000 0000 0000 9995 |
| Expired | 4000 0000 0000 0069 |

---

For payment processing details, see the comprehensive [Payment Processing Guide](/kb/payment-methods-processing-guide).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "managing-payment-methods") do |article|
  article.title = "Managing Payment Methods"
  article.category = billing_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Configure payment methods with Stripe and PayPal support for cards, digital wallets, and bank transfers with PCI compliance."
  article.content = payment_methods_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Managing Payment Methods"

# Article 10: Billing Cycles and Invoicing
billing_cycles_content = <<~MARKDOWN
# Billing Cycles and Invoicing

Understand billing cycles, invoice generation, and payment timing for subscription management.

## Billing Cycle Basics

### Cycle Types

| Type | Description | Example |
|------|-------------|---------|
| **Anniversary** | Bills on signup date | Signed up 15th, bills 15th |
| **Calendar** | Bills on fixed date | Always bills 1st |
| **Prorated** | Adjusts for partial periods | Mid-month signup |

### Billing Anchor

The anchor date determines when billing occurs:

```yaml
Subscription Started: January 15
Billing Anchor: 15th of each month
Next Bill Dates:
  - February 15
  - March 15
  - April 15
```

## Invoice Generation

### Automatic Invoicing

Invoices generate automatically:

1. **Advance Billing**: Invoice before period starts
2. **Arrears Billing**: Invoice after period ends
3. **Immediate**: Invoice at subscription creation

### Invoice Contents

```yaml
Invoice #INV-2024-0001
  Customer: Acme Corp
  Period: Jan 1 - Jan 31, 2024

  Line Items:
    - Professional Plan: $49.00
    - Additional Users (3): $15.00
    - Storage Overage (50GB): $5.00

  Subtotal: $69.00
  Tax (8%): $5.52
  Total: $74.52

  Due: February 1, 2024
```

### Invoice Customization

Configure invoice appearance:
- Company logo and branding
- Custom footer text
- Payment instructions
- Terms and conditions

## Tax Configuration

### Tax Settings

```yaml
Tax Configuration:
  Enable Tax: true
  Tax Provider: automatic | manual
  Default Rate: 0%

  Tax Rates by Region:
    - US-CA: 7.25%
    - US-NY: 8%
    - EU: VAT (varies)
```

### Tax Compliance

- Automatic tax calculation (via Stripe Tax)
- Tax exemptions for B2B
- Tax reporting exports
- Multiple jurisdiction support

## Payment Collection

### Automatic Collection

```yaml
Collection Settings:
  Attempt Payment: On invoice due date
  Retry Schedule:
    - Day 1: First retry
    - Day 3: Second retry
    - Day 7: Third retry
  Grace Period: 7 days
  Suspend After: 14 days
```

### Manual Collection

For special cases:
- Send payment reminders
- Mark as paid manually
- Record offline payments

## Invoice Delivery

### Delivery Methods

| Method | When |
|--------|------|
| Email | Automatic on generation |
| Dashboard | Always available |
| PDF Download | On demand |
| API | Programmatic access |

### Email Templates

Customize invoice emails:
- Subject line
- Body text
- Payment button
- Support contact

## Failed Payments

### Dunning Process

```yaml
Dunning Schedule:
  Day 0: Payment fails
    - Email: "Payment failed"
    - Retry payment

  Day 3: Second attempt
    - Email: "Action required"
    - Retry payment

  Day 7: Final notice
    - Email: "Service at risk"
    - Retry payment

  Day 14: Suspension
    - Email: "Service suspended"
    - Disable access
```

### Recovery Tips

- Clear payment failure messaging
- Easy update payment method
- Multiple retry attempts
- Personal outreach for high-value

---

For payment failure handling, see [Troubleshooting Common Issues](/kb/troubleshooting-common-issues).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "billing-cycles-invoicing") do |article|
  article.title = "Billing Cycles and Invoicing"
  article.category = billing_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Understand billing cycles, invoice generation, tax configuration, payment collection, and dunning processes for subscriptions."
  article.content = billing_cycles_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Billing Cycles and Invoicing"

# Article 11: Upgrading, Downgrading, and Cancellations
plan_changes_content = <<~MARKDOWN
# Upgrading, Downgrading, and Cancellations

Handle subscription changes smoothly with proper proration, timing, and customer communication.

## Upgrading Plans

### Upgrade Process

1. Customer selects new plan
2. System calculates proration
3. Payment collected (or credited)
4. Access upgraded immediately

### Proration Calculation

```yaml
Upgrade Example:
  Current: Basic ($19/mo), 15 days remaining
  New: Pro ($49/mo)

  Calculation:
    Credit: $19 × (15/30) = $9.50
    Charge: $49 × (15/30) = $24.50
    Net Charge: $24.50 - $9.50 = $15.00
```

### Immediate vs. End of Period

| Timing | Use Case |
|--------|----------|
| Immediate | Customer needs features now |
| End of Period | Planned upgrade, no urgency |

## Downgrading Plans

### Downgrade Options

```yaml
Downgrade Settings:
  Effective: end_of_period | immediate
  Proration: credit | forfeit
  Features: immediate_removal | end_of_period
```

### Best Practices

- **Grace Period**: Allow continued access
- **Data Retention**: Don't delete user data
- **Communication**: Confirm what changes
- **Win-back**: Offer incentives to stay

## Subscription Pause

### Pause Configuration

```yaml
Pause Settings:
  Max Duration: 90 days
  Billing: paused | reduced_rate
  Access: full | limited | none
  Resume: automatic | manual
```

### Pause vs. Cancel

| Action | Billing | Access | Data |
|--------|---------|--------|------|
| Pause | Stopped | Varies | Kept |
| Cancel | Stopped | Removed | Kept 30 days |

## Cancellation Workflow

### Cancellation Types

1. **Immediate**: Ends now, prorated refund
2. **End of Period**: Continues until paid period ends
3. **Scheduled**: Future date cancellation

### Cancellation Flow

```yaml
Cancellation Process:
  1. Customer initiates cancel
  2. Show retention offer (optional)
  3. Collect cancellation reason
  4. Confirm cancellation timing
  5. Send confirmation email
  6. Process at scheduled time
```

### Retention Strategies

Before completing cancellation:
- **Discount Offer**: X% off for Y months
- **Plan Downgrade**: Suggest cheaper plan
- **Pause Option**: Suggest pausing instead
- **Feature Highlight**: Remind of value

### Cancellation Reasons

Track why customers cancel:
- Too expensive
- Missing features
- Switching to competitor
- No longer needed
- Technical issues
- Poor support

## Refund Policies

### Refund Types

| Type | Calculation |
|------|-------------|
| Full | 100% of last payment |
| Prorated | Unused portion |
| Partial | Fixed amount |
| None | No refund |

### Refund Processing

```yaml
Refund Settings:
  Automatic: enabled | disabled
  Window: 30 days
  Method: original_payment_method
  Processing: 5-10 business days
```

## Subscription Reactivation

### Reactivating Cancelled Subscriptions

1. Customer initiates reactivation
2. Select plan (same or different)
3. Provide payment method
4. Confirm reactivation
5. Access restored immediately

### Win-back Campaigns

Reach out to cancelled customers:
- 7 days after: Check-in email
- 30 days after: Feature updates
- 90 days after: Special offer

## Handling Edge Cases

### Mid-Cycle Plan Changes

```yaml
Scenario: Multiple changes in one period

  Jan 1: Start Basic ($19)
  Jan 10: Upgrade to Pro ($49)
  Jan 20: Downgrade to Basic ($19)

  Resolution:
    - Track each change
    - Calculate net proration
    - Invoice/credit accordingly
```

### Failed Upgrade Payments

If upgrade payment fails:
- Keep current plan active
- Notify customer
- Retry payment
- Escalate if continues

---

For payment processing details, see [Payment Methods and Processing](/kb/payment-methods-processing-guide).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "upgrading-downgrading-cancellations") do |article|
  article.title = "Upgrading, Downgrading, and Cancellations"
  article.category = billing_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Handle subscription changes with proper proration, pause options, cancellation workflows, retention strategies, and reactivation processes."
  article.content = plan_changes_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Upgrading, Downgrading, and Cancellations"

puts "  ✅ Billing articles created (4 articles)"
