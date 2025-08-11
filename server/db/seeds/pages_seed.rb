# Create welcome page seed data

# Find or create admin user for authoring pages
admin_user = User.joins(:roles)
                 .where(roles: { name: ['owner', 'admin'] })
                 .first

# Fallback: use first user if none exists with admin roles
unless admin_user
  puts "No admin user found. Using first existing user or skipping user creation..."
  admin_user = User.first
  
  unless admin_user
    puts "❌ No users found in database. Please create a user first before seeding pages."
    exit(1)
  end
  
  puts "✅ Using existing user for page authoring: #{admin_user.email}"
end

# Welcome page content
welcome_content = <<~MARKDOWN
# Welcome to Powernode

**The modern subscription management platform built for growth.**

Powernode empowers businesses to manage subscriptions, process payments, and scale their recurring revenue with ease. Whether you're a startup launching your first SaaS product or an enterprise managing thousands of customers, Powernode provides the tools you need to succeed.

## 🚀 Why Choose Powernode?

### **Comprehensive Subscription Management**
- Complete subscription lifecycle management
- Flexible billing cycles and proration
- Automated renewals and dunning management
- Advanced analytics and reporting

### **Powerful Payment Processing**
- Multiple payment gateway support (Stripe, PayPal)
- PCI-compliant security standards
- Global currency support
- Intelligent payment retry logic

### **Enterprise-Grade Features**
- Multi-tenant architecture
- Role-based access control
- Comprehensive audit logging
- API-first design for seamless integrations

### **Built for Scale**
- High-performance Rails 8 backend
- React-powered modern frontend
- Background job processing with Sidekiq
- PostgreSQL for reliable data storage

## 💡 Key Features

**📊 Analytics Dashboard**
Get real-time insights into your subscription business with comprehensive analytics, including MRR/ARR tracking, churn analysis, and customer lifetime value calculations.

**⚙️ Flexible Plan Management**
Create and manage unlimited subscription plans with custom features, limits, and pricing tiers. Support for free trials, setup fees, and promotional pricing.

**👥 Customer Management**
Centralized customer database with detailed subscription histories, payment records, and communication logs. Built-in customer support tools.

**🔄 Automated Billing**
Set it and forget it billing automation with intelligent proration, failed payment recovery, and customizable billing notifications.

**🛡️ Security & Compliance**
Built with security first - JWT authentication, encrypted data storage, audit logs, and PCI DSS compliance for payment processing.

**🔗 Developer-Friendly APIs**
RESTful APIs for all platform functions, comprehensive documentation, and webhook support for real-time integrations.

## 🎯 Perfect For

- **SaaS Startups** - Launch with professional subscription management from day one
- **Growing Businesses** - Scale your recurring revenue with advanced tools and insights  
- **Enterprises** - Manage complex subscription models with enterprise-grade features
- **Developers** - Integrate seamlessly with comprehensive APIs and documentation

## 🌟 Success Stories

*"Powernode helped us streamline our subscription management and reduce churn by 40% in the first quarter. The analytics insights were game-changing for our business decisions."*

**— Sarah Chen, CEO at TechFlow Solutions**

---

*"The API-first approach made integration a breeze. We were up and running in days, not months. Customer support has been exceptional throughout our journey."*

**— Marcus Rodriguez, CTO at CloudScale**

## 📈 Trusted by Growing Companies

Join thousands of businesses worldwide who trust Powernode to power their subscription growth:

- **500+** Active businesses
- **$50M+** In processed revenue  
- **99.9%** Uptime reliability
- **24/7** Customer support

## 🎊 Ready to Transform Your Business?

Start your journey with Powernode today. Choose from our flexible plans designed to grow with your business, or contact our team for a custom enterprise solution.

**✨ 14-day free trial • No setup fees • Cancel anytime**

---

*Experience the power of modern subscription management. Your customers will thank you, and your bottom line will too.*
MARKDOWN

# Create or update welcome page
welcome_page = Page.find_or_initialize_by(slug: 'welcome')

welcome_page.assign_attributes(
  title: 'Welcome to Powernode',
  content: welcome_content,
  meta_description: 'Powernode is the modern subscription management platform built for growth. Manage subscriptions, process payments, and scale your recurring revenue with enterprise-grade tools.',
  meta_keywords: 'subscription management, SaaS platform, recurring billing, payment processing, subscription analytics, customer management, enterprise software',
  status: 'published',
  author: admin_user,
  published_at: Time.current
)

if welcome_page.save
  puts "✅ Welcome page created/updated successfully!"
  puts "   - Title: #{welcome_page.title}"
  puts "   - Slug: #{welcome_page.slug}"
  puts "   - Status: #{welcome_page.status}"
  puts "   - Word count: #{welcome_page.word_count}"
  puts "   - Author: #{welcome_page.author.full_name}"
else
  puts "❌ Failed to create welcome page:"
  welcome_page.errors.full_messages.each do |error|
    puts "   - #{error}"
  end
end

# Create additional sample pages
sample_pages = [
  {
    title: 'About Us',
    slug: 'about-us',
    content: <<~MARKDOWN,
# About Powernode

## Our Mission

At Powernode, we believe that managing subscriptions shouldn't be complicated. Our mission is to empower businesses of all sizes with the tools they need to build, manage, and scale their subscription-based revenue streams.

## Our Story

Founded in 2024 by a team of experienced developers and business leaders, Powernode was born from the frustration of dealing with complex, expensive subscription management solutions that didn't meet the needs of modern businesses.

We set out to build something better - a platform that combines powerful features with intuitive design, enterprise-grade security with startup-friendly pricing, and comprehensive functionality with developer-friendly APIs.

## Our Values

### **Customer First**
Every decision we make is guided by what's best for our customers. We listen, we learn, and we build solutions that solve real problems.

### **Transparency**
We believe in clear communication, honest pricing, and open development practices. No hidden fees, no surprises.

### **Innovation**
We're constantly pushing the boundaries of what's possible in subscription management, always looking for better ways to serve our customers.

### **Reliability**
Your business depends on us, and we take that responsibility seriously. We build for scale, security, and uptime.

## Our Team

We're a distributed team of passionate professionals dedicated to building the best subscription management platform in the world. From our engineers to our customer success team, everyone at Powernode is committed to your success.

## Contact Us

Ready to learn more? We'd love to hear from you.

- **Email**: hello@powernode.com
- **Support**: support@powernode.com
- **Sales**: sales@powernode.com

---

*Building the future of subscription management, one customer at a time.*
MARKDOWN
    meta_description: 'Learn about Powernode\'s mission, values, and the team building the future of subscription management.',
    meta_keywords: 'about powernode, company mission, subscription management team, SaaS platform company'
  },
  {
    title: 'Getting Started Guide',
    slug: 'getting-started',
    content: <<~MARKDOWN,
# Getting Started with Powernode

Welcome to Powernode! This guide will help you set up your account and start managing subscriptions in no time.

## Step 1: Choose Your Plan

Select the plan that best fits your needs:

- **Starter**: Perfect for new businesses with up to 100 customers
- **Professional**: Ideal for growing companies with advanced needs  
- **Enterprise**: Custom solutions for large organizations

[View all plans and pricing →](/plans)

## Step 2: Set Up Your Account

1. **Create your account** with your business email
2. **Verify your email address** to activate your account
3. **Complete your profile** with business information
4. **Configure your first payment gateway** (Stripe or PayPal)

## Step 3: Create Your First Plan

1. Navigate to **Plans** in your dashboard
2. Click **"Create Plan"**
3. Define your pricing, billing cycle, and features
4. Set up trial periods and promotional pricing (optional)
5. **Publish** your plan to make it available

## Step 4: Invite Your Team

1. Go to **Settings** > **Team Management**
2. Send invitations to team members
3. Assign appropriate roles and permissions
4. Collaborate on subscription management

## Step 5: Start Accepting Subscriptions

Your subscription system is now ready! Customers can:

- Browse your plans
- Subscribe with secure payment processing
- Manage their subscriptions through the customer portal
- Receive automated billing notifications

## Need Help?

- 📚 **Documentation**: Comprehensive guides and API reference
- 💬 **Support Chat**: Get help from our support team
- 📧 **Email Support**: support@powernode.com
- 🎥 **Video Tutorials**: Step-by-step visual guides

---

**Ready to dive deeper?** Explore our advanced features like analytics, webhooks, and API integrations in the dashboard.
MARKDOWN
    meta_description: 'Learn how to get started with Powernode subscription management platform. Step-by-step setup guide for new users.',
    meta_keywords: 'getting started, setup guide, powernode tutorial, subscription platform onboarding'
  },
  {
    title: 'API Documentation',
    slug: 'api-docs',
    content: <<~MARKDOWN,
# Powernode API Documentation

Build powerful integrations with Powernode's comprehensive RESTful API. Our API is designed to be developer-friendly with consistent patterns, detailed responses, and extensive documentation.

## Quick Start

### Authentication

All API requests require authentication using JWT Bearer tokens:

```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \\
     -H "Content-Type: application/json" \\
     https://api.powernode.com/v1/subscriptions
```

### Base URL

```
https://api.powernode.com/v1/
```

### Rate Limiting

- **Standard**: 1000 requests per hour
- **Professional**: 5000 requests per hour  
- **Enterprise**: 10000 requests per hour

## Core Resources

### Subscriptions

Manage customer subscriptions and billing cycles.

#### List Subscriptions

```http
GET /v1/subscriptions
```

**Parameters:**
- `page` (integer): Page number for pagination
- `per_page` (integer): Items per page (max 100)
- `status` (string): Filter by status (active, cancelled, past_due)

**Response:**
```json
{
  "data": [
    {
      "id": "sub_1234567890",
      "customer_id": "cus_1234567890", 
      "plan_id": "plan_basic",
      "status": "active",
      "current_period_start": "2024-01-01T00:00:00Z",
      "current_period_end": "2024-02-01T00:00:00Z",
      "created_at": "2024-01-01T00:00:00Z"
    }
  ],
  "meta": {
    "total": 150,
    "page": 1,
    "per_page": 25,
    "total_pages": 6
  }
}
```

#### Create Subscription

```http
POST /v1/subscriptions
```

**Request Body:**
```json
{
  "customer_id": "cus_1234567890",
  "plan_id": "plan_basic",
  "trial_days": 14,
  "payment_method_id": "pm_1234567890"
}
```

### Plans

Define your subscription pricing and features.

#### List Plans

```http
GET /v1/plans
```

#### Create Plan

```http
POST /v1/plans
```

**Request Body:**
```json
{
  "name": "Professional Plan",
  "price": 2999,
  "currency": "usd",
  "interval": "month",
  "features": {
    "users": 10,
    "storage": "100GB",
    "api_calls": 10000
  }
}
```

### Customers

Manage your customer database and profiles.

#### List Customers

```http
GET /v1/customers
```

#### Create Customer

```http
POST /v1/customers
```

### Invoices

Access billing history and invoice data.

#### List Invoices

```http
GET /v1/invoices
```

#### Download Invoice

```http
GET /v1/invoices/:id/download
```

## Webhooks

Stay synchronized with real-time events using webhooks.

### Supported Events

- `subscription.created`
- `subscription.updated` 
- `subscription.cancelled`
- `invoice.payment_succeeded`
- `invoice.payment_failed`
- `customer.updated`

### Webhook Example

```json
{
  "id": "evt_1234567890",
  "type": "subscription.created",
  "created": 1640995200,
  "data": {
    "object": {
      "id": "sub_1234567890",
      "status": "active",
      "customer": "cus_1234567890"
    }
  }
}
```

### Webhook Verification

Verify webhook authenticity using HMAC signatures:

```python
import hmac
import hashlib

def verify_webhook(payload, signature, secret):
    expected = hmac.new(
        secret.encode(),
        payload.encode(),
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(signature, expected)
```

## SDKs and Libraries

Official SDKs are available for popular programming languages:

### Node.js

```bash
npm install @powernode/node
```

```javascript
const Powernode = require('@powernode/node');
const client = new Powernode('your-api-key');

const subscription = await client.subscriptions.create({
  customer_id: 'cus_1234567890',
  plan_id: 'plan_basic'
});
```

### Python

```bash
pip install powernode-python
```

```python
import powernode

powernode.api_key = 'your-api-key'

subscription = powernode.Subscription.create(
    customer_id='cus_1234567890',
    plan_id='plan_basic'
)
```

### Ruby

```bash
gem install powernode-ruby
```

```ruby
require 'powernode'

Powernode.api_key = 'your-api-key'

subscription = Powernode::Subscription.create(
  customer_id: 'cus_1234567890',
  plan_id: 'plan_basic'
)
```

## Error Handling

The API uses conventional HTTP response codes and provides detailed error information:

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "missing_parameter",
    "message": "Missing required parameter: customer_id",
    "param": "customer_id"
  }
}
```

### HTTP Status Codes

- `200` - Success
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `429` - Too Many Requests
- `500` - Internal Server Error

## Need Help?

- **API Support**: api-support@powernode.com
- **Documentation**: [docs.powernode.com](https://docs.powernode.com)
- **Community**: [community.powernode.com](https://community.powernode.com)
- **Status Page**: [status.powernode.com](https://status.powernode.com)

---

**Ready to build?** Get your API keys from the dashboard and start integrating with Powernode today.
MARKDOWN
    meta_description: 'Complete API documentation for Powernode subscription management platform. RESTful API reference with examples and SDKs.',
    meta_keywords: 'powernode api, rest api, subscription api, billing api, webhook documentation, developer docs'
  },
  {
    title: 'Privacy Policy',
    slug: 'privacy-policy',
    content: <<~MARKDOWN,
# Privacy Policy

**Effective Date:** January 1, 2024  
**Last Updated:** January 1, 2024

## Overview

At Powernode ("we," "our," or "us"), we are committed to protecting your privacy and ensuring the security of your personal information. This Privacy Policy explains how we collect, use, share, and protect your information when you use our subscription management platform.

## Information We Collect

### Account Information
- **Contact Details**: Name, email address, phone number
- **Business Information**: Company name, business address, tax identification
- **Authentication Data**: Password (encrypted), security preferences

### Usage Information  
- **Platform Activity**: Features used, pages visited, time spent
- **Device Information**: IP address, browser type, device identifiers
- **Performance Data**: API calls, system performance metrics

### Payment Information
- **Billing Details**: Billing address, payment method information
- **Transaction Data**: Payment history, invoice records, subscription details
- **Financial Information**: Processed securely through PCI-compliant payment processors

### Customer Data
- **Subscriber Information**: Data about your customers that you store in Powernode
- **Subscription Records**: Customer subscription histories and preferences
- **Communication Logs**: Support tickets, email communications

## How We Use Your Information

### Platform Operations
- Provide and maintain our subscription management services
- Process payments and manage billing operations
- Authenticate users and secure accounts
- Provide customer support and technical assistance

### Service Improvement
- Analyze usage patterns to improve platform features
- Develop new functionality based on user needs  
- Monitor system performance and reliability
- Conduct security assessments and fraud prevention

### Communication
- Send service-related notifications and updates
- Provide customer support and technical assistance
- Share important changes to our terms or policies
- Marketing communications (with your consent)

## Information Sharing

We do not sell, rent, or trade your personal information. We may share information in these limited circumstances:

### Service Providers
- **Payment Processors**: Stripe, PayPal for secure payment processing
- **Cloud Infrastructure**: AWS, Google Cloud for hosting and data storage
- **Analytics Providers**: For usage analytics and performance monitoring
- **Support Tools**: Customer service platforms for support ticket management

### Legal Requirements
- Comply with applicable laws and regulations
- Respond to legal process and government requests
- Protect our rights, privacy, safety, or property
- Enforce our terms of service and agreements

### Business Transfers
In the event of a merger, acquisition, or sale of assets, your information may be transferred as part of the business transaction, subject to equivalent privacy protections.

## Data Security

### Technical Safeguards
- **Encryption**: Data encrypted in transit (TLS 1.3) and at rest (AES-256)
- **Access Controls**: Multi-factor authentication and role-based permissions
- **Network Security**: Firewalls, intrusion detection, and monitoring systems
- **Regular Audits**: Security assessments and penetration testing

### Operational Security
- **Employee Training**: Regular security and privacy training for all staff
- **Background Checks**: Screening for personnel with data access
- **Incident Response**: Procedures for detecting and responding to security events
- **Data Minimization**: Collect and retain only necessary information

### Compliance
- **PCI DSS**: Payment Card Industry Data Security Standard compliance
- **SOC 2 Type II**: Annual security and availability audits
- **GDPR**: European General Data Protection Regulation compliance
- **CCPA**: California Consumer Privacy Act compliance

## Your Rights and Choices

### Access and Control
- **Account Dashboard**: View and update your personal information
- **Data Export**: Download your data in portable formats
- **Account Deletion**: Request deletion of your account and data
- **Communication Preferences**: Opt out of marketing communications

### Privacy Rights (GDPR/CCPA)
- **Right to Know**: What personal information we collect and how it's used
- **Right to Delete**: Request deletion of your personal information
- **Right to Correct**: Update or correct inaccurate personal information
- **Right to Portability**: Receive your data in a portable format

### Exercising Your Rights
To exercise any of these rights, contact us at privacy@powernode.com or through your account dashboard.

## Data Retention

### Account Data
- **Active Accounts**: Retained while your account is active
- **Closed Accounts**: Deleted within 90 days of account closure
- **Legal Holds**: Retained longer when required by law

### Transaction Data
- **Payment Records**: Retained for 7 years for tax and compliance purposes
- **Subscription History**: Retained for 3 years for analytics and support
- **Communication Logs**: Retained for 2 years for quality assurance

## International Data Transfers

Powernode is based in the United States. If you access our services from outside the U.S., your information may be transferred to, stored, and processed in the U.S. We implement appropriate safeguards for international transfers, including:

- **Standard Contractual Clauses**: EU-approved contractual terms
- **Adequacy Decisions**: Transfers to countries with adequate privacy laws
- **Binding Corporate Rules**: Internal policies for data protection

## Children's Privacy

Our services are not intended for individuals under 13 years of age. We do not knowingly collect personal information from children under 13. If you believe we have collected such information, please contact us immediately.

## Changes to This Policy

We may update this Privacy Policy periodically to reflect changes in our practices or legal requirements. We will:

- Post the updated policy on our website
- Email registered users about material changes
- Provide 30 days' notice for significant changes
- Maintain previous versions for reference

## Contact Information

### Privacy Inquiries
- **Email**: privacy@powernode.com
- **Address**: Powernode Privacy Team, 123 Technology Drive, San Francisco, CA 94105

### Data Protection Officer
- **Email**: dpo@powernode.com
- **Phone**: +1 (555) 123-4567

### Support
- **General Support**: support@powernode.com
- **Security Issues**: security@powernode.com

---

**Questions?** We're here to help. Contact our Privacy Team at privacy@powernode.com for any questions about this policy or our privacy practices.
MARKDOWN
    meta_description: 'Powernode Privacy Policy - Learn how we collect, use, and protect your personal information on our subscription management platform.',
    meta_keywords: 'privacy policy, data protection, GDPR compliance, personal information, subscription platform privacy'
  },
  {
    title: 'Blog: 5 Ways to Reduce Subscription Churn',
    slug: 'reduce-subscription-churn',
    content: <<~MARKDOWN,
# 5 Proven Ways to Reduce Subscription Churn and Boost Customer Retention

*Published on January 15, 2024 • 8 min read*

Subscription churn is one of the biggest challenges facing SaaS businesses today. With the average churn rate across industries hovering around 5-7% monthly, reducing churn even by a few percentage points can dramatically impact your bottom line.

After analyzing thousands of subscription businesses using Powernode, we've identified five proven strategies that consistently reduce churn and improve customer lifetime value.

## 1. Implement Proactive Customer Success Programs

**The Problem:** Many businesses only reach out to customers when they're already at risk of churning or have submitted a cancellation request.

**The Solution:** Create proactive touchpoints throughout the customer journey:

### Onboarding Excellence
- **First 7 Days**: Daily check-ins with new subscribers
- **30-Day Mark**: Comprehensive usage review and optimization recommendations
- **90-Day Mark**: Strategic consultation on expanding use cases

### Success Metrics to Track
- Time to first value realization
- Feature adoption rates  
- Support ticket resolution time
- Customer health scores

**Real Example:** TechFlow Solutions reduced their 90-day churn by 35% by implementing weekly check-ins for new customers and providing personalized onboarding guides.

> *"The proactive approach transformed our relationship with customers. Instead of waiting for problems, we're now helping customers succeed from day one."* - Sarah Chen, CEO at TechFlow Solutions

## 2. Use Data-Driven Churn Prediction

**The Problem:** By the time customers express dissatisfaction, it's often too late to retain them.

**The Solution:** Leverage behavioral data to identify at-risk customers before they churn:

### Key Early Warning Signals
- **Declining usage patterns**: 50% drop in activity over 2 weeks
- **Feature abandonment**: Stopped using key features
- **Support ticket patterns**: Multiple unresolved issues
- **Engagement drops**: Reduced email opens, dashboard logins

### Powernode's Churn Prediction Features
- Automated risk scoring based on usage patterns
- Real-time alerts for at-risk accounts
- Customizable intervention workflows
- A/B testing for retention campaigns

**Case Study:** CloudScale implemented churn prediction and reduced their monthly churn from 8% to 5.2% within six months by proactively reaching out to at-risk customers.

## 3. Optimize Your Pricing and Packaging

**The Problem:** Customers churn when they don't see value in their current plan or feel they're overpaying.

**The Solution:** Create flexible pricing that grows with your customers:

### Value-Based Pricing Strategies

#### **Tiered Pricing**
```
Starter: $29/month
- Up to 100 customers
- Basic analytics  
- Email support

Professional: $99/month  
- Up to 1,000 customers
- Advanced analytics
- Priority support
- API access

Enterprise: Custom pricing
- Unlimited customers
- Custom integrations
- Dedicated support
```

#### **Usage-Based Components**
- Base subscription fee + per-customer charges
- Volume discounts for larger accounts
- Seasonal adjustments for cyclical businesses

### Plan Migration Strategies
- **Downgrades**: Offer feature-limited plans instead of cancellation
- **Pause Options**: Temporary suspension for seasonal businesses  
- **Win-Back Offers**: Targeted discounts for churned customers

## 4. Create Exceptional Customer Support Experiences

**The Problem:** Poor support experiences are a leading cause of subscription cancellations.

**The Solution:** Transform support from a cost center into a retention engine:

### Multi-Channel Support Strategy
- **Live Chat**: Instant help during business hours
- **Email Support**: Detailed responses within 4 hours
- **Video Calls**: Screen sharing for complex issues  
- **Self-Service**: Comprehensive knowledge base and tutorials

### Support Excellence Metrics
- First response time: < 1 hour
- Resolution time: < 24 hours for standard issues
- Customer satisfaction score: > 4.5/5
- First-contact resolution rate: > 70%

### Proactive Support Initiatives
- **Health Check Calls**: Monthly reviews with key accounts
- **Feature Training**: Webinars and workshops
- **Best Practice Sharing**: Industry benchmarks and optimization tips

## 5. Build Strong Product Engagement

**The Problem:** Customers who don't fully utilize your product are more likely to churn.

**The Solution:** Drive deep product engagement through strategic feature adoption:

### Feature Adoption Framework

#### **Core Features** (Must Use)
- Essential functionality that defines your product value
- Target: 100% adoption within 30 days
- Heavy onboarding focus and training

#### **Power Features** (Nice to Use)  
- Advanced capabilities that increase stickiness
- Target: 40-60% adoption within 90 days
- Progressive disclosure and education

#### **Expansion Features** (Future Value)
- Functionality that opens upgrade opportunities  
- Target: 20-30% adoption within 180 days
- Strategic positioning and demos

### Engagement Tactics
- **Progressive Onboarding**: Introduce features gradually
- **In-App Guidance**: Tooltips, tutorials, and contextual help
- **Achievement Systems**: Gamification for feature completion
- **Regular Training**: Monthly webinars and best practice sessions

### Measuring Success
```
Customer Health Score = 
  (Feature Adoption × 0.3) + 
  (Usage Frequency × 0.3) + 
  (Support Satisfaction × 0.2) + 
  (Payment History × 0.2)
```

## Implementation Roadmap

### Month 1: Foundation
- [ ] Set up churn prediction tracking
- [ ] Implement customer health scoring
- [ ] Design proactive outreach workflows

### Month 2: Optimization  
- [ ] Launch enhanced onboarding program
- [ ] A/B test retention offers
- [ ] Upgrade support response times

### Month 3: Scale
- [ ] Automate intervention campaigns
- [ ] Expand self-service resources
- [ ] Launch customer success program

## Measuring Your Success

Track these key metrics to measure the impact of your churn reduction efforts:

### Primary Metrics
- **Monthly Churn Rate**: Percentage of customers who cancel each month
- **Customer Lifetime Value (CLV)**: Average revenue per customer over their lifecycle
- **Net Revenue Retention**: Revenue growth from existing customers

### Secondary Metrics  
- **Time to Churn**: How long customers stay before cancelling
- **Voluntary vs. Involuntary Churn**: Intentional vs. payment-related cancellations
- **Churn by Cohort**: How retention varies by customer segment

### Success Benchmarks
- **Excellent**: < 3% monthly churn
- **Good**: 3-5% monthly churn  
- **Needs Improvement**: > 5% monthly churn

## Conclusion

Reducing subscription churn requires a comprehensive approach that touches every aspect of the customer experience. By implementing these five strategies—proactive customer success, data-driven predictions, optimized pricing, exceptional support, and strong product engagement—you can significantly improve retention and drive sustainable growth.

Remember: a 1% reduction in monthly churn can increase customer lifetime value by 12-18%, making retention investments some of the highest-ROI activities for subscription businesses.

**Ready to reduce churn and boost retention?** Powernode's built-in churn prediction and customer success tools make it easy to implement these strategies at scale.

---

### About the Author

**Marcus Rodriguez** is the Head of Customer Success at Powernode, where he helps subscription businesses reduce churn and improve customer retention. With over 8 years of experience in SaaS customer success, Marcus has helped hundreds of companies optimize their retention strategies.

### Related Articles
- [The Complete Guide to Customer Success Metrics](/blog/customer-success-metrics)
- [Pricing Strategies That Reduce Churn](/blog/pricing-strategies)  
- [Building a World-Class Support Team](/blog/support-excellence)

**Have questions about reducing churn?** Reach out to our team at success@powernode.com or schedule a consultation through your dashboard.
MARKDOWN
    meta_description: 'Learn 5 proven strategies to reduce subscription churn and boost customer retention. Data-driven insights from analyzing thousands of subscription businesses.',
    meta_keywords: 'subscription churn, customer retention, SaaS churn reduction, customer success, subscription business'
  }
]

sample_pages.each do |page_data|
  page = Page.find_or_initialize_by(slug: page_data[:slug])
  
  page.assign_attributes(
    title: page_data[:title],
    content: page_data[:content],
    meta_description: page_data[:meta_description],
    meta_keywords: page_data[:meta_keywords],
    status: 'published',
    author: admin_user,
    published_at: Time.current
  )
  
  if page.save
    puts "✅ #{page.title} page created/updated successfully!"
  else
    puts "❌ Failed to create #{page.title} page:"
    page.errors.full_messages.each do |error|
      puts "   - #{error}"
    end
  end
end

puts "\n🎉 Page seeding completed!"
puts "📄 #{Page.published.count} published pages available"
puts "🌐 Welcome page available at: /welcome"