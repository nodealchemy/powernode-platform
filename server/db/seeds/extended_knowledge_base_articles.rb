# frozen_string_literal: true

# Extended Knowledge Base Articles for Powernode Platform
puts "Creating extended Knowledge Base articles..."

# Find the system admin user to be the author
admin_user = User.joins(:user_roles, :roles).where(roles: { name: 'system.admin' }).first

if admin_user.nil?
  # Try to find KB admin user created by main script
  admin_user = User.find_by(email: 'kb-admin@powernode.org')
  
  if admin_user.nil?
    puts "⚠️  No admin user found. Please run sample_knowledge_base_articles.rb first..."
    return
  end
end

# Get existing categories
category_records = {}
%w[getting-started subscription-management billing-payments user-management api-integrations troubleshooting admin-guides].each do |slug|
  category_records[slug.underscore.to_sym] = KnowledgeBaseCategory.find_by(slug: slug)
end

# Extended articles covering all major platform features
extended_articles = [
  # Getting Started Articles
  {
    category: :getting_started,
    title: 'Welcome to Powernode: Your Complete Platform Guide',
    slug: 'welcome-to-powernode-guide',
    content: %{
# Welcome to Powernode: Your Complete Platform Guide

Welcome to Powernode, the comprehensive subscription lifecycle management platform designed to streamline your business operations from customer acquisition to revenue optimization.

## What is Powernode?

Powernode is an all-in-one subscription management platform that provides:

- **Subscription Lifecycle Management**: Complete customer journey from trial to renewal
- **Flexible Billing Engine**: Support for multiple payment models and pricing strategies  
- **Payment Processing**: Integrated Stripe and PayPal with PCI compliance
- **Customer Management**: Comprehensive user and account administration
- **Analytics & Reporting**: Real-time insights into your subscription business
- **API-First Architecture**: Extensible platform with robust webhook system
- **Team Collaboration**: Role-based permissions and multi-user support

## Core Platform Components

### 1. Customer Dashboard
Your customers' central hub featuring:
- Subscription overview and management
- Billing history and payment methods
- Account settings and preferences
- Support and knowledge base access

### 2. Admin Dashboard
Powerful administrative interface with:
- Real-time business metrics and analytics
- Customer and subscription management
- Billing and payment oversight
- System configuration and settings
- Team and permission management

### 3. Billing Engine
Automated billing system supporting:
- Recurring subscription billing
- Usage-based billing models
- Proration and mid-cycle changes
- Multiple currencies and tax handling
- Dunning management and retry logic

### 4. Payment Processing
Secure payment infrastructure featuring:
- Stripe and PayPal integration
- PCI DSS compliance
- Multiple payment methods
- Automated payment retry
- Refund and chargeback management

## Getting Started Checklist

### Phase 1: Initial Setup (Day 1)
- [ ] Complete account verification
- [ ] Configure basic company information
- [ ] Set up your first subscription plan
- [ ] Configure payment gateway (Stripe or PayPal)
- [ ] Invite team members

### Phase 2: Configuration (Days 2-3)
- [ ] Customize customer portal branding
- [ ] Set up email notifications
- [ ] Configure tax settings (if applicable)
- [ ] Create additional subscription plans
- [ ] Test the customer signup flow

### Phase 3: Launch Preparation (Days 4-7)
- [ ] Import existing customers (if migrating)
- [ ] Configure webhooks for integrations
- [ ] Set up reporting and analytics
- [ ] Train your team on the platform
- [ ] Perform end-to-end testing

### Phase 4: Go Live (Week 2)
- [ ] Launch with a subset of customers
- [ ] Monitor initial transactions
- [ ] Gather team feedback
- [ ] Make necessary adjustments
- [ ] Full platform deployment

## Key Features Overview

### Subscription Management
Create and manage flexible subscription plans:
- **Multiple Billing Cycles**: Monthly, quarterly, yearly, or custom
- **Free Trials**: Configurable trial periods with automatic conversion
- **Plan Changes**: Seamless upgrades, downgrades, and modifications
- **Add-ons**: Additional features and usage-based components
- **Pause/Resume**: Temporary subscription suspension options

### Customer Experience
Deliver exceptional customer experiences:
- **Self-Service Portal**: Customers manage their own subscriptions
- **Transparent Billing**: Clear invoices and payment history
- **Flexible Payments**: Multiple payment methods and currencies
- **Support Integration**: Built-in help and knowledge base access
- **Mobile Optimized**: Full functionality on all devices

### Business Intelligence
Make data-driven decisions with:
- **Real-Time Dashboards**: Live metrics and KPIs
- **Revenue Analytics**: MRR, ARR, churn, and growth metrics
- **Customer Insights**: Lifecycle analysis and behavior patterns
- **Financial Reporting**: Comprehensive revenue and billing reports
- **Cohort Analysis**: Track customer groups over time

### Platform Integration
Connect with your existing tools:
- **REST API**: Complete programmatic access
- **Webhooks**: Real-time event notifications
- **Third-Party Apps**: CRM, accounting, and marketing integrations
- **Custom Development**: Extensible platform architecture
- **Data Export**: Comprehensive reporting and data extraction

## Common Use Cases

### SaaS Companies
- Monthly/annual software subscriptions
- Feature-based pricing tiers
- Usage metering and billing
- Free trial management
- Customer self-service

### Digital Services
- Content subscription services
- Professional services billing
- Training and education platforms
- Membership organizations
- Digital product sales

### E-commerce
- Subscription box services
- Recurring service billing
- Customer loyalty programs
- Seasonal subscription management
- Multi-channel sales integration

## Best Practices for Success

### 1. Plan Your Pricing Strategy
- Research competitor pricing models
- Consider customer value perception
- Plan for pricing experiments and changes
- Account for different customer segments
- Include room for plan evolution

### 2. Design Customer-Centric Flows
- Minimize friction in signup process
- Provide clear plan comparisons
- Offer flexible payment options
- Enable easy plan changes
- Implement graceful failure handling

### 3. Monitor Key Metrics
- Monthly Recurring Revenue (MRR)
- Customer Acquisition Cost (CAC)
- Customer Lifetime Value (LTV)
- Churn rate and reasons
- Payment failure rates

### 4. Optimize Continuously
- A/B test pricing and messaging
- Analyze customer feedback
- Monitor support ticket trends
- Review payment failure patterns
- Iterate on user experience

## Next Steps

### Immediate Actions
1. **Review this guide completely**
2. **Start with the setup checklist**
3. **Explore the admin dashboard**
4. **Create your first test subscription**
5. **Invite team members to collaborate**

### Learning Resources
- **Video Tutorials**: Step-by-step visual guides
- **API Documentation**: Complete technical reference
- **Best Practices**: Industry insights and recommendations
- **Community Forum**: Connect with other Powernode users
- **Live Training**: Scheduled onboarding sessions

### Support Options
- **Knowledge Base**: Comprehensive self-help resources
- **Email Support**: Detailed assistance for complex issues
- **Live Chat**: Real-time help for urgent questions
- **Phone Support**: Direct access to our expert team
- **Dedicated Success Manager**: For enterprise accounts

## Frequently Asked Questions

### Getting Started
**Q: How long does initial setup take?**
A: Basic setup can be completed in under an hour. Full configuration typically takes 2-3 days depending on complexity.

**Q: Can I import existing customer data?**
A: Yes, we provide data import tools and migration assistance for existing subscription businesses.

**Q: What payment methods are supported?**
A: We support all major credit cards, ACH/bank transfers, and digital wallets through Stripe and PayPal.

### Pricing and Billing
**Q: How does Powernode pricing work?**
A: We offer transparent, usage-based pricing with no setup fees. Contact sales for detailed pricing information.

**Q: Can I change plans after setup?**
A: Absolutely! Our platform is designed for flexibility, allowing plan changes without disruption.

**Q: What about international customers?**
A: We support multiple currencies and handle international tax compliance through our payment partners.

---

**Ready to get started?** Begin with our [Quick Setup Guide](/kb/quick-setup-guide) or schedule a personalized demo with our team.

**Need help?** Contact us at support@powernode.org or use the live chat feature.

**Last Updated**: #{Time.current.strftime('%B %d, %Y')}
},
    excerpt: 'Complete introduction to Powernode subscription management platform with setup guidance and best practices.',
    tags: %w[getting-started platform overview setup basics],
    is_featured: true,
    sort_order: 1
  },

  # Subscription Management Articles
  {
    category: :subscription_management,
    title: 'Complete Guide to Subscription Plans and Pricing',
    slug: 'subscription-plans-pricing-guide',
    content: %{
# Complete Guide to Subscription Plans and Pricing

Learn how to create, manage, and optimize subscription plans that drive revenue growth and customer satisfaction.

## Understanding Subscription Plans

Subscription plans are the foundation of your recurring revenue model. In Powernode, plans define:

- **Pricing Structure**: How much customers pay and when
- **Billing Cycles**: Frequency of charges (monthly, yearly, etc.)
- **Features Included**: What customers get access to
- **Trial Periods**: Free evaluation periods
- **Plan Limits**: Usage restrictions or allowances

## Types of Subscription Models

### 1. Flat-Rate Pricing
Single price for all features and unlimited usage.

**Best For:**
- Simple products with consistent value delivery
- Companies wanting predictable revenue
- Markets where complexity creates friction

**Example Configuration:**
```
Plan: Professional
Price: $99/month
Features: All features included
Billing: Monthly
Trial: 14 days
```

**Pros:**
- Simple for customers to understand
- Predictable revenue forecasting
- Low support overhead

**Cons:**
- May leave money on the table with high-usage customers
- Difficult to segment different customer needs
- Limited expansion revenue opportunities

### 2. Tiered Pricing
Multiple plans with different feature sets and pricing levels.

**Common Tier Structure:**
- **Starter**: Basic features for individuals/small teams
- **Professional**: Enhanced features for growing businesses  
- **Enterprise**: Advanced features for large organizations

**Example Configuration:**
```
Starter Plan:
- Price: $29/month
- Users: Up to 5
- Storage: 10GB
- Support: Email only

Professional Plan:
- Price: $99/month  
- Users: Up to 25
- Storage: 100GB
- Support: Email + Chat

Enterprise Plan:
- Price: $299/month
- Users: Unlimited
- Storage: 1TB
- Support: Phone + Dedicated rep
```

**Best Practices:**
- Limit tiers to 3-4 options to avoid decision paralysis
- Make the middle tier most attractive (anchor pricing)
- Clearly differentiate value between tiers
- Include logical upgrade paths

### 3. Usage-Based Pricing
Customers pay based on their actual consumption.

**Usage Metrics Examples:**
- API calls made
- Storage space used
- Number of transactions processed
- Users active in the system
- Data transfer volume

**Implementation Options:**

#### Pay-Per-Use
```
Base Plan: $49/month
Additional Usage: $0.10 per API call over 1,000
Billing: Monthly base + usage charges
```

#### Usage Tiers
```
Tier 1 (0-1,000 calls): $49/month
Tier 2 (1,001-5,000 calls): $99/month  
Tier 3 (5,001-15,000 calls): $199/month
Tier 4 (15,001+ calls): $299/month + $0.05 per additional call
```

**Advantages:**
- Aligns cost with value received
- Appeals to cost-conscious customers
- Natural expansion revenue
- Eliminates waste for light users

**Challenges:**
- Unpredictable revenue
- More complex billing
- Requires usage tracking infrastructure
- Potential for bill shock

### 4. Hybrid Models
Combine multiple pricing approaches for maximum flexibility.

**Example: Base + Usage**
```
Plan: Growth
Base Price: $199/month (includes 10,000 API calls)
Overage: $0.02 per additional API call
Users: Up to 50 included, $15/month per additional user
```

**Example: Freemium + Tiers**
```
Free Plan: Limited features, 100 API calls/month
Starter Plan: $29/month, 2,000 API calls/month
Pro Plan: $99/month, 10,000 API calls/month + advanced features
```

## Creating Your First Subscription Plan

### Step 1: Access Plan Management
1. Navigate to **Admin Dashboard** > **Plans**
2. Click **Create New Plan**
3. Choose your plan template or start from scratch

### Step 2: Basic Plan Information

#### Plan Details
- **Plan Name**: Clear, descriptive name (e.g., "Professional Plan")
- **Plan Code**: Internal identifier (e.g., "PROF_MONTHLY")
- **Description**: Brief explanation of plan benefits
- **Plan Category**: Group similar plans together

#### Pricing Configuration
- **Base Price**: Primary monthly/yearly charge
- **Currency**: USD, EUR, GBP, etc.
- **Billing Interval**: Monthly, yearly, quarterly, custom
- **Setup Fee**: One-time charge (optional)
- **Trial Period**: Free trial duration in days

#### Plan Features
Define what's included:
- **Feature Limits**: Users, storage, API calls, etc.
- **Feature Access**: Which features are enabled/disabled
- **Support Level**: Email, chat, phone support tiers
- **Integration Access**: Available third-party integrations

### Step 3: Advanced Settings

#### Proration Settings
- **Mid-Cycle Changes**: How to handle plan upgrades/downgrades
- **Proration Policy**: Full month, daily proration, or next cycle
- **Credit Handling**: How to apply unused time credits

#### Trial Configuration
- **Trial Type**: Free trial or paid trial
- **Trial Duration**: Days of free access
- **Credit Card Required**: Whether payment method is needed upfront
- **Auto-Conversion**: Automatic billing after trial expires

#### Plan Limits and Quotas
Set usage boundaries:
- **Hard Limits**: System enforced restrictions
- **Soft Limits**: Warnings before overage charges
- **Overage Handling**: Block usage vs. charge for overages
- **Reset Periods**: When limits refresh (monthly, etc.)

### Step 4: Testing Your Plan
Before going live:
1. **Create Test Subscription**: Use test payment methods
2. **Test Upgrade/Downgrade**: Verify proration logic
3. **Test Trial Flow**: Ensure proper conversion
4. **Verify Billing**: Check invoice generation and payment processing
5. **Test Limits**: Confirm quota enforcement works correctly

## Plan Management Best Practices

### Pricing Strategy
1. **Research Competition**: Understand market positioning
2. **Value-Based Pricing**: Price based on customer value, not costs
3. **Psychology of Pricing**: Use $9, $99, $999 pricing patterns
4. **Anchor High**: Present highest-priced option first
5. **Test Regularly**: A/B test pricing changes carefully

### Plan Architecture
1. **Clear Differentiation**: Each tier should have obvious value differences
2. **Logical Progression**: Natural upgrade path between tiers  
3. **Feature Gating**: Reserve compelling features for higher tiers
4. **Avoid Feature Cramming**: Don't overwhelm lower tiers
5. **Upgrade Incentives**: Make upgrading appealing and beneficial

### Customer Communication
1. **Transparent Pricing**: No hidden fees or confusing terms
2. **Value Messaging**: Focus on benefits, not just features
3. **Comparison Charts**: Help customers choose the right plan
4. **Change Notifications**: Alert customers before price changes
5. **Grandfathering**: Consider protecting existing customers from price increases

## Managing Plan Changes

### Plan Modifications
When updating existing plans:
1. **Grandfathering**: Keep existing customers on old pricing
2. **Migration Strategy**: Plan for moving customers to new plans
3. **Communication**: Notify customers well in advance
4. **Effective Dates**: Choose change timing carefully

### Deprecating Plans
To discontinue a plan:
1. **Stop New Signups**: Prevent new subscriptions
2. **Notify Existing Customers**: Provide advance notice
3. **Offer Alternatives**: Suggest comparable replacement plans
4. **Migration Timeline**: Give customers time to decide
5. **Support**: Provide extra assistance during transition

### Seasonal Plans
Create time-limited offerings:
1. **Limited Duration**: Set clear start/end dates
2. **Promotional Pricing**: Discount to drive urgency
3. **Marketing Integration**: Coordinate with campaign timing
4. **Conversion Strategy**: Plan post-promotion pricing

## Advanced Plan Features

### Add-Ons and Extensions
Expand plan value with optional extras:
- **User Seats**: Additional team members
- **Storage Expansion**: Extra data allowances  
- **Feature Unlocks**: Premium functionality access
- **Support Upgrades**: Enhanced support levels
- **Integration Packs**: Third-party service access

### Custom Enterprise Plans
For large customers:
- **Custom Pricing**: Volume discounts and special terms
- **Feature Customization**: Tailored functionality
- **Contract Terms**: Multi-year commitments
- **Dedicated Support**: Assigned account management
- **SLA Guarantees**: Performance and uptime commitments

### Plan Analytics and Optimization

#### Key Metrics to Track
- **Plan Popularity**: Which plans are chosen most often
- **Revenue Per Plan**: Average revenue by plan type
- **Upgrade Rates**: How often customers move up tiers
- **Downgrade Rates**: Customer tier regression patterns
- **Trial Conversion**: Free to paid conversion rates

#### Optimization Strategies
1. **A/B Test Pricing**: Test different price points
2. **Feature Analysis**: Identify most valuable features
3. **Conversion Funnels**: Optimize signup and upgrade flows
4. **Cohort Analysis**: Track customer behavior over time
5. **Feedback Integration**: Use customer input for improvements

## Troubleshooting Common Issues

### Low Conversion Rates
**Symptoms**: Few trial-to-paid conversions
**Solutions**:
- Reduce friction in signup process
- Improve trial experience
- Add social proof and testimonials
- Clarify value proposition
- Optimize pricing psychology

### High Churn After Trial
**Symptoms**: Customers cancel immediately after trial
**Solutions**:
- Extend trial period
- Improve onboarding experience
- Add usage-based notifications
- Provide proactive support
- Reassess plan-market fit

### Upgrade Resistance  
**Symptoms**: Customers stay on lowest tier indefinitely
**Solutions**:
- Add compelling higher-tier features
- Implement usage limits
- Create upgrade incentives
- Improve tier messaging
- Add social proof for higher tiers

---

**Ready to create your first plan?** Start with our [Plan Creation Wizard](/admin/plans/new) or contact our success team for personalized guidance.

**Need pricing strategy help?** Schedule a consultation with our revenue optimization specialists.
},
    excerpt: 'Comprehensive guide to creating and managing subscription plans, pricing strategies, and revenue optimization.',
    tags: %w[subscriptions pricing plans strategy billing],
    is_featured: true,
    sort_order: 1
  },

  # Billing and Payment Articles
  {
    category: :billing_payments,
    title: 'Payment Gateway Setup: Stripe and PayPal Integration',
    slug: 'payment-gateway-setup-stripe-paypal',
    content: %{
# Payment Gateway Setup: Stripe and PayPal Integration

Configure secure payment processing with Stripe and PayPal to handle customer payments, subscriptions, and billing automatically.

## Payment Gateway Overview

Powernode supports two industry-leading payment processors:

### Stripe
**Best For:**
- Credit card processing
- ACH/bank transfers
- International payments
- Advanced subscription billing
- Developer-friendly APIs

**Supported Payment Methods:**
- All major credit/debit cards
- Apple Pay, Google Pay
- Bank transfers (ACH)
- SEPA Direct Debit (Europe)
- Various local payment methods

### PayPal
**Best For:**
- PayPal account holders
- International marketplaces
- Buyer protection preferences
- Quick checkout flows
- Mobile payments

**Supported Payment Methods:**
- PayPal balance
- PayPal Credit
- Linked bank accounts
- Credit/debit cards via PayPal
- PayPal Pay in 4 (installments)

## Prerequisites

### Required Information
Before setting up payment gateways:

#### Business Information
- Legal business name and address
- Tax identification number (EIN/VAT)
- Business type and industry
- Bank account details for payouts
- Business website and description

#### Technical Requirements
- SSL certificate on your website
- Access to webhook endpoints
- Development/testing capabilities
- PCI compliance understanding

### Account Requirements

#### Stripe Account
1. **Sign up at**: [stripe.com](https://stripe.com)
2. **Verify business**: Provide business documentation
3. **Connect bank account**: For automatic payouts
4. **Enable features**: Subscriptions, webhooks, etc.
5. **Get API keys**: Publishable and secret keys

#### PayPal Business Account  
1. **Sign up at**: [paypal.com/business](https://paypal.com/business)
2. **Verify business**: Link bank account and verify identity
3. **Enable subscriptions**: Activate recurring payments
4. **Get API credentials**: Client ID and secret
5. **Configure webhooks**: For real-time notifications

## Stripe Integration Setup

### Step 1: Access Gateway Settings
1. Navigate to **Admin Dashboard** > **Payment Gateways**
2. Click **Configure Stripe**
3. Select **Live** or **Test** mode

### Step 2: API Configuration

#### Test Mode Setup (Development)
```
Publishable Key: pk_test_[your_test_key]
Secret Key: sk_test_[your_test_secret]
Webhook Endpoint: https://yourapp.com/webhooks/stripe
Webhook Secret: whsec_[your_webhook_secret]
```

#### Live Mode Setup (Production)
```
Publishable Key: pk_live_[your_live_key]  
Secret Key: sk_live_[your_live_secret]
Webhook Endpoint: https://yourapp.com/webhooks/stripe
Webhook Secret: whsec_[your_live_webhook_secret]
```

### Step 3: Stripe Webhook Configuration

#### Required Webhook Events
Configure these events in your Stripe dashboard:

**Customer Events:**
- `customer.created`
- `customer.updated`
- `customer.deleted`

**Subscription Events:**
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `customer.subscription.trial_will_end`

**Payment Events:**
- `invoice.payment_succeeded`
- `invoice.payment_failed`
- `payment_method.attached`
- `payment_method.detached`

**Billing Events:**
- `invoice.created`
- `invoice.finalized`
- `invoice.paid`
- `invoice.payment_action_required`

#### Webhook Setup Steps
1. **Go to Stripe Dashboard** > **Developers** > **Webhooks**
2. **Click "Add endpoint"**
3. **Enter endpoint URL**: `https://yourdomain.com/webhooks/stripe`
4. **Select events**: Choose events listed above
5. **Add endpoint** and copy the **signing secret**
6. **Enter signing secret** in Powernode configuration

### Step 4: Advanced Stripe Settings

#### Payment Method Configuration
```yaml
Accepted Cards:
  - Visa
  - Mastercard  
  - American Express
  - Discover
  
Digital Wallets:
  - Apple Pay: Enabled
  - Google Pay: Enabled
  
Bank Payments:
  - ACH Direct Debit: Enabled
  - SEPA Direct Debit: Enabled (EU)
  
Local Payment Methods:
  - iDEAL: Enabled (Netherlands)
  - SOFORT: Enabled (Europe)
  - Bancontact: Enabled (Belgium)
```

#### Subscription Settings
```yaml
Billing Configuration:
  - Proration: Enabled
  - Invoice Generation: Automatic
  - Payment Retry: Smart retries enabled
  - Late Fees: Configurable
  
Dunning Management:
  - Failed Payment Retries: 3 attempts
  - Retry Schedule: Day 3, 5, 7
  - Subscription Cancellation: After final retry
```

## PayPal Integration Setup

### Step 1: Access PayPal Configuration
1. Navigate to **Admin Dashboard** > **Payment Gateways**
2. Click **Configure PayPal**
3. Select **Sandbox** or **Live** environment

### Step 2: PayPal API Configuration

#### Sandbox Setup (Testing)
```
Environment: Sandbox
Client ID: [sandbox_client_id]
Client Secret: [sandbox_client_secret]  
Webhook ID: [sandbox_webhook_id]
```

#### Live Setup (Production)
```
Environment: Live
Client ID: [live_client_id]
Client Secret: [live_client_secret]
Webhook ID: [live_webhook_id]
```

### Step 3: PayPal Webhook Configuration

#### Required Webhook Events
Set up these events in PayPal Developer console:

**Billing Events:**
- `BILLING.SUBSCRIPTION.CREATED`
- `BILLING.SUBSCRIPTION.UPDATED`
- `BILLING.SUBSCRIPTION.CANCELLED`
- `BILLING.SUBSCRIPTION.SUSPENDED`
- `BILLING.SUBSCRIPTION.ACTIVATED`

**Payment Events:**
- `PAYMENT.SALE.COMPLETED`
- `PAYMENT.SALE.DENIED`
- `PAYMENT.SALE.REFUNDED`
- `PAYMENT.SALE.REVERSED`

#### Webhook Setup Process
1. **Go to PayPal Developer Console**
2. **Select your application**
3. **Add webhook** with URL: `https://yourdomain.com/webhooks/paypal`
4. **Select event types** from list above
5. **Save webhook** and copy the **Webhook ID**
6. **Enter Webhook ID** in Powernode configuration

### Step 4: PayPal Product and Plan Setup

#### Create PayPal Products
Products represent your service offerings:
```yaml
Product Configuration:
  - Name: "Professional Plan"
  - Type: "SERVICE"  
  - Category: "SOFTWARE"
  - Description: "Monthly professional subscription"
  - Home URL: "https://yourdomain.com"
```

#### Create PayPal Billing Plans
Plans define pricing and billing cycles:
```yaml
Plan Configuration:
  - Product ID: [from_product_creation]
  - Name: "Professional Monthly"
  - Status: "ACTIVE"
  - Billing Cycles:
    - Frequency: MONTH
    - Tenure Type: REGULAR  
    - Sequence: 1
    - Total Cycles: 0 (infinite)
    - Pricing: $99.00 USD
```

## Testing Payment Gateways

### Stripe Test Cards
Use these test card numbers in test mode:

**Successful Payments:**
- `4242424242424242` - Visa
- `5555555555554444` - Mastercard
- `378282246310005` - American Express

**Failed Payments:**
- `4000000000000002` - Card declined
- `4000000000009995` - Insufficient funds
- `4000000000000119` - Processing error

**Special Cases:**
- `4000000000003220` - 3D Secure authentication required
- `4000000000000341` - Card with ZIP code failure

### PayPal Test Accounts
Create sandbox accounts for testing:

**Test Buyer Account:**
- Email: buyer@example.com
- Password: [test_password]
- Balance: $5,000 (for testing)

**Test Seller Account:**
- Email: seller@example.com  
- Password: [test_password]
- Verified: Yes

### Test Scenarios
Execute these test cases:

1. **New Subscription Creation**
   - Create test subscription
   - Verify webhook delivery
   - Check invoice generation
   - Confirm customer record

2. **Payment Processing**
   - Process successful payment
   - Test failed payment scenarios
   - Verify retry mechanisms
   - Check notification emails

3. **Subscription Changes**
   - Test plan upgrades
   - Test plan downgrades  
   - Verify proration calculations
   - Check billing adjustments

## Security Best Practices

### API Key Management
- **Never expose secret keys** in client-side code
- **Use environment variables** for API keys
- **Rotate keys regularly** (quarterly recommended)
- **Implement key access controls**
- **Monitor key usage** for anomalies

### Webhook Security
- **Verify webhook signatures** for all incoming requests
- **Use HTTPS only** for webhook endpoints
- **Implement idempotency** to handle duplicate events
- **Log webhook events** for debugging and audit trails
- **Set up monitoring** for failed webhook deliveries

### PCI Compliance
- **Never store card data** on your servers
- **Use tokenization** for recurring payments
- **Implement SSL/TLS** for all payment pages
- **Regular security audits** and vulnerability scans
- **Employee training** on payment data handling

## Troubleshooting Common Issues

### Stripe Issues

#### "Authentication Required" Errors
**Cause**: 3D Secure authentication needed
**Solution**: 
- Enable SCA handling in Stripe configuration
- Update payment flow to handle authentication
- Test with 3D Secure test cards

#### Webhook Delivery Failures
**Cause**: Endpoint not responding or incorrect signature verification
**Solution**:
- Check webhook endpoint availability
- Verify webhook signature validation
- Review webhook event logs in Stripe dashboard
- Implement proper error handling and retries

#### Subscription Creation Failures
**Cause**: Invalid payment method or customer data
**Solution**:
- Validate customer data before API calls
- Ensure payment method is properly attached
- Check for required fields in subscription creation
- Review Stripe logs for specific error messages

### PayPal Issues

#### "Subscription Not Found" Errors
**Cause**: PayPal subscription not properly created or expired
**Solution**:
- Verify product and plan creation in PayPal
- Check subscription status in PayPal dashboard
- Ensure proper API credentials
- Validate webhook event processing

#### Payment Authorization Failures  
**Cause**: Buyer account issues or insufficient funds
**Solution**:
- Check buyer account status
- Verify payment method validity
- Review PayPal transaction logs
- Implement proper error messaging for customers

### General Issues

#### Failed Payment Handling
**Symptoms**: Customers not notified of payment failures
**Solutions**:
- Configure dunning management settings
- Set up payment failure notifications
- Implement grace periods for service access
- Provide clear payment update instructions

#### Currency Conversion Problems
**Symptoms**: Incorrect amounts or currency errors  
**Solutions**:
- Verify currency settings in gateway configuration
- Check exchange rate handling
- Validate currency codes (USD, EUR, GBP)
- Test international payment scenarios

## Monitoring and Maintenance

### Key Metrics to Track
- **Payment Success Rate**: Percentage of successful transactions
- **Failed Payment Rate**: Track and investigate failures
- **Webhook Delivery**: Monitor webhook success rates
- **Processing Time**: Average payment processing duration
- **Dispute Rate**: Chargebacks and disputed transactions

### Regular Maintenance Tasks
- **Review gateway settings** monthly
- **Update webhook configurations** as needed
- **Monitor error logs** weekly
- **Test payment flows** before major releases
- **Review and rotate API keys** quarterly

### Compliance Monitoring
- **PCI compliance** annual assessment
- **Security audit** quarterly reviews
- **Payment regulations** stay updated on changes
- **Data retention** comply with regional requirements

---

**Ready to configure payments?** Start with our [Gateway Setup Wizard](/admin/payment-gateways/setup) or contact support for personalized assistance.

**Need help with testing?** Use our [Payment Testing Guide](/kb/payment-testing-guide) for comprehensive test scenarios.
},
    excerpt: 'Complete guide to setting up and configuring Stripe and PayPal payment gateways for secure subscription billing.',
    tags: %w[payments stripe paypal billing setup integration],
    is_featured: true,
    sort_order: 1
  },

  # User Management Article
  {
    category: :user_management,
    title: 'User Permissions and Role Management Guide',
    slug: 'user-permissions-role-management',
    content: %{
# User Permissions and Role Management Guide

Master Powernode's permission-based access control system to securely manage team access and maintain proper system security.

## Understanding Powernode's Permission System

Powernode uses a **permission-based access control** system rather than simple role assignments. This provides:

- **Granular Control**: Precise access management for specific features
- **Flexible Assignments**: Users can have multiple permission combinations
- **Security Best Practice**: Principle of least privilege implementation
- **Scalable Administration**: Easy management as teams grow

### Core Concepts

#### Permissions
Individual capabilities that grant access to specific features:
- `users.read` - View user information
- `billing.manage` - Full billing access
- `subscriptions.create` - Create new subscriptions
- `admin.access` - Access administrative features

#### Roles  
Pre-configured permission bundles for common job functions:
- **System Admin**: All permissions across the platform
- **Account Manager**: Account-scoped permissions
- **Billing Manager**: Financial operations permissions
- **Account Member**: Basic user permissions

#### Assignment Philosophy
🎯 **Best Practice**: Assign permissions directly when possible, use roles for convenience.

## Available Permissions

### User Management Permissions
Control access to user-related features:

- `users.read` - View user profiles and information
- `users.create` - Add new users to the account
- `users.update` - Edit user profiles and settings
- `users.delete` - Remove users from the account
- `users.manage` - Full user management (includes all above)
- `team.manage` - Manage team structure and assignments

### Billing and Financial Permissions
Manage financial operations and billing:

- `billing.read` - View billing information and history
- `billing.update` - Modify billing settings and payment methods
- `billing.manage` - Full billing access (includes all above)
- `invoices.create` - Generate and send invoices
- `payments.process` - Handle payment processing and refunds

### Subscription Management Permissions
Control subscription lifecycle operations:

- `subscriptions.read` - View subscription information
- `subscriptions.create` - Create new customer subscriptions
- `subscriptions.update` - Modify existing subscriptions
- `subscriptions.delete` - Cancel or delete subscriptions
- `subscriptions.manage` - Full subscription management

### Administrative Permissions
System-level access and configuration:

- `admin.access` - Access administrative dashboard
- `system.admin` - Full system administration
- `accounts.manage` - Manage multiple customer accounts
- `settings.update` - Modify system settings and configuration

### Content Management Permissions
Knowledge Base and content operations:

- `kb.view` - View knowledge base articles
- `kb.write` - Create and edit knowledge base content
- `kb.manage` - Full knowledge base management
- `kb.admin` - Knowledge base system administration

### Analytics and Reporting Permissions
Data access and reporting capabilities:

- `analytics.read` - View analytics and reports
- `analytics.export` - Export data and generate reports
- `reports.generate` - Create custom reports and dashboards

## Standard Roles Explained

### System Administrator (`system.admin`)
**Purpose**: Complete platform control
**Permissions**: All available permissions
**Use Cases**: 
- Platform setup and configuration
- System maintenance and troubleshooting
- Security management and compliance
- Advanced feature configuration

**Typical Users**: 
- IT administrators
- Platform owners
- Senior technical staff

### Account Manager (`account.manager`)
**Purpose**: Customer account administration
**Key Permissions**:
- `users.manage` - Full user management
- `billing.manage` - Complete billing control
- `subscriptions.manage` - Subscription lifecycle
- `analytics.read` - Business metrics access
- `admin.access` - Admin dashboard access

**Use Cases**:
- Customer success management
- Billing issue resolution
- Team management and onboarding
- Business metrics monitoring

**Typical Users**:
- Customer success managers
- Account administrators
- Department heads

### Billing Manager (`billing.manager`)
**Purpose**: Financial operations specialist
**Key Permissions**:
- `billing.manage` - All billing operations
- `invoices.create` - Invoice management
- `payments.process` - Payment handling
- `analytics.read` - Financial reporting
- `subscriptions.read` - Subscription viewing

**Use Cases**:
- Invoice generation and management
- Payment processing and reconciliation
- Financial reporting and analysis
- Billing issue resolution

**Typical Users**:
- Accounting team members
- Finance managers
- Billing specialists

### Account Member (`account.member`)
**Purpose**: Standard user access
**Key Permissions**:
- `users.read` - View team members
- `billing.read` - View billing information
- `subscriptions.read` - View subscriptions
- `kb.view` - Access knowledge base

**Use Cases**:
- General platform usage
- Self-service account access
- Basic information viewing
- Knowledge base access

**Typical Users**:
- End users
- Basic team members
- Customers with limited needs

## Managing User Permissions

### Adding New Users

#### Step 1: Navigate to User Management
1. Go to **Admin Dashboard** > **Users**
2. Click **Invite New User**
3. Choose between **Team Member** or **Customer** user type

#### Step 2: User Information
```yaml
Basic Information:
  First Name: John
  Last Name: Smith
  Email: john.smith@company.com
  Department: Sales (optional)
  Job Title: Sales Manager (optional)
```

#### Step 3: Permission Assignment

**Option A: Role-Based Assignment** (Recommended for standard cases)
```yaml
Primary Role: account.manager
Additional Permissions: 
  - analytics.export (if needed for reporting)
  - kb.write (if contributing to documentation)
```

**Option B: Custom Permission Assignment**
```yaml
Selected Permissions:
  - users.read
  - users.update  
  - billing.read
  - subscriptions.manage
  - analytics.read
```

#### Step 4: Account Settings
```yaml
Account Configuration:
  Email Verification: Required
  Two-Factor Authentication: Recommended
  Session Timeout: 8 hours
  Password Requirements: Strong
```

### Modifying Existing Users

#### Permission Updates
1. **Navigate to User Profile**: Admin Dashboard > Users > [User Name]
2. **Review Current Permissions**: Check existing access levels
3. **Add Permissions**: Grant additional capabilities as needed
4. **Remove Permissions**: Revoke unnecessary access
5. **Audit Changes**: Document permission modifications

#### Role Changes
1. **Assess Current Role**: Review existing role assignment
2. **Plan Transition**: Consider impact of role change
3. **Update Role**: Assign new role
4. **Verify Access**: Test that new permissions work correctly
5. **Communicate**: Inform user of access changes

### Bulk User Management

#### CSV Import Process
1. **Download Template**: Get user import CSV template
2. **Prepare Data**: Fill in user information and permissions
3. **Upload File**: Use bulk import tool
4. **Review Preview**: Check assignments before processing
5. **Process Import**: Complete bulk user creation
6. **Verify Results**: Confirm all users created correctly

#### Example CSV Format:
```csv
first_name,last_name,email,role,additional_permissions
John,Smith,john@company.com,account.manager,analytics.export
Jane,Doe,jane@company.com,billing.manager,
Mike,Johnson,mike@company.com,account.member,kb.write
```

## Permission Best Practices

### Security Principles

#### Principle of Least Privilege
- **Start Minimal**: Begin with minimal required permissions
- **Add Gradually**: Increase access as needs are proven
- **Regular Review**: Audit permissions quarterly
- **Remove Unused**: Clean up unnecessary permissions

#### Separation of Duties
- **Financial Controls**: Separate billing from user management
- **Administrative Boundaries**: Limit system admin roles
- **Customer Access**: Separate customer and internal user permissions
- **Audit Trail**: Maintain logs of permission changes

### Organizational Structures

#### Department-Based Permissions
```yaml
Sales Team:
  Base Role: account.member
  Additional: subscriptions.read, analytics.read
  
Finance Team:
  Base Role: billing.manager
  Additional: analytics.export, reports.generate
  
Customer Success:
  Base Role: account.manager
  Additional: kb.write, team.manage
  
IT/Admin:
  Base Role: system.admin
  Additional: All permissions available
```

#### Project-Based Access
```yaml
Implementation Project:
  Team Lead: account.manager + system.admin
  Developers: admin.access + settings.update
  QA Team: users.read + subscriptions.read
  
Customer Onboarding:
  Success Manager: account.manager
  Billing Specialist: billing.manager
  Support Agent: users.read + kb.view
```

### Permission Auditing

#### Regular Review Schedule
- **Weekly**: Review new user assignments
- **Monthly**: Audit permission changes and usage
- **Quarterly**: Comprehensive access review
- **Annually**: Full security audit and compliance check

#### Audit Checklist
- [ ] **Unused Permissions**: Remove permissions not used in 90 days
- [ ] **Over-Privileged Users**: Check for excessive access
- [ ] **Role Drift**: Verify roles match job functions
- [ ] **Shared Accounts**: Eliminate shared login credentials
- [ ] **External Access**: Review third-party integrations
- [ ] **Documentation**: Update permission documentation

## Troubleshooting Access Issues

### Common Permission Problems

#### "Access Denied" Errors
**Symptoms**: User cannot access expected features
**Diagnosis Steps**:
1. Check user's assigned permissions
2. Verify feature requires specific permission
3. Confirm permission is active/not suspended
4. Check for conflicting security settings

**Solutions**:
- Grant missing permissions
- Update user role if appropriate
- Clear user session and re-authenticate
- Contact system administrator for review

#### Missing Dashboard Features
**Symptoms**: Expected menu items or features not visible
**Diagnosis Steps**:
1. Review required permissions for feature
2. Check user's current permission list
3. Verify feature is enabled for account
4. Confirm browser cache is cleared

**Solutions**:
- Add required permission to user
- Update user role to include needed access
- Enable feature at account level
- Refresh browser/clear cache

#### Billing Access Issues
**Symptoms**: Cannot view or modify billing information
**Common Causes**:
- Missing `billing.read` or `billing.manage` permissions
- Role doesn't include financial access
- Account-level billing restrictions

**Solutions**:
- Grant appropriate billing permissions
- Update to billing manager role
- Check account billing settings
- Verify payment gateway configuration

### Permission Conflicts

#### Overlapping Roles
**Problem**: User has multiple roles with conflicting permissions
**Solution**: 
- Consolidate to single primary role
- Use custom permission assignment
- Document special access requirements
- Regular audit to prevent conflicts

#### Inherited Permissions
**Problem**: User inherits unexpected permissions from group membership
**Solution**:
- Review group permission assignments
- Use direct user permissions when needed
- Maintain clear group permission documentation
- Implement permission precedence rules

## Advanced Permission Features

### Conditional Access
Set up conditional permissions based on:
- **Time-based access**: Temporary elevated permissions
- **Location restrictions**: IP-based access controls
- **Device requirements**: Multi-factor authentication
- **Session limits**: Maximum concurrent sessions

### Permission Templates
Create reusable permission sets:
- **New Employee Template**: Standard starter permissions
- **Manager Template**: Supervisory access levels
- **Contractor Template**: Limited-time access
- **Executive Template**: High-level reporting access

### API Access Management
Control programmatic access:
- **API Key Permissions**: Scope API keys to specific operations
- **Webhook Access**: Limit webhook endpoint permissions
- **Integration Permissions**: Third-party service access
- **Rate Limiting**: Control API usage per user/role

---

**Need help with permissions?** Contact our support team at support@powernode.org or use our [Permission Troubleshooting Guide](/kb/permission-troubleshooting).

**Setting up a new team?** Try our [Team Setup Wizard](/admin/users/team-setup) for guided permission configuration.
},
    excerpt: 'Complete guide to managing user permissions and roles in Powernode\'s security system.',
    tags: %w[users permissions roles security admin team],
    is_featured: true,
    sort_order: 1
  },

  # API Integration Article
  {
    category: :api_integrations,
    title: 'API Integration Guide: Getting Started with Powernode APIs',
    slug: 'api-integration-guide-getting-started',
    content: %{
# API Integration Guide: Getting Started with Powernode APIs

Learn how to integrate with Powernode's REST API to build custom applications, automate workflows, and extend platform functionality.

## API Overview

The Powernode API is a RESTful web service that provides programmatic access to all platform features:

### Key Features
- **RESTful Design**: Standard HTTP methods and status codes
- **JSON Format**: All requests and responses use JSON
- **Comprehensive Coverage**: Access to all platform features
- **Real-time Webhooks**: Event-driven notifications
- **Rate Limited**: Fair usage policies to ensure reliability
- **Versioned**: Stable API with backward compatibility

### API Characteristics
- **Base URL**: `https://api.powernode.com/v1`
- **Authentication**: Bearer token (JWT)
- **Rate Limits**: 1000 requests per hour per API key
- **Response Format**: Consistent JSON structure
- **HTTPS Only**: All communication encrypted

### Supported Operations
- **Customer Management**: Users, accounts, subscriptions
- **Billing Operations**: Invoices, payments, refunds
- **Plan Management**: Subscription plans and features
- **Analytics**: Metrics, reports, and business intelligence
- **Webhook Configuration**: Event subscriptions and delivery

## API Authentication

### API Key Management

#### Creating API Keys
1. **Navigate to API Settings**: Admin Dashboard > API Keys
2. **Click "Create New API Key"**
3. **Configure Key Properties**:
   ```yaml
   Name: "Customer Integration"
   Description: "CRM integration for customer sync"
   Permissions: 
     - users.read
     - users.update
     - subscriptions.read
   Environment: Production
   Rate Limit: 1000/hour
   ```
4. **Generate Key**: System creates secure API key
5. **Store Securely**: Copy key immediately (only shown once)

#### API Key Types
- **Public Keys**: Client-side operations (limited scope)
- **Private Keys**: Server-side operations (full access)
- **Integration Keys**: Third-party service access
- **Webhook Keys**: Event delivery authentication

### Authentication Methods

#### Bearer Token Authentication
Include API key in request headers:
```http
GET /api/v1/customers HTTP/1.1
Host: api.powernode.com
Authorization: Bearer pk_live_your_api_key_here
Content-Type: application/json
```

#### Example Authentication
```javascript
const axios = require('axios');

const apiClient = axios.create({
  baseURL: 'https://api.powernode.com/v1',
  headers: {
    'Authorization': 'Bearer pk_live_your_api_key_here',
    'Content-Type': 'application/json'
  }
});

// Example API call
const getCustomers = async () => {
  try {
    const response = await apiClient.get('/customers');
    return response.data;
  } catch (error) {
    console.error('API Error:', error.response.data);
    throw error;
  }
};
```

## Core API Concepts

### Request Structure
All API requests follow consistent patterns:

#### HTTP Methods
- **GET**: Retrieve data (list or individual records)
- **POST**: Create new resources
- **PUT**: Update entire resources  
- **PATCH**: Update partial resources
- **DELETE**: Remove resources

#### URL Structure
```
https://api.powernode.com/v1/{resource}/{id}/{sub-resource}

Examples:
GET    /customers                    # List customers
GET    /customers/cust_123          # Get specific customer  
POST   /customers                   # Create customer
PUT    /customers/cust_123          # Update customer
DELETE /customers/cust_123          # Delete customer
GET    /customers/cust_123/subscriptions  # Get customer subscriptions
```

#### Request Headers
```http
Authorization: Bearer pk_live_your_api_key
Content-Type: application/json
Accept: application/json
Idempotency-Key: unique_request_id_here (for POST/PUT requests)
```

### Response Structure
All API responses use a consistent JSON structure:

#### Success Response
```json
{
  "success": true,
  "data": {
    "id": "cust_123",
    "email": "customer@example.com",
    "first_name": "John",
    "last_name": "Smith",
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

#### Error Response
```json
{
  "success": false,
  "error": {
    "code": "INVALID_REQUEST",
    "message": "The email field is required",
    "field": "email",
    "type": "validation_error"
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

#### Paginated Response
```json
{
  "success": true,
  "data": [
    { "id": "cust_1", "email": "user1@example.com" },
    { "id": "cust_2", "email": "user2@example.com" }
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 150,
    "total_pages": 6,
    "has_next": true,
    "has_prev": false
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

## Customer Management API

### Creating Customers
Create new customer accounts:

```javascript
const createCustomer = async (customerData) => {
  const response = await apiClient.post('/customers', {
    email: customerData.email,
    first_name: customerData.firstName,
    last_name: customerData.lastName,
    phone: customerData.phone,
    company: customerData.company,
    metadata: {
      source: 'website',
      campaign: 'spring_2024'
    }
  });
  
  return response.data.data;
};

// Usage
const newCustomer = await createCustomer({
  email: 'john.smith@example.com',
  firstName: 'John',
  lastName: 'Smith',
  phone: '+1-555-123-4567',
  company: 'Acme Corp'
});
```

### Retrieving Customers
Get customer information:

```javascript
// Get single customer
const getCustomer = async (customerId) => {
  const response = await apiClient.get(`/customers/${customerId}`);
  return response.data.data;
};

// List customers with filtering
const listCustomers = async (filters = {}) => {
  const params = new URLSearchParams();
  
  if (filters.email) params.append('email', filters.email);
  if (filters.created_after) params.append('created_after', filters.created_after);
  if (filters.page) params.append('page', filters.page);
  if (filters.limit) params.append('limit', filters.limit);
  
  const response = await apiClient.get(`/customers?${params}`);
  return response.data;
};

// Usage examples
const customer = await getCustomer('cust_123');
const recentCustomers = await listCustomers({
  created_after: '2024-01-01',
  limit: 50
});
```

### Updating Customers
Modify customer information:

```javascript
// Full update (PUT)
const updateCustomer = async (customerId, customerData) => {
  const response = await apiClient.put(`/customers/${customerId}`, customerData);
  return response.data.data;
};

// Partial update (PATCH)
const patchCustomer = async (customerId, updates) => {
  const response = await apiClient.patch(`/customers/${customerId}`, updates);
  return response.data.data;
};

// Usage
const updatedCustomer = await patchCustomer('cust_123', {
  phone: '+1-555-987-6543',
  company: 'New Company Name'
});
```

## Subscription Management API

### Creating Subscriptions
Set up new customer subscriptions:

```javascript
const createSubscription = async (subscriptionData) => {
  const response = await apiClient.post('/subscriptions', {
    customer_id: subscriptionData.customerId,
    plan_id: subscriptionData.planId,
    payment_method_id: subscriptionData.paymentMethodId,
    trial_days: subscriptionData.trialDays,
    coupon_code: subscriptionData.couponCode,
    metadata: {
      source: subscriptionData.source,
      campaign: subscriptionData.campaign
    }
  });
  
  return response.data.data;
};

// Usage
const subscription = await createSubscription({
  customerId: 'cust_123',
  planId: 'plan_pro_monthly',
  paymentMethodId: 'pm_card_visa',
  trialDays: 14,
  source: 'website_signup'
});
```

### Managing Subscription Changes
Handle plan changes and modifications:

```javascript
// Upgrade/downgrade subscription
const changeSubscriptionPlan = async (subscriptionId, newPlanId, options = {}) => {
  const response = await apiClient.patch(`/subscriptions/${subscriptionId}`, {
    plan_id: newPlanId,
    prorate: options.prorate !== false,
    effective_date: options.effectiveDate || 'immediate'
  });
  
  return response.data.data;
};

// Pause subscription
const pauseSubscription = async (subscriptionId, pauseOptions = {}) => {
  const response = await apiClient.post(`/subscriptions/${subscriptionId}/pause`, {
    resume_date: pauseOptions.resumeDate,
    reason: pauseOptions.reason
  });
  
  return response.data.data;
};

// Cancel subscription
const cancelSubscription = async (subscriptionId, cancelOptions = {}) => {
  const response = await apiClient.post(`/subscriptions/${subscriptionId}/cancel`, {
    cancel_at: cancelOptions.cancelAt || 'end_of_period',
    reason: cancelOptions.reason,
    provide_feedback: cancelOptions.provideFeedback
  });
  
  return response.data.data;
};
```

## Billing and Payment API

### Invoice Management
Handle invoice operations:

```javascript
// Get customer invoices
const getCustomerInvoices = async (customerId, options = {}) => {
  const params = new URLSearchParams();
  if (options.status) params.append('status', options.status);
  if (options.date_from) params.append('date_from', options.date_from);
  if (options.date_to) params.append('date_to', options.date_to);
  
  const response = await apiClient.get(`/customers/${customerId}/invoices?${params}`);
  return response.data;
};

// Create manual invoice
const createInvoice = async (invoiceData) => {
  const response = await apiClient.post('/invoices', {
    customer_id: invoiceData.customerId,
    line_items: invoiceData.lineItems,
    due_date: invoiceData.dueDate,
    notes: invoiceData.notes,
    metadata: invoiceData.metadata
  });
  
  return response.data.data;
};

// Usage
const invoices = await getCustomerInvoices('cust_123', {
  status: 'unpaid',
  date_from: '2024-01-01'
});
```

### Payment Processing
Handle payment operations:

```javascript
// Process one-time payment
const processPayment = async (paymentData) => {
  const response = await apiClient.post('/payments', {
    customer_id: paymentData.customerId,
    payment_method_id: paymentData.paymentMethodId,
    amount: paymentData.amount,
    currency: paymentData.currency || 'USD',
    description: paymentData.description,
    metadata: paymentData.metadata
  });
  
  return response.data.data;
};

// Refund payment
const refundPayment = async (paymentId, refundData) => {
  const response = await apiClient.post(`/payments/${paymentId}/refund`, {
    amount: refundData.amount, // Optional: partial refund
    reason: refundData.reason,
    metadata: refundData.metadata
  });
  
  return response.data.data;
};
```

## Webhook Integration

### Setting Up Webhooks
Configure event notifications:

```javascript
// Create webhook endpoint
const createWebhook = async (webhookData) => {
  const response = await apiClient.post('/webhooks', {
    url: webhookData.url,
    events: webhookData.events,
    description: webhookData.description,
    secret: webhookData.secret // Optional: for signature verification
  });
  
  return response.data.data;
};

// Usage
const webhook = await createWebhook({
  url: 'https://yourapp.com/webhooks/powernode',
  events: [
    'customer.created',
    'subscription.created',
    'subscription.updated',
    'subscription.cancelled',
    'invoice.paid',
    'payment.failed'
  ],
  description: 'Production webhook for customer updates'
});
```

### Handling Webhook Events
Process incoming webhook notifications:

```javascript
const express = require('express');
const crypto = require('crypto');
const app = express();

// Webhook signature verification
const verifyWebhookSignature = (payload, signature, secret) => {
  const computedSignature = crypto
    .createHmac('sha256', secret)
    .update(payload, 'utf8')
    .digest('hex');
    
  return crypto.timingSafeEqual(
    Buffer.from(signature, 'hex'),
    Buffer.from(computedSignature, 'hex')
  );
};

// Webhook endpoint handler
app.post('/webhooks/powernode', express.raw({type: 'application/json'}), (req, res) => {
  const payload = req.body;
  const signature = req.headers['x-powernode-signature'];
  const webhookSecret = process.env.POWERNODE_WEBHOOK_SECRET;
  
  // Verify webhook signature
  if (!verifyWebhookSignature(payload, signature, webhookSecret)) {
    return res.status(401).send('Invalid signature');
  }
  
  const event = JSON.parse(payload.toString());
  
  // Handle different event types
  switch (event.type) {
    case 'customer.created':
      handleCustomerCreated(event.data);
      break;
      
    case 'subscription.created':
      handleSubscriptionCreated(event.data);
      break;
      
    case 'payment.failed':
      handlePaymentFailed(event.data);
      break;
      
    default:
      console.log(`Unhandled event type: ${event.type}`);
  }
  
  res.status(200).send('OK');
});

// Event handlers
const handleCustomerCreated = (customerData) => {
  console.log('New customer created:', customerData.id);
  // Sync with CRM, send welcome email, etc.
};

const handleSubscriptionCreated = (subscriptionData) => {
  console.log('New subscription:', subscriptionData.id);
  // Provision services, update internal systems, etc.
};

const handlePaymentFailed = (paymentData) => {
  console.log('Payment failed:', paymentData.id);
  // Send notification, update customer record, etc.
};
```

## Error Handling and Best Practices

### Error Handling
Implement robust error handling:

```javascript
const apiCall = async (operation) => {
  try {
    const response = await operation();
    return response;
  } catch (error) {
    if (error.response) {
      // API returned error response
      const { status, data } = error.response;
      
      switch (status) {
        case 400:
          throw new Error(`Bad Request: ${data.error.message}`);
        case 401:
          throw new Error('Authentication failed. Check API key.');
        case 403:
          throw new Error('Permission denied. Check API key permissions.');
        case 404:
          throw new Error('Resource not found.');
        case 429:
          throw new Error('Rate limit exceeded. Retry after delay.');
        case 500:
          throw new Error('Server error. Try again later.');
        default:
          throw new Error(`API Error: ${data.error.message}`);
      }
    } else if (error.request) {
      // Request made but no response
      throw new Error('Network error. Check internet connection.');
    } else {
      // Other error
      throw error;
    }
  }
};
```

### Rate Limiting
Handle rate limits gracefully:

```javascript
const withRetry = async (operation, maxRetries = 3, baseDelay = 1000) => {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      if (error.response?.status === 429 && attempt < maxRetries) {
        const delay = baseDelay * Math.pow(2, attempt - 1);
        console.log(`Rate limited. Retrying in ${delay}ms...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      } else {
        throw error;
      }
    }
  }
};

// Usage
const result = await withRetry(() => apiClient.get('/customers'));
```

### Idempotency
Ensure safe retries:

```javascript
const createCustomerSafely = async (customerData, idempotencyKey) => {
  const response = await apiClient.post('/customers', customerData, {
    headers: {
      'Idempotency-Key': idempotencyKey
    }
  });
  
  return response.data.data;
};

// Generate unique key
const idempotencyKey = `create-customer-${Date.now()}-${Math.random()}`;
const customer = await createCustomerSafely(customerData, idempotencyKey);
```

---

**Ready to start integrating?** Get your API keys from the [Developer Dashboard](/admin/api-keys) and try our [Interactive API Explorer](/api/explorer).

**Need help?** Check out our [API Reference Documentation](/docs/api) or contact our developer support team.
},
    excerpt: 'Complete guide to integrating with Powernode REST APIs, including authentication, webhooks, and best practices.',
    tags: %w[api integration development webhooks rest],
    is_featured: true,
    sort_order: 1
  }
]

# Create the extended articles
extended_articles.each do |article_data|
  next unless category_records[article_data[:category]] # Skip if category doesn't exist
  
  category = category_records[article_data[:category]]
  
  article = KnowledgeBaseArticle.find_or_create_by(slug: article_data[:slug]) do |article|
    article.title = article_data[:title]
    article.content = article_data[:content].strip
    article.excerpt = article_data[:excerpt]
    article.category = category
    article.author = admin_user
    article.status = 'published'
    article.is_public = true
    article.is_featured = article_data[:is_featured] || false
    article.sort_order = article_data[:sort_order] || 0
    article.published_at = Time.current
  end

  # Add tags
  if article_data[:tags]
    article.tags = article_data[:tags].map do |tag_name|
      KnowledgeBaseTag.find_or_create_by(name: tag_name) do |tag|
        tag.slug = tag_name
      end
    end
  end
end

puts "✅ Created #{extended_articles.length} extended Knowledge Base articles"

# Output summary
total_articles = KnowledgeBaseArticle.count
puts "\n📊 Total Knowledge Base Articles: #{total_articles}"
puts "✅ Extended Knowledge Base articles seeded successfully!"