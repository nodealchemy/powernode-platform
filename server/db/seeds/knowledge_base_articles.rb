# frozen_string_literal: true

# Knowledge Base Articles Seed
# This file creates comprehensive Knowledge Base content for the Powernode platform
# Run with: rails db:seed (includes this file automatically)
# Or directly: rails runner "load 'db/seeds/knowledge_base_articles.rb'"

puts "\n🔄 Seeding Knowledge Base Articles..."

# Ensure categories exist first
categories_data = [
  { name: "Getting Started", slug: "getting-started", description: "Essential guides for new users", sort_order: 1 },
  { name: "Account Setup", slug: "account-setup", description: "Account configuration and team management", sort_order: 2 },
  { name: "Billing & Subscriptions", slug: "billing-subscriptions", description: "Subscription management and billing", sort_order: 3 },
  { name: "Payment Methods", slug: "payment-methods", description: "Payment processing and gateway setup", sort_order: 4 },
  { name: "API Documentation", slug: "api-documentation", description: "Developer resources and API integration", sort_order: 5 },
  { name: "Troubleshooting", slug: "troubleshooting", description: "Solutions to common issues", sort_order: 6 }
]

categories_data.each do |cat_data|
  category = KnowledgeBaseCategory.find_or_create_by(slug: cat_data[:slug]) do |cat|
    cat.name = cat_data[:name]
    cat.description = cat_data[:description]
    cat.sort_order = cat_data[:sort_order]
    cat.is_public = true
  end
  puts "✅ Category: #{category.name}"
end

# Get author and categories
author = User.first || User.create!(
  email: "admin@powernode.org",
  password: SecureRandom.hex(16),
  email_verified: true,
  first_name: "System",
  last_name: "Administrator"
)

getting_started_cat = KnowledgeBaseCategory.find_by(slug: "getting-started")
account_setup_cat = KnowledgeBaseCategory.find_by(slug: "account-setup")
billing_cat = KnowledgeBaseCategory.find_by(slug: "billing-subscriptions")
payment_methods_cat = KnowledgeBaseCategory.find_by(slug: "payment-methods")
api_cat = KnowledgeBaseCategory.find_by(slug: "api-documentation")
troubleshooting_cat = KnowledgeBaseCategory.find_by(slug: "troubleshooting")

# Article 1: Welcome to Powernode - Getting Started Guide (Featured)
welcome_content = <<~MARKDOWN
# Welcome to Powernode - Getting Started Guide

Welcome to Powernode, your comprehensive subscription lifecycle management platform! This guide will help you get up and running quickly.

## What is Powernode?

Powernode is a powerful subscription management platform designed to handle the complete lifecycle of subscription-based businesses. Whether you're managing SaaS products, membership sites, or recurring services, Powernode provides the tools you need.

### Key Features
- **Subscription Management**: Create, modify, and track subscriptions
- **Payment Processing**: Integrated Stripe and PayPal support
- **Team Management**: Role-based access control and permissions
- **Analytics & Reporting**: Comprehensive insights into your business
- **API Integration**: RESTful API for custom integrations
- **Automated Billing**: Recurring payments and invoice generation

## Quick Setup Checklist

Follow these steps to get your Powernode account ready:

### 1. Account Configuration
- [ ] Complete your profile information
- [ ] Set up your company details
- [ ] Configure your timezone and currency preferences
- [ ] Upload your company logo

### 2. Payment Gateway Setup
- [ ] Connect your Stripe account
- [ ] Configure PayPal integration (optional)
- [ ] Test payment processing in sandbox mode
- [ ] Set up webhook endpoints

### 3. Subscription Plans
- [ ] Create your first subscription plan
- [ ] Configure pricing tiers
- [ ] Set up trial periods (if applicable)
- [ ] Define plan features and limitations

### 4. Team Setup
- [ ] Invite team members
- [ ] Assign appropriate roles and permissions
- [ ] Configure notification preferences
- [ ] Set up approval workflows

## Your First Subscription

Creating your first subscription plan is easy:

1. **Navigate to Plans**: Go to Business > Subscription Plans
2. **Create New Plan**: Click "Create Plan"
3. **Configure Details**: 
   - Plan name and description
   - Pricing and billing cycle
   - Trial period settings
   - Feature limitations
4. **Save and Activate**: Review and activate your plan

## Understanding Permissions

Powernode uses a granular permission system:

- **Account Managers**: Full account access
- **Billing Managers**: Payment and subscription management  
- **Team Members**: Limited access based on assigned permissions
- **API Users**: Programmatic access with specific scopes

## Getting Help

Need assistance? Here are your options:

- **Knowledge Base**: Browse our comprehensive guides
- **API Documentation**: Technical integration resources
- **Support Portal**: Submit tickets for technical issues
- **Community Forum**: Connect with other Powernode users

## Next Steps

Ready to dive deeper? Check out these guides:

1. [Setting Up Your First Subscription Plan](#)
2. [Configuring Payment Gateways](#)
3. [Managing Team Members and Permissions](#)
4. [Understanding Analytics and Reporting](#)
5. [API Integration Basics](#)

## Best Practices

For the best experience with Powernode:

- **Start Small**: Begin with a simple plan structure
- **Test Thoroughly**: Use sandbox mode before going live
- **Monitor Metrics**: Keep an eye on key performance indicators
- **Stay Updated**: Check for platform updates and new features
- **Backup Data**: Regularly export important data

Welcome aboard! We're excited to help you grow your subscription business with Powernode.
MARKDOWN

article1 = KnowledgeBaseArticle.find_or_create_by(slug: "welcome-to-powernode-getting-started-guide") do |article|
  article.title = "Welcome to Powernode - Getting Started Guide"
  article.category = getting_started_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Complete guide to getting started with Powernode subscription management platform. Learn setup, configuration, and first steps."
  article.content = welcome_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "✅ Article: #{article1.title}"

# Article 2: Complete Guide to Subscription Management
subscription_content = <<~MARKDOWN
# Complete Guide to Subscription Management

Master subscription lifecycle management with Powernode's comprehensive tools and automation features.

## Understanding Subscription Lifecycles

### The Complete Customer Journey

1. **🎯 Acquisition**: Customer discovers and signs up
2. **📝 Onboarding**: Initial setup and configuration  
3. **💳 Active Billing**: Recurring payment cycles
4. **📈 Growth**: Upgrades, add-ons, and expansion
5. **🔄 Retention**: Renewal management and engagement
6. **⚠️ Recovery**: Failed payment handling and winback
7. **👋 Churn**: Cancellation and exit processes

## Creating Effective Subscription Plans

### Plan Architecture Best Practices

**🏗️ Tiered Structure**
```
Basic Plan → Professional → Enterprise
  $10        $25           $100
```

**📦 Feature-Based Differentiation**
- **Usage Limits**: API calls, storage, users
- **Feature Access**: Advanced features, integrations
- **Support Level**: Email, priority, dedicated success manager
- **SLA Commitments**: Uptime guarantees, response times

### Pricing Strategy Framework

**Value-Based Pricing**
- Align price with customer value received
- Consider willingness to pay vs. cost to deliver
- Factor in competitive positioning
- Include growth headroom for upgrades

**Psychological Pricing**
- Use charm pricing ($9.99 vs $10.00)
- Create clear value gaps between tiers
- Offer annual discounts (15-20% typical)
- Position middle tier as "most popular"

## Advanced Billing Configuration

### Billing Cycles and Timing

**Monthly Billing**
- Pros: Lower commitment, easier to start
- Cons: Higher churn, more payment processing
- Best for: New products, lower price points

**Annual Billing**  
- Pros: Better cash flow, lower churn
- Cons: Higher initial commitment barrier
- Best for: Established products, higher value

**Custom Billing Periods**
- Quarterly (3 months)
- Semi-annual (6 months)  
- Bi-annual (2 years)
- Custom periods for enterprise

### Proration and Mid-Cycle Changes

**Upgrade Scenarios**
```
Customer upgrades from $10 to $25 plan mid-month:
- Current period: $10 (already paid)
- Prorated charge: $15 × (15 days remaining / 30 days) = $7.50
- Next billing: $25 full amount
```

**Downgrade Scenarios**
```
Customer downgrades from $25 to $10 plan:
- Credit applied: $15 × (15 days remaining / 30 days) = $7.50
- Applied to next billing cycle
- Next billing: $10 - $7.50 = $2.50
```

## Subscription Automation Workflows

### Automated Billing Processes

**🔄 Recurring Billing**
- Automatic payment attempts
- Smart retry logic for failed payments
- Grace periods and dunning management
- Automatic service suspension/restoration

**📧 Customer Communications**
- Payment confirmations and receipts
- Upcoming renewal notifications
- Failed payment alerts
- Cancellation confirmations

### Failed Payment Recovery

**Dunning Management Strategy**
```
Day 0: Payment fails → Immediate retry
Day 1: Email notification + Retry attempt
Day 3: Second email + Retry attempt  
Day 7: Final notice + Retry attempt
Day 10: Service suspension
Day 30: Subscription cancellation
```

**Recovery Tactics**
- Update payment method prompts
- Alternative payment options
- Temporary discounts or incentives
- Personal outreach for high-value customers

## Customer Self-Service Portal

### Portal Features

**Account Management**
- View subscription details and billing history
- Download invoices and receipts
- Update payment methods
- Change billing addresses

**Plan Management**
- Upgrade/downgrade subscriptions
- Add or remove features/add-ons
- Pause or cancel subscriptions
- View usage and limits

### Configuration Best Practices

**User Experience**
- Clear navigation and status indicators
- Mobile-responsive design
- Single sign-on integration
- Multi-language support

**Business Rules**
- Define upgrade/downgrade restrictions
- Set cancellation policies (immediate vs. end-of-term)
- Configure refund policies and processing
- Establish change limitations and approval requirements

## Advanced Subscription Features

### Add-Ons and Extras

**Usage-Based Add-Ons**
- API calls beyond plan limits
- Additional storage or bandwidth
- Extra user seats or licenses
- Premium support hours

**Feature Add-Ons**
- Advanced integrations
- White-label options
- Custom reporting
- Priority processing

### Subscription Bundling

**Product Bundles**
- Multiple services in one subscription
- Cross-product discounts
- Simplified billing consolidation
- Higher customer lifetime value

**Implementation Strategy**
```yaml
Bundle: "Complete Suite"
  - Core Platform: $50/month
  - Analytics Add-on: $20/month (normally $30)
  - API Access: $15/month (normally $25)
  - Total Value: $105/month
  - Bundle Price: $75/month (29% savings)
```

## Analytics and Optimization

### Key Subscription Metrics

**📊 Revenue Metrics**
- Monthly Recurring Revenue (MRR)
- Annual Recurring Revenue (ARR)
- Average Revenue Per User (ARPU)
- Customer Lifetime Value (CLV)

**📈 Growth Metrics**
- Customer Acquisition Cost (CAC)
- MRR Growth Rate
- Net Revenue Retention
- Expansion Revenue

**⚠️ Health Metrics**
- Churn Rate (customer and revenue)
- Involuntary Churn (failed payments)
- Time to Value (activation rate)
- Payment Success Rate

### Optimization Strategies

**Reduce Churn**
- Improve onboarding experience
- Implement usage monitoring and alerts
- Create engagement campaigns
- Offer pause options instead of cancellation

**Increase Expansion**
- Usage-based upgrade prompts
- Feature discovery campaigns  
- Success-driven account management
- Regular plan optimization reviews

**Improve Unit Economics**
- Optimize payment processing costs
- Reduce support costs through self-service
- Increase annual plan adoption
- Implement referral programs

## Compliance and Security

### Payment Processing Compliance

**PCI DSS Requirements**
- Never store credit card data
- Use tokenization for payment methods
- Implement strong access controls
- Regular security assessments

**Data Protection**
- GDPR compliance for EU customers
- CCPA compliance for California residents
- SOC 2 Type II certification
- Regular penetration testing

### Financial Reporting

**Revenue Recognition**
- Subscription revenue recognition rules
- Deferred revenue tracking
- Tax calculation and remittance
- Financial audit support

**Regulatory Requirements**
- Sales tax collection and remittance
- VAT handling for international customers
- Financial reporting standards
- Anti-money laundering compliance

## Troubleshooting Common Issues

### Payment Problems

**Failed Payments**
1. Check card expiration and limits
2. Verify billing address accuracy
3. Try alternative payment methods
4. Contact payment processor support

**Proration Errors**
1. Review plan change timing
2. Verify proration calculation rules
3. Check for manual adjustments
4. Audit billing cycle alignment

### Customer Issues

**Access Problems**
1. Verify subscription status
2. Check payment method validity
3. Review account permissions
4. Confirm feature entitlements

**Billing Disputes**
1. Review transaction history
2. Provide detailed invoice breakdowns
3. Explain proration calculations
4. Offer adjustment if warranted

---

Ready to implement advanced subscription management? Explore our API documentation for custom integrations, or contact support for personalized setup assistance.
MARKDOWN

article2 = KnowledgeBaseArticle.find_or_create_by(slug: "complete-guide-subscription-management") do |article|
  article.title = "Complete Guide to Subscription Management"
  article.category = billing_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Master subscription lifecycle management with Powernode. Learn plan creation, billing cycles, upgrades, downgrades, and automated workflows."
  article.content = subscription_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "✅ Article: #{article2.title}"

# Article 3: API Integration Fundamentals
api_content = <<~MARKDOWN
# API Integration Fundamentals for Powernode

Unlock the full power of Powernode through our comprehensive RESTful API. This guide covers everything developers need to build robust integrations.

## API Overview

### Core Capabilities

**🔗 RESTful Architecture**
- Predictable resource-based URLs
- Standard HTTP methods (GET, POST, PUT, DELETE)
- JSON request/response format
- Comprehensive error handling

**🛡️ Enterprise Security**
- JWT-based authentication
- Rate limiting and throttling
- IP whitelisting support
- Audit logging for all API calls

**📊 Real-Time Data**
- Webhook notifications for events
- Server-sent events for live updates
- Batch operations for efficiency
- Pagination for large datasets

### Base API Information

```
Base URL: https://api.powernode.org/api/v1
Content-Type: application/json
Authentication: Bearer JWT tokens
Rate Limit: 1000 requests/hour (default)
```

## Authentication Deep Dive

### JWT Token Authentication

**🔑 Authentication Flow**
```bash
# 1. Get access token
curl -X POST https://api.powernode.org/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your-email@example.com",
    "password": "your-password"
  }'

# Response:
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

**🔄 Token Refresh**
```bash
curl -X POST https://api.powernode.org/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_REFRESH_TOKEN"
```

### API Key Authentication (Recommended for Server-to-Server)

**🎯 Creating API Keys**
1. Navigate to Settings > API Keys
2. Click "Generate New API Key"
3. Set permissions and expiration
4. Securely store the generated key

**🔒 Using API Keys**
```bash
curl -X GET https://api.powernode.org/api/v1/subscriptions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json"
```

### Security Best Practices

**🛡️ Token Management**
- Store tokens securely (environment variables)
- Implement automatic token refresh
- Use HTTPS for all API communications
- Rotate API keys regularly

**🔐 Permission Scoping**
```json
{
  "scopes": [
    "subscriptions:read",
    "subscriptions:write", 
    "customers:read",
    "invoices:read",
    "analytics:read"
  ]
}
```

## Core API Endpoints

### Subscription Management

**📋 List Subscriptions**
```bash
GET /v1/subscriptions
Query Parameters:
  - status: active|cancelled|trial|past_due
  - plan_id: filter by specific plan
  - customer_id: filter by customer  
  - page: pagination page number
  - per_page: items per page (max 100)
```

**🔍 Get Subscription Details**
```bash
GET /v1/subscriptions/{subscription_id}

Response:
{
  "id": "sub_1234567890",
  "customer_id": "cust_9876543210", 
  "plan_id": "plan_basic",
  "status": "active",
  "current_period_start": "2024-01-01T00:00:00Z",
  "current_period_end": "2024-02-01T00:00:00Z",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-15T10:30:00Z",
  "metadata": {}
}
```

**➕ Create Subscription**
```bash
POST /v1/subscriptions

Request Body:
{
  "customer_id": "cust_9876543210",
  "plan_id": "plan_basic",
  "trial_days": 14,
  "prorate": true,
  "metadata": {
    "source": "website_signup",
    "campaign": "summer_2024"
  }
}
```

**✏️ Update Subscription**
```bash
PUT /v1/subscriptions/{subscription_id}

Request Body:
{
  "plan_id": "plan_professional",
  "prorate": true,
  "billing_cycle_anchor": "unchanged"
}
```

### Customer Management

**👥 Customer Operations**
```bash
# List customers
GET /v1/customers?page=1&per_page=50

# Create customer  
POST /v1/customers
{
  "email": "customer@example.com",
  "name": "John Doe",
  "phone": "+1-555-0123",
  "address": {
    "line1": "123 Main St",
    "city": "Anytown", 
    "state": "CA",
    "postal_code": "12345",
    "country": "US"
  }
}

# Update customer
PUT /v1/customers/{customer_id}
{
  "name": "John Smith",
  "phone": "+1-555-0124"
}
```

### Payment and Invoice Management

**💳 Payment Methods**
```bash
# List payment methods for customer
GET /v1/customers/{customer_id}/payment-methods

# Add payment method
POST /v1/customers/{customer_id}/payment-methods
{
  "type": "card",
  "token": "tok_visa_4242424242424242",
  "set_as_default": true
}
```

**🧾 Invoice Operations**
```bash
# List invoices
GET /v1/invoices?customer_id={customer_id}

# Get invoice details
GET /v1/invoices/{invoice_id}

# Send invoice manually
POST /v1/invoices/{invoice_id}/send
```

## Webhook Integration

### Understanding Webhooks

**🔔 Event-Driven Architecture**
Webhooks allow your application to receive real-time notifications when events occur in your Powernode account.

**📡 Common Webhook Events**
```json
{
  "events": [
    "subscription.created",
    "subscription.updated", 
    "subscription.cancelled",
    "invoice.created",
    "invoice.paid",
    "invoice.payment_failed",
    "customer.created",
    "customer.updated",
    "payment.succeeded",
    "payment.failed"
  ]
}
```

### Webhook Configuration

**⚙️ Setting Up Webhooks**
1. Go to Settings > Webhooks
2. Click "Add Webhook Endpoint"
3. Enter your endpoint URL
4. Select events to subscribe to
5. Configure retry and timeout settings

**🔒 Webhook Security**
```python
import hmac
import hashlib
import json

def verify_webhook_signature(payload, signature, secret):
    """Verify webhook signature for security"""
    expected_signature = hmac.new(
        secret.encode('utf-8'),
        payload.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(
        f"sha256={expected_signature}", 
        signature
    )

# Usage in webhook handler
@app.route('/webhooks/powernode', methods=['POST'])
def handle_webhook():
    payload = request.get_data(as_text=True)
    signature = request.headers.get('X-Powernode-Signature')
    
    if not verify_webhook_signature(payload, signature, WEBHOOK_SECRET):
        return 'Invalid signature', 401
        
    event = json.loads(payload)
    handle_event(event)
    return 'OK', 200
```

### Webhook Event Handling

**📨 Sample Webhook Payload**
```json
{
  "id": "evt_1234567890",
  "type": "subscription.created",
  "created": "2024-01-15T10:30:00Z",
  "data": {
    "object": {
      "id": "sub_1234567890",
      "customer_id": "cust_9876543210",
      "plan_id": "plan_basic",
      "status": "active",
      "current_period_start": "2024-01-15T10:30:00Z",
      "current_period_end": "2024-02-15T10:30:00Z"
    }
  }
}
```

**🔄 Event Processing Best Practices**
```python
def handle_event(event):
    event_type = event['type']
    
    if event_type == 'subscription.created':
        # Provision access for new subscription
        provision_user_access(event['data']['object'])
        
    elif event_type == 'subscription.cancelled':
        # Revoke access for cancelled subscription
        revoke_user_access(event['data']['object'])
        
    elif event_type == 'invoice.payment_failed':
        # Handle failed payment
        notify_payment_failure(event['data']['object'])
        
    # Always return 200 OK for successful processing
    return True
```

## Integration Patterns and Best Practices

### Error Handling

**📊 HTTP Status Codes**
```bash
200 OK              # Successful GET, PUT requests
201 Created         # Successful POST requests  
204 No Content      # Successful DELETE requests
400 Bad Request     # Invalid request format
401 Unauthorized    # Missing/invalid authentication
403 Forbidden       # Insufficient permissions
404 Not Found       # Resource doesn't exist
422 Unprocessable   # Validation errors
429 Too Many Req    # Rate limit exceeded
500 Server Error    # Internal server error
```

**⚠️ Error Response Format**
```json
{
  "error": {
    "type": "validation_error",
    "message": "Invalid email format",
    "details": {
      "field": "email",
      "code": "invalid_format"
    }
  }
}
```

### Rate Limiting

**🚦 Rate Limit Headers**
```bash
X-RateLimit-Limit: 1000        # Requests per hour
X-RateLimit-Remaining: 999     # Remaining requests
X-RateLimit-Reset: 1642687200  # Unix timestamp reset time
```

**⏳ Handling Rate Limits**
```python
import time
import requests

def api_request_with_retry(url, headers, data=None):
    max_retries = 3
    
    for attempt in range(max_retries):
        response = requests.post(url, headers=headers, json=data)
        
        if response.status_code == 429:
            # Rate limited, wait and retry
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
            continue
            
        return response
    
    raise Exception("Max retries exceeded")
```

### Pagination

**📄 Cursor-Based Pagination**
```bash
GET /v1/subscriptions?per_page=25&cursor=eyJpZCI6InN1Yl8xMjM0NTY3ODkwIn0

Response:
{
  "data": [...],
  "pagination": {
    "has_more": true,
    "next_cursor": "eyJpZCI6InN1Yl85ODc2NTQzMjEwIn0"
  }
}
```

**🔢 Page-Based Pagination**
```bash
GET /v1/invoices?page=2&per_page=50

Response:
{
  "data": [...],
  "pagination": {
    "current_page": 2,
    "per_page": 50, 
    "total_pages": 10,
    "total_count": 487
  }
}
```

## SDK and Code Examples

### Official SDKs

**🐍 Python SDK**
```python
import powernode

client = powernode.Client(api_key='your-api-key')

# Create subscription
subscription = client.subscriptions.create({
    'customer_id': 'cust_123',
    'plan_id': 'plan_basic'
})

# List subscriptions with filtering
subscriptions = client.subscriptions.list(
    status='active',
    per_page=100
)
```

**📱 Node.js SDK**
```javascript
const Powernode = require('powernode');
const client = new Powernode('your-api-key');

// Create customer
const customer = await client.customers.create({
  email: 'customer@example.com',
  name: 'John Doe'
});

// Create subscription
const subscription = await client.subscriptions.create({
  customerId: customer.id,
  planId: 'plan_basic'
});
```

**💎 Ruby SDK**
```ruby
require 'powernode'

Powernode.api_key = 'your-api-key'

# Create subscription
subscription = Powernode::Subscription.create(
  customer_id: 'cust_123',
  plan_id: 'plan_basic'
)

# Update subscription
subscription.plan_id = 'plan_professional'
subscription.save
```

### Custom Integration Examples

**🔗 Webhook to Slack Integration**
```python
import requests

def notify_slack_new_subscription(event_data):
    subscription = event_data['object']
    
    message = {
        "text": f"🎉 New subscription created!",
        "attachments": [{
            "fields": [
                {"title": "Customer", "value": subscription['customer_id'], "short": True},
                {"title": "Plan", "value": subscription['plan_id'], "short": True},
                {"title": "Status", "value": subscription['status'], "short": True}
            ]
        }]
    }
    
    requests.post(SLACK_WEBHOOK_URL, json=message)
```

**📊 Sync to Analytics Platform**
```python
def sync_subscription_to_analytics(subscription):
    """Sync subscription data to your analytics platform"""
    
    analytics_data = {
        'user_id': subscription['customer_id'],
        'plan': subscription['plan_id'],
        'mrr': get_plan_price(subscription['plan_id']),
        'status': subscription['status'],
        'trial_end': subscription.get('trial_end'),
        'created_at': subscription['created_at']
    }
    
    # Send to your analytics platform
    analytics_client.track('subscription_created', analytics_data)
```

## Testing and Development

### Sandbox Environment

**🧪 Sandbox Configuration**
```bash
Base URL: https://sandbox-api.powernode.org/api/v1
Test API Keys: Use 'test_' prefix
Test Data: Pre-populated test customers and plans
Webhooks: Use ngrok for local development
```

**🎯 Test Payment Methods**
```json
{
  "test_cards": {
    "visa_success": "4242424242424242",
    "visa_declined": "4000000000000002",
    "amex_success": "378282246310005",
    "mastercard_success": "5555555555554444"
  }
}
```

### Integration Testing

**✅ Test Checklist**
- [ ] Authentication and authorization
- [ ] CRUD operations for all resources
- [ ] Error handling and edge cases
- [ ] Rate limiting behavior
- [ ] Webhook delivery and processing
- [ ] Idempotency for critical operations

**🔍 Debugging Tools**
```bash
# Enable debug logging
export POWERNODE_DEBUG=true

# Use request IDs for tracing
curl -X GET "https://api.powernode.org/api/v1/subscriptions" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "X-Request-ID: unique-request-id-123"
```

---

Ready to start building? Check out our [interactive API explorer](API_EXPLORER_LINK) or download our [Postman collection](POSTMAN_LINK) to get started immediately.

Need help? Our developer support team is available through [GitHub Discussions](GITHUB_LINK) or email at developers@powernode.org.
MARKDOWN

article3 = KnowledgeBaseArticle.find_or_create_by(slug: "api-integration-fundamentals-powernode") do |article|
  article.title = "API Integration Fundamentals for Powernode"
  article.category = api_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Complete developer guide to Powernode's RESTful API. Learn authentication, endpoints, webhooks, and integration best practices for seamless automation."
  article.content = api_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "✅ Article: #{article3.title}"

# Article 4: Team Management and Permissions Guide
team_content = <<~MARKDOWN
# Team Management and Permissions Guide

Effectively manage your team with Powernode's granular permission system and role-based access control.

## Understanding Permission-Based Access Control

Powernode uses a **permission-based system** (not roles) for granular access control. This ensures team members have exactly the access they need.

### Core Permission Categories

**👤 User Management**
- `users.create` - Create new team members
- `users.read` - View team member information  
- `users.update` - Edit team member details
- `users.delete` - Remove team members
- `users.manage` - Full user management access
- `team.manage` - Comprehensive team oversight

**💰 Billing & Finance**
- `billing.read` - View billing information
- `billing.update` - Modify billing settings
- `billing.manage` - Full billing management
- `invoices.create` - Generate invoices
- `payments.process` - Process payments and refunds

**🔧 System Administration**
- `admin.access` - Access admin interface
- `system.admin` - Complete system control
- `accounts.manage` - Manage multiple accounts
- `settings.update` - Modify system settings

**📊 Analytics & Reporting**
- `analytics.read` - View reports and metrics
- `analytics.export` - Export data and reports
- `reports.generate` - Create custom reports

**📝 Content Management**
- `pages.create` - Create new content
- `pages.update` - Edit existing content
- `pages.delete` - Remove content
- `content.manage` - Full content control

## Team Member Management

### Adding Team Members

**Step 1: Navigate to Team Settings**
Go to **Settings > Team** in your dashboard

**Step 2: Send Invitation**
1. Click "Invite Team Member"
2. Enter email address
3. Select permissions (not roles!)
4. Add personal message (optional)
5. Set expiration for invitation

**Step 3: Permission Assignment**
Choose specific permissions based on responsibilities:

```yaml
Support Manager:
  - users.read
  - billing.read
  - analytics.read
  - content.read

Billing Administrator:  
  - billing.manage
  - invoices.create
  - payments.process
  - analytics.read

Content Editor:
  - pages.create
  - pages.update
  - content.manage
```

### Managing Existing Team Members

**Update Permissions**
1. Go to Settings > Team
2. Click on team member name
3. Modify permissions as needed
4. Save changes (takes effect immediately)

**Temporary Access Changes**
- **Suspend Access**: Temporarily disable without removing
- **Restore Access**: Re-enable suspended accounts  
- **Emergency Revocation**: Immediately revoke all access

**Account Deactivation**
1. Select team member to remove
2. Choose "Deactivate Account"
3. Confirm action and provide reason
4. Transfer ownership of their work (if applicable)

## Permission Strategies by Role

### 🎯 Department-Based Permissions

**Customer Success Team**
```yaml
Permissions:
  - users.read          # View customer information
  - billing.read        # Check subscription status
  - analytics.read      # Access usage metrics
  - content.update      # Update help documentation
  
Responsibilities:
  - Customer onboarding and support
  - Usage monitoring and optimization
  - Documentation maintenance
```

**Finance & Billing Team**
```yaml
Permissions:
  - billing.manage      # Full billing control
  - invoices.create     # Generate invoices
  - payments.process    # Handle payments/refunds
  - analytics.read      # Financial reporting
  - reports.generate    # Custom financial reports

Responsibilities:
  - Payment processing and reconciliation
  - Invoice generation and management
  - Financial reporting and analysis
```

**Engineering & API Team**
```yaml
Permissions:
  - system.admin        # Technical system access
  - settings.update     # API and integration settings
  - analytics.read      # Performance monitoring
  - content.manage      # API documentation

Responsibilities:
  - API integrations and webhooks
  - Technical configurations
  - Performance monitoring
```

### 🏢 Company Size Considerations

**Startup Team (2-5 people)**
- Fewer permission restrictions
- Cross-functional responsibilities
- Regular permission reviews

**Growing Company (5-20 people)**
- Department-based permission groups
- Clear separation of concerns
- Documented permission policies

**Enterprise (20+ people)**
- Granular permission assignments
- Approval workflows for sensitive actions
- Audit logging and compliance tracking

## Advanced Team Features

### Team Notifications and Communication

**Notification Preferences**
Configure what notifications team members receive:
- New customer signups
- Payment failures and successes
- System alerts and maintenance
- API usage thresholds

**Communication Channels**
- **Email Notifications**: Detailed updates and reports
- **Slack Integration**: Real-time alerts and updates
- **In-App Notifications**: Dashboard alerts and messages
- **SMS Alerts**: Critical issues and emergencies

### Audit Logging and Compliance

**Activity Monitoring**
Track all team member actions:
- Login/logout times
- Permission changes
- Data access and modifications
- API key usage and generation

**Compliance Features**
- **SOX Compliance**: Financial access controls
- **GDPR Requirements**: Data access logging
- **SOC 2**: Security access monitoring
- **Custom Compliance**: Industry-specific requirements

### Team Collaboration Tools

**Shared Workspaces**
- Team dashboards with relevant metrics
- Shared customer lists and filters
- Collaborative notes and documentation
- Task assignment and tracking

**Knowledge Sharing**
- Internal documentation and procedures
- Training materials and resources
- Best practices and guidelines
- Troubleshooting guides and solutions

## Security Best Practices

### Access Control Principles

**🔒 Principle of Least Privilege**
- Grant minimum permissions needed for job function
- Regular permission audits and reviews
- Time-limited access for temporary tasks
- Automatic permission expiration for inactive accounts

**🛡️ Multi-Factor Authentication**
- Require MFA for all team members
- Use authenticator apps over SMS
- Backup codes for emergency access
- Regular MFA device rotation

**📋 Regular Security Reviews**

**Monthly Reviews**
- Active team member verification
- Permission alignment with current roles
- Inactive account cleanup
- MFA compliance check

**Quarterly Audits**
- Comprehensive permission review
- Access pattern analysis
- Security incident review
- Policy updates and training

### Account Security Configuration

**Password Policies**
- Minimum length and complexity requirements
- Regular password rotation requirements
- Prevention of password reuse
- Strong password generation tools

**Session Management**
- Automatic logout after inactivity
- Concurrent session limits
- IP address monitoring and alerts
- Geographic access restrictions

**API Key Management**
- Team member-specific API keys
- Permission-scoped API access
- Regular key rotation schedules
- Usage monitoring and alerts

## Troubleshooting Common Issues

### Permission Problems

**"Access Denied" Errors**
1. Verify user has required permission
2. Check permission is correctly assigned
3. Confirm account is active and not suspended
4. Validate API key permissions (if applicable)

**Missing Features or Menus**
1. Review user's permission assignments
2. Check for recent permission changes
3. Verify account subscription level
4. Clear browser cache and retry

### Team Management Issues

**Invitation Not Received**
1. Check spam/junk email folders
2. Verify email address is correct
3. Resend invitation with updated settings
4. Use alternative email address if needed

**Cannot Remove Team Member**
1. Ensure you have `users.manage` permission
2. Transfer ownership of their work first
3. Check for active API keys or integrations
4. Contact support for account dependencies

**Permission Changes Not Taking Effect**
1. Allow up to 5 minutes for propagation
2. Have user log out and log back in
3. Clear browser cache and cookies
4. Verify changes were saved successfully

### Account Access Recovery

**Lost Access to Account**
1. Use "Forgot Password" feature
2. Contact account administrator
3. Verify identity through support channels
4. Follow account recovery procedures

**MFA Device Lost or Replaced**
1. Use backup codes if available
2. Contact account administrator for reset
3. Provide identity verification
4. Set up new MFA device after access restored

---

## Getting Started Checklist

Ready to set up your team? Follow this checklist:

- [ ] Define team roles and required permissions
- [ ] Create permission groups for common access patterns  
- [ ] Send invitations to team members
- [ ] Configure notification preferences
- [ ] Set up MFA requirements
- [ ] Document team procedures and policies
- [ ] Schedule regular permission reviews
- [ ] Test access levels and workflows

Need help setting up your team? Contact our support team for personalized guidance and best practices for your organization.
MARKDOWN

article4 = KnowledgeBaseArticle.find_or_create_by(slug: "team-management-permissions-guide") do |article|
  article.title = "Team Management and Permissions Guide"
  article.category = account_setup_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Learn how to effectively manage team members, assign permissions, and configure role-based access control in Powernode."
  article.content = team_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "✅ Article: #{article4.title}"

# Article 5: Payment Methods and Processing Guide
payment_content = <<~MARKDOWN
# Payment Methods and Processing Guide

Master payment processing with Powernode's comprehensive payment infrastructure and optimization tools.

## Supported Payment Methods

### Credit and Debit Cards

**💳 Major Card Networks**
- **Visa**: Most widely accepted globally
- **Mastercard**: Strong international presence
- **American Express**: Higher fees, premium customers
- **Discover**: Primarily US market
- **JCB**: Popular in Asia-Pacific
- **Diners Club**: Business and travel focused

**🌍 Regional Payment Methods**
- **SEPA Direct Debit**: European bank transfers
- **iDEAL**: Netherlands online banking
- **Bancontact**: Belgium's preferred method
- **SOFORT**: German bank transfer system
- **Alipay**: Chinese mobile payments
- **WeChat Pay**: Chinese social payments

### Digital Wallets and Alternative Methods

**📱 Mobile Wallets**
- **Apple Pay**: iOS ecosystem integration
- **Google Pay**: Android and web payments
- **Samsung Pay**: Samsung device integration
- **PayPal**: Global online payments
- **Amazon Pay**: E-commerce integration

**🏪 Buy Now, Pay Later (BNPL)**
- **Klarna**: Flexible payment schedules
- **Afterpay**: Interest-free installments
- **Affirm**: Transparent financing options
- **Sezzle**: Budget-friendly payments

### Bank-Based Payments

**🏦 Direct Bank Transfers**
- **ACH Transfers**: US bank-to-bank transfers
- **Wire Transfers**: International bank transfers
- **Open Banking**: UK and EU direct debits
- **Faster Payments**: UK instant transfers

**📄 Traditional Methods**
- **Paper Checks**: US business payments
- **Bank Drafts**: International payments
- **Money Orders**: Secure postal payments

## Payment Gateway Configuration

### Stripe Integration

**⚡ Stripe Setup Process**

1. **Create Stripe Account**
   - Business verification process
   - Tax information submission
   - Bank account connection
   - Compliance documentation

2. **Configure Webhook Endpoints**
   ```bash
   # Webhook URL configuration
   https://your-domain.com/webhooks/stripe
   
   # Required events
   - payment_intent.succeeded
   - payment_intent.payment_failed
   - invoice.payment_succeeded
   - invoice.payment_failed
   - customer.subscription.updated
   ```

3. **API Key Management**
   ```bash
   # Test Environment
   Publishable Key: pk_test_...
   Secret Key: sk_test_...
   
   # Live Environment  
   Publishable Key: pk_live_...
   Secret Key: sk_live_...
   ```

**🔧 Advanced Stripe Features**

**Smart Retries and Recovery**
```json
{
  "automatic_payment_methods": {
    "enabled": true,
    "allow_redirects": "always"
  },
  "payment_method_options": {
    "card": {
      "request_three_d_secure": "automatic"
    }
  }
}
```

**Optimized Checkout Flow**
```javascript
// Stripe Elements integration
const stripe = Stripe('pk_test_your_key');
const elements = stripe.elements();

// Create payment element with optimizations
const paymentElement = elements.create('payment', {
  fields: {
    billingDetails: 'auto'
  },
  wallets: {
    applePay: 'auto',
    googlePay: 'auto'
  }
});
```

### PayPal Integration

**🌟 PayPal Configuration**

1. **Business Account Setup**
   - PayPal Business account creation
   - Business verification process
   - API credentials generation
   - Webhook endpoint configuration

2. **Payment Flow Configuration**
   ```javascript
   // PayPal SDK integration
   paypal.Buttons({
     createOrder: function(data, actions) {
       return actions.order.create({
         purchase_units: [{
           amount: {
             value: subscription_amount
           }
         }]
       });
     },
     onApprove: function(data, actions) {
       return actions.order.capture().then(function(details) {
         // Handle successful payment
         process_subscription(details);
       });
     }
   }).render('#paypal-button-container');
   ```

**💼 PayPal Advanced Features**

**Express Checkout**
- One-click payments for returning customers
- Saved payment methods and addresses
- Mobile-optimized checkout experience

**Subscription Billing**
- Recurring payment agreements
- Flexible billing cycles and amounts
- Automatic retry for failed payments

## Payment Security and Compliance

### PCI DSS Compliance

**🛡️ Level 1 PCI DSS Requirements**

**Data Protection**
- Never store cardholder data
- Use tokenization for payment methods
- Encrypt data transmission (TLS 1.2+)
- Secure network configurations

**Access Controls**
- Unique user IDs for system access
- Multi-factor authentication requirements
- Regular access reviews and updates
- Principle of least privilege

**Security Monitoring**
```yaml
Required Monitoring:
  - Failed payment attempts
  - Unusual transaction patterns  
  - System access logs
  - Network traffic analysis
  - File integrity monitoring
```

**Compliance Validation**
- Quarterly network vulnerability scans
- Annual penetration testing
- Daily log monitoring and analysis
- Regular security assessments

### 3D Secure Authentication

**🔐 3D Secure 2.0 Implementation**

**Benefits**
- Reduced chargebacks and fraud
- Improved payment success rates
- Regulatory compliance (SCA/PSD2)
- Enhanced customer confidence

**Integration Strategy**
```json
{
  "payment_method_options": {
    "card": {
      "request_three_d_secure": "automatic"
    }
  },
  "confirmation_method": "automatic",
  "return_url": "https://your-site.com/payments/confirm"
}
```

**Exemption Handling**
- Low-value transactions under €30
- Trusted merchant exemptions
- Corporate payment exemptions
- Recurring payment exemptions

## Payment Optimization Strategies

### Success Rate Optimization

**📈 Improving Authorization Rates**

**Payment Method Optimization**
```yaml
Optimization Techniques:
  - Multiple payment processor fallback
  - Smart payment routing
  - Currency optimization
  - Local payment method support
  - Dynamic descriptor optimization
```

**Transaction Timing**
- Avoid processing during high-traffic periods
- Implement intelligent retry logic
- Consider timezone optimization
- Plan for holiday and weekend impacts

**Customer Experience**
```javascript
// Optimized payment flow
const optimizePaymentFlow = {
  // Pre-populate customer data
  prefillCustomerInfo: true,
  
  // Multiple payment options
  showSavedCards: true,
  enableWallets: ['apple_pay', 'google_pay'],
  
  // Smooth error handling
  showInlineErrors: true,
  enableRealTimeValidation: true,
  
  // Mobile optimization
  responsive: true,
  touchOptimized: true
};
```

### Fraud Prevention

**🚨 Fraud Detection Systems**

**Risk Scoring Factors**
```yaml
High Risk Indicators:
  - Multiple failed payment attempts
  - Unusual geographic locations
  - High-value first transactions
  - Mismatched billing/shipping addresses
  - Rapid succession of transactions

Medium Risk Indicators:
  - New customer with high-value purchase
  - Different country from IP address
  - Multiple payment methods attempted
  - Unusual time-of-day patterns
```

**Automated Response Actions**
- Require additional verification for high-risk
- Implement velocity limits and cooling-off periods  
- Use machine learning for pattern recognition
- Manual review workflows for edge cases

**Custom Rules Engine**
```json
{
  "fraud_rules": [
    {
      "name": "velocity_check",
      "condition": "transactions > 3 in 1 hour",
      "action": "require_verification"
    },
    {
      "name": "geo_mismatch", 
      "condition": "billing_country != ip_country",
      "action": "manual_review"
    }
  ]
}
```

## Failed Payment Management

### Dunning Management

**📧 Automated Dunning Workflows**

**Standard Dunning Sequence**
```yaml
Day 0: Payment Failure
  - Immediate retry attempt
  - Email notification to customer
  - In-app notification display

Day 1: First Follow-up
  - Update payment method reminder
  - SMS notification (if enabled)
  - Account access warning

Day 3: Second Attempt  
  - Retry payment processing
  - Call-to-action email with discount
  - Customer service outreach

Day 7: Final Notice
  - Last retry attempt
  - Account suspension warning
  - Payment plan offering

Day 10: Service Suspension
  - Suspend account access
  - Preserve data for recovery period
  - Continue light-touch communications

Day 30: Account Cancellation
  - Cancel subscription
  - Data deletion scheduling
  - Win-back campaign enrollment
```

**Smart Recovery Strategies**

**Payment Method Updates**
- Proactive card expiration notifications
- One-click payment method updates
- Alternative payment method suggestions
- Assisted payment method changes

**Customer Communication**
```html
<!-- Effective dunning email template -->
<email>
  <subject>Action Required: Update Your Payment Method</subject>
  <body>
    <h1>Hi [Customer Name],</h1>
    
    <p>We couldn't process your payment for [Service Name]. 
    This happens sometimes due to:</p>
    
    <ul>
      <li>Expired card</li>
      <li>Changed billing address</li>
      <li>Bank security measures</li>
    </ul>
    
    <cta>Update Payment Method</cta>
    
    <p>Questions? Reply to this email or call [Support Phone]</p>
  </body>
</email>
```

### Recovery Optimization

**🎯 Winning Back Customers**

**Incentive Strategies**
- Limited-time discounts for payment updates
- Service credit for inconvenience
- Extended trial periods
- Feature upgrades or bonuses

**Personalized Outreach**
- Account manager calls for high-value customers
- Personalized email sequences
- Custom payment plan offerings
- Alternative billing cycle options

**Success Metrics**
```yaml
Key Recovery Metrics:
  - Involuntary churn rate: < 2%
  - Payment update rate: > 60%
  - Recovery email open rate: > 25%
  - Time to payment resolution: < 7 days
  - Customer satisfaction post-recovery: > 4.0/5.0
```

## Analytics and Reporting

### Payment Performance Metrics

**📊 Key Performance Indicators**

**Success Metrics**
```yaml
Authorization Rate: 
  - Target: > 95%
  - Benchmark by card type and geography
  - Track decline reason codes

Processing Speed:
  - Target: < 2 seconds average
  - Monitor by payment method
  - Track during peak periods

Customer Experience:
  - Payment form abandonment: < 10%
  - Time to complete payment: < 60 seconds
  - Payment method save rate: > 70%
```

**Financial Metrics**
- Total payment volume and growth
- Average transaction value trends
- Payment method cost analysis
- Currency conversion optimization
- Chargeback and dispute rates

### Advanced Analytics

**🔍 Payment Intelligence**

**Cohort Analysis**
- Payment success by customer segments
- Retry success rates by failure type
- Geographic performance variations
- Seasonal payment patterns

**Predictive Analytics**
```python
# Payment failure prediction model
def predict_payment_failure(customer_data):
    risk_factors = {
        'card_age_days': customer_data['card_age'],
        'previous_failures': customer_data['failure_count'],
        'transaction_amount': customer_data['amount'],
        'customer_tenure': customer_data['months_active']
    }
    
    risk_score = ml_model.predict(risk_factors)
    return risk_score
```

**Real-time Monitoring**
- Live payment success rate dashboard  
- Instant fraud detection alerts
- Payment processor health monitoring
- Customer payment journey tracking

## Troubleshooting Common Issues

### Payment Decline Scenarios

**💳 Card-Related Declines**

**Insufficient Funds**
```yaml
Error Code: insufficient_funds
Customer Message: "Your card was declined due to insufficient funds"
Recommended Actions:
  - Try a different payment method
  - Contact your bank
  - Use a different card
```

**Card Security Issues**
```yaml  
Error Code: security_violation
Customer Message: "Transaction blocked for security reasons"
Recommended Actions:
  - Verify billing address
  - Contact card issuer
  - Try alternative payment method
  - Complete 3D Secure authentication
```

**Expired or Invalid Cards**
```yaml
Error Code: expired_card
Customer Message: "Your card has expired"
Recommended Actions:
  - Update card expiration date
  - Add new payment method
  - Contact customer support
```

### Technical Integration Issues

**🔧 API and Webhook Problems**

**Webhook Delivery Failures**
```bash
# Webhook debugging checklist
1. Verify endpoint URL is accessible
2. Check SSL certificate validity
3. Confirm response time < 10 seconds
4. Validate HTTP status codes (200-299)
5. Review webhook signature validation
6. Monitor for timeout issues
```

**API Integration Errors**
```javascript
// Error handling best practices
try {
  const payment = await stripe.paymentIntents.create({
    amount: amount_cents,
    currency: 'usd',
    payment_method: payment_method_id,
    confirmation_method: 'manual',
    confirm: true
  });
} catch (error) {
  switch(error.code) {
    case 'card_declined':
      handleCardDecline(error);
      break;
    case 'insufficient_funds':  
      handleInsufficientFunds(error);
      break;
    default:
      handleGenericError(error);
  }
}
```

---

## Quick Reference

### Essential Setup Checklist
- [ ] Configure primary payment processor
- [ ] Set up webhook endpoints  
- [ ] Enable 3D Secure authentication
- [ ] Configure dunning management
- [ ] Set up fraud monitoring rules
- [ ] Test payment flows thoroughly
- [ ] Monitor success rates and metrics

### Emergency Contact Information
- **Stripe Support**: Available 24/7 via dashboard
- **PayPal Support**: Business support hotline
- **Powernode Support**: help@powernode.org
- **Security Issues**: security@powernode.org

Need help optimizing your payment infrastructure? Contact our payment specialists for personalized consultation and setup assistance.
MARKDOWN

article5 = KnowledgeBaseArticle.find_or_create_by(slug: "payment-methods-processing-guide") do |article|
  article.title = "Payment Methods and Processing Guide"
  article.category = payment_methods_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Comprehensive guide to managing payment methods, processing payments, handling failures, and optimizing your payment infrastructure."
  article.content = payment_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "✅ Article: #{article5.title}"

# Article 6: Troubleshooting Common Powernode Issues
troubleshooting_content = <<~MARKDOWN
# Troubleshooting Common Powernode Issues

Quick solutions and step-by-step fixes for the most common issues you may encounter while using Powernode.

## Account Access Issues

### Login Problems

**🔐 Cannot Login to Account**

**Forgotten Password**
1. Go to the login page
2. Click "Forgot Password"
3. Enter your email address
4. Check email for reset link (including spam folder)
5. Follow instructions to create new password

**Email Not Recognized**
1. Verify you're using the correct email address
2. Check if you have multiple Powernode accounts
3. Contact your account administrator
4. Reach out to support with account details

**Multi-Factor Authentication Issues**
1. Try backup codes if available
2. Resync your authenticator app time settings
3. Contact account administrator for MFA reset
4. Use account recovery process

**Account Locked**
```yaml
Common Causes:
  - Multiple failed login attempts
  - Suspicious activity detection
  - Manual admin suspension
  - Payment-related suspension

Resolution Steps:
  1. Wait 15 minutes and try again
  2. Contact account administrator
  3. Verify payment status
  4. Submit support ticket with details
```

### Permission and Access Errors

**❌ "Access Denied" Messages**

**Missing Permissions**
1. Verify your permission assignments
2. Contact account administrator
3. Check if permissions changed recently
4. Confirm account is active

**Page or Feature Not Visible**
```yaml
Troubleshooting Steps:
  1. Check user permissions in Settings > Team
  2. Verify account subscription level
  3. Clear browser cache and cookies
  4. Try different browser or incognito mode
  5. Check for maintenance notifications
```

**API Access Issues**
1. Verify API key is correct and active
2. Check permission scopes for API key
3. Confirm rate limits haven't been exceeded
4. Validate request format and endpoints

## Payment and Billing Issues

### Payment Failures

**💳 Credit Card Declined**

**Immediate Actions**
```yaml
Quick Fixes:
  1. Verify card details are correct
  2. Check card expiration date
  3. Confirm billing address matches bank records
  4. Try a different payment method
  5. Contact your bank about the transaction
```

**Common Decline Reasons**
- **Insufficient Funds**: Add money to account or use different card
- **Card Expired**: Update expiration date or add new card
- **Security Hold**: Contact bank to authorize transaction
- **International Block**: Enable international transactions
- **Daily Limit Exceeded**: Wait 24 hours or contact bank

**Payment Method Issues**
```bash
# Updating payment methods
1. Go to Settings > Billing
2. Click "Payment Methods"
3. Add new payment method or update existing
4. Set as default if needed
5. Test with small transaction
```

### Subscription Problems

**🔄 Subscription Status Issues**

**Subscription Not Active**
1. Check payment method validity
2. Verify recent payment succeeded
3. Review subscription status in dashboard
4. Check for service interruptions
5. Contact support if payment processed successfully

**Plan Changes Not Applied**
```yaml
Troubleshooting Plan Changes:
  1. Verify change was confirmed
  2. Check for proration calculations
  3. Review billing cycle timing
  4. Look for email confirmations
  5. Allow up to 24 hours for changes
```

**Billing Cycle Confusion**
- Review subscription start date
- Understand proration calculations
- Check next billing date
- Verify plan change timing
- Review billing history

### Invoice and Receipt Issues

**📄 Invoice Problems**

**Missing Invoices**
1. Check spam/junk email folders
2. Verify billing email address is correct
3. Download from account dashboard
4. Contact support for invoice resend

**Incorrect Invoice Amounts**
```yaml
Common Causes:
  - Proration from plan changes
  - Add-on services or usage charges
  - Tax calculations
  - Currency conversion
  - Previous credits or adjustments

Resolution:
  1. Review detailed line items
  2. Check plan change history
  3. Verify tax settings
  4. Contact support for explanation
```

## Technical Integration Issues

### API Problems

**🔧 API Integration Errors**

**Authentication Failures**
```bash
# Common authentication issues
HTTP 401 Unauthorized:
  - Verify API key is correct
  - Check API key hasn't expired
  - Confirm proper header format
  - Validate permission scopes

HTTP 403 Forbidden:
  - Check API key permissions
  - Verify account access level
  - Confirm endpoint requires correct scope
  - Review rate limiting status
```

**Request Format Issues**
```json
{
  "error": {
    "type": "validation_error",
    "message": "Invalid request format",
    "details": {
      "field": "email",
      "code": "required"
    }
  }
}
```

**Rate Limiting Problems**
```bash
HTTP 429 Too Many Requests:
  - Check rate limit headers
  - Implement exponential backoff
  - Reduce request frequency
  - Consider API key upgrade
  
Headers:
  X-RateLimit-Limit: 1000
  X-RateLimit-Remaining: 0
  X-RateLimit-Reset: 1642687200
```

### Webhook Issues

**📡 Webhook Delivery Problems**

**Webhooks Not Received**
```yaml
Debugging Checklist:
  1. Verify endpoint URL is accessible
  2. Check SSL certificate is valid
  3. Confirm response time < 10 seconds
  4. Review server logs for requests
  5. Test webhook endpoint manually
  6. Verify webhook signature validation
```

**Webhook Processing Errors**
```python
# Webhook debugging example
@app.route('/webhooks/powernode', methods=['POST'])
def handle_webhook():
    try:
        payload = request.get_data(as_text=True)
        signature = request.headers.get('X-Powernode-Signature')
        
        # Verify signature
        if not verify_signature(payload, signature):
            logger.error('Invalid webhook signature')
            return 'Invalid signature', 401
        
        # Process event
        event = json.loads(payload)
        process_event(event)
        
        return 'OK', 200
        
    except Exception as e:
        logger.error(f'Webhook processing error: {e}')
        return 'Error processing webhook', 500
```

**Webhook Retry Logic**
```yaml
Powernode Retry Strategy:
  - Immediate retry if 5xx error
  - Exponential backoff (1s, 2s, 4s, 8s, 16s)
  - Maximum 5 retry attempts
  - 24-hour retry window
  - Manual replay available in dashboard
```

## Performance and Data Issues

### Slow Performance

**⏱️ Dashboard Loading Slowly**

**Browser-Related Issues**
1. Clear browser cache and cookies
2. Disable browser extensions temporarily
3. Try different browser (Chrome, Firefox, Safari)
4. Use incognito/private browsing mode
5. Check internet connection speed

**Account-Specific Issues**
```yaml
Performance Optimization:
  1. Reduce dashboard widget count
  2. Adjust date ranges for reports
  3. Filter large data sets
  4. Use pagination for large lists
  5. Contact support for account optimization
```

**Network and Connectivity**
- Check internet connection stability
- Try different network or VPN
- Test from different device
- Verify firewall isn't blocking requests
- Contact IT department for whitelist

### Data Synchronization Issues

**📊 Data Not Updating**

**Real-time Data Problems**
1. Refresh browser page
2. Check last update timestamp
3. Verify data source connectivity
4. Review API rate limiting
5. Contact support for data refresh

**Export and Reporting Issues**
```yaml
Common Export Problems:
  - File format compatibility
  - Date range too large
  - Insufficient permissions
  - Browser popup blocking
  - Network timeout during download

Solutions:
  1. Try smaller date ranges
  2. Use different file format
  3. Disable popup blockers
  4. Use different browser
  5. Contact support for large exports
```

## Feature-Specific Issues

### Subscription Management

**📋 Subscription Creation Problems**

**Customer Creation Fails**
```json
{
  "error": {
    "type": "validation_error", 
    "message": "Customer email already exists",
    "details": {
      "field": "email",
      "code": "duplicate_value"
    }
  }
}
```

**Plan Configuration Issues**
1. Verify plan is active and available
2. Check plan pricing configuration
3. Confirm currency settings match
4. Review trial period settings
5. Validate plan feature limitations

### Team Management

**👥 Team Invitation Problems**

**Invitations Not Delivered**
1. Check recipient's spam/junk folder
2. Verify email address spelling
3. Resend invitation from team settings
4. Try alternative email address
5. Check email server blacklisting

**Permission Assignment Issues**
```yaml
Permission Troubleshooting:
  1. Verify permission exists and is active
  2. Check for permission conflicts
  3. Review account subscription level
  4. Confirm user acceptance of invitation
  5. Allow time for permission propagation
```

## Getting Additional Help

### Self-Service Resources

**📚 Documentation and Guides**
- Knowledge Base search function
- Video tutorials and walkthroughs
- API documentation and examples
- Community forum discussions
- FAQ section for quick answers

**🔍 Diagnostic Tools**
```bash
# Built-in diagnostic features
1. Account health check in dashboard
2. API connection tester
3. Webhook delivery logs
4. Payment processing history
5. System status page monitoring
```

### Contacting Support

**📞 When to Contact Support**

**Immediate Support Needed**
- Payment processing failures affecting business
- Security concerns or suspicious activity
- Data loss or corruption issues
- Critical API integration failures
- Account access completely blocked

**Standard Support Process**
```yaml
Support Ticket Information:
  Required Details:
    - Account email address
    - Specific error messages
    - Steps to reproduce issue
    - Browser/device information
    - Timestamps of problems
    
  Response Times:
    - Critical: 1 hour
    - High: 4 hours  
    - Normal: 24 hours
    - Low: 48 hours
```

### Preparing for Support Contact

**📋 Information to Gather**

**Technical Issues**
1. Exact error messages (screenshots helpful)
2. Steps taken to reproduce the issue
3. Browser version and operating system
4. Account details (never include passwords)
5. Affected features or API endpoints

**Billing Issues**
1. Invoice numbers or payment IDs
2. Payment method details (last 4 digits only)
3. Expected vs actual charges
4. Date and time of transactions
5. Currency and amount information

**Integration Issues**
```yaml
API Integration Details:
  - API endpoint URLs being used
  - Request/response examples
  - HTTP status codes received
  - Rate limiting information
  - Webhook delivery attempts
  - Integration timeline and changes
```

---

## Emergency Contact Information

**🚨 Critical Issues**
- **Security Emergencies**: security@powernode.org
- **Payment Processing**: Available 24/7 via dashboard
- **System Outages**: Check status.powernode.org
- **Data Breaches**: Immediate escalation protocol

**📧 Standard Support**
- **General Support**: support@powernode.org  
- **Technical Issues**: tech@powernode.org
- **Billing Questions**: billing@powernode.org
- **API Integration**: developers@powernode.org

**💬 Community Resources**
- **User Forum**: community.powernode.org
- **Developer Slack**: Join at powernode.org/slack
- **Status Updates**: Follow @PowernodeStatus
- **Knowledge Base**: Browse all available guides

Most issues can be resolved quickly using this troubleshooting guide. For complex problems or if these solutions don't work, don't hesitate to contact our support team with detailed information about your issue.
MARKDOWN

article6 = KnowledgeBaseArticle.find_or_create_by(slug: "troubleshooting-common-powernode-issues") do |article|
  article.title = "Troubleshooting Common Powernode Issues"
  article.category = troubleshooting_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Quick solutions to the most common issues in Powernode. Find answers to login problems, payment failures, API errors, and integration challenges."
  article.content = troubleshooting_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "✅ Article: #{article6.title}"

# Summary
puts "\n📊 Knowledge Base Articles Summary:"
puts "   Categories: #{KnowledgeBaseCategory.count}"
puts "   Total Articles: #{KnowledgeBaseArticle.count}"
puts "   Featured Articles: #{KnowledgeBaseArticle.where(is_featured: true).count}"
puts "   Published Articles: #{KnowledgeBaseArticle.where(status: 'published').count}"

puts "\n✅ Knowledge Base seeding completed successfully!"