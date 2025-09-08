# frozen_string_literal: true

puts "Seeding Knowledge Base content..."

# Get system admin user to be the author
admin_user = User.find_by(email: 'admin@powernode.org')
if admin_user.nil?
  puts "  ✗ Admin user not found, skipping KB content seeding"
  return
end

# Create KB Categories
categories_data = [
  {
    name: 'Getting Started',
    slug: 'getting-started',
    description: 'Essential guides for new users to get up and running',
    sort_order: 1,
    subcategories: [
      { name: 'Account Setup', slug: 'account-setup', description: 'How to set up your account' },
      { name: 'First Steps', slug: 'first-steps', description: 'Your first steps with Powernode' }
    ]
  },
  {
    name: 'Billing & Subscriptions',
    slug: 'billing-subscriptions', 
    description: 'Everything about billing, plans, and subscription management',
    sort_order: 2,
    subcategories: [
      { name: 'Payment Methods', slug: 'payment-methods', description: 'Managing your payment methods' },
      { name: 'Plan Upgrades', slug: 'plan-upgrades', description: 'Upgrading and downgrading plans' }
    ]
  },
  {
    name: 'API Documentation',
    slug: 'api-documentation',
    description: 'Complete API reference and integration guides',
    sort_order: 3,
    subcategories: [
      { name: 'Authentication', slug: 'authentication', description: 'API authentication methods' },
      { name: 'REST API', slug: 'rest-api', description: 'REST API endpoints and usage' }
    ]
  },
  {
    name: 'Troubleshooting',
    slug: 'troubleshooting',
    description: 'Common issues and their solutions',
    sort_order: 4
  }
]

puts "\nCreating categories and subcategories..."
categories = {}

categories_data.each do |cat_data|
  category = KnowledgeBaseCategory.create!(
    name: cat_data[:name],
    slug: cat_data[:slug],
    description: cat_data[:description],
    sort_order: cat_data[:sort_order],
    is_public: true
  )
  categories[cat_data[:slug]] = category
  puts "  ✓ Created category: #{category.name}"
  
  # Create subcategories if any
  if cat_data[:subcategories]
    cat_data[:subcategories].each_with_index do |sub_data, index|
      subcategory = KnowledgeBaseCategory.create!(
        name: sub_data[:name],
        slug: sub_data[:slug],
        description: sub_data[:description],
        parent_id: category.id,
        sort_order: index + 1,
        is_public: true
      )
      categories[sub_data[:slug]] = subcategory
      puts "    ✓ Created subcategory: #{subcategory.name}"
    end
  end
end

# Create KB Tags
tags_data = [
  { name: 'Beginner', color: '#10B981' },
  { name: 'Advanced', color: '#F59E0B' },
  { name: 'API', color: '#3B82F6' },
  { name: 'Tutorial', color: '#8B5CF6' },
  { name: 'Troubleshooting', color: '#EF4444' },
  { name: 'Best Practices', color: '#059669' },
  { name: 'Security', color: '#DC2626' },
  { name: 'Integration', color: '#7C3AED' }
]

puts "\nCreating tags..."
tags = {}

tags_data.each do |tag_data|
  tag = KnowledgeBaseTag.create!(
    name: tag_data[:name],
    color: tag_data[:color],
    usage_count: 0
  )
  tags[tag_data[:name]] = tag
  puts "  ✓ Created tag: #{tag.name}"
end

# Create comprehensive articles
articles_data = [
  {
    category: 'account-setup',
    title: 'Creating Your First Account',
    content: <<~CONTENT,
      # Creating Your First Account

      Welcome to Powernode! This guide will walk you through creating your account and getting started.

      ## Step 1: Sign Up

      1. Visit the registration page
      2. Enter your email address
      3. Create a secure password (minimum 12 characters)
      4. Verify your email address

      ## Step 2: Account Verification

      After signing up, you'll receive an email verification link. Click the link to activate your account.

      ## Step 3: Choose Your Plan

      Select the plan that best fits your needs:
      - **Free**: Perfect for getting started
      - **Pro**: Advanced features for growing teams
      - **Enterprise**: Full-featured solution for large organizations

      ## Next Steps

      Once your account is set up, you can:
      - Invite team members
      - Configure your workspace
      - Explore our features

      Need help? Contact our support team at support@powernode.org
    CONTENT
    tags: ['Beginner', 'Tutorial'],
    is_featured: true,
    status: 'published'
  },
  {
    category: 'first-steps',
    title: 'Your First 30 Days with Powernode',
    content: <<~CONTENT,
      # Your First 30 Days with Powernode

      Maximize your success with this 30-day onboarding plan.

      ## Week 1: Foundation
      - Complete account setup
      - Invite your team
      - Explore the dashboard
      - Set up your first project

      ## Week 2: Integration
      - Connect your existing tools
      - Configure API access
      - Set up webhooks
      - Test your workflows

      ## Week 3: Optimization
      - Review analytics
      - Optimize your setup
      - Train your team
      - Document your processes

      ## Week 4: Scaling
      - Plan for growth
      - Configure advanced features
      - Set up monitoring
      - Prepare for production

      ## Success Metrics

      By the end of 30 days, you should have:
      - ✅ Completed team onboarding
      - ✅ Integrated key systems
      - ✅ Processed first transactions
      - ✅ Established monitoring

      ## Resources

      - [Team Training Materials](#)
      - [API Documentation](/kb/api-documentation)
      - [Best Practices Guide](#)
    CONTENT
    tags: ['Beginner', 'Tutorial', 'Best Practices'],
    is_featured: true,
    status: 'published'
  },
  {
    category: 'payment-methods',
    title: 'Managing Payment Methods',
    content: <<~CONTENT,
      # Managing Payment Methods

      Learn how to add, update, and manage your payment methods securely.

      ## Supported Payment Methods

      We support the following payment methods:
      - Credit/Debit Cards (Visa, Mastercard, American Express)
      - PayPal
      - Bank Transfer (Enterprise plans)
      - Digital Wallets (Apple Pay, Google Pay)

      ## Adding a Payment Method

      1. Go to **Account Settings** > **Billing**
      2. Click **Add Payment Method**
      3. Enter your payment information
      4. Verify the payment method

      ## Security Features

      Your payment information is protected by:
      - PCI DSS compliance
      - End-to-end encryption
      - Secure tokenization
      - Fraud detection

      ## Troubleshooting Payment Issues

      If you're experiencing payment issues:
      1. Check your card expiration date
      2. Verify your billing address
      3. Ensure sufficient funds
      4. Contact your bank if needed

      ## Automatic Billing

      - Payments are processed automatically on your billing date
      - You'll receive email notifications before each charge
      - Failed payments trigger retry attempts
      - Account suspension occurs after multiple failures

      Need assistance? Our billing support team is available 24/7.
    CONTENT
    tags: ['Billing', 'Security', 'Troubleshooting'],
    status: 'published'
  },
  {
    category: 'plan-upgrades',
    title: 'Upgrading Your Subscription Plan',
    content: <<~CONTENT,
      # Upgrading Your Subscription Plan

      Scale your account by upgrading to a higher-tier plan.

      ## When to Upgrade

      Consider upgrading when you:
      - Reach usage limits on your current plan
      - Need advanced features
      - Want priority support
      - Require additional team seats

      ## Upgrade Process

      1. Navigate to **Billing Settings**
      2. Click **Change Plan**
      3. Select your new plan
      4. Review pricing and features
      5. Confirm the upgrade

      ## Proration and Billing

      - Upgrades are prorated immediately
      - You'll be charged the difference today
      - Next billing cycle reflects the new plan price
      - Downgrades take effect at next billing cycle

      ## Plan Comparison

      | Feature | Free | Pro | Enterprise |
      |---------|------|-----|------------|
      | API Calls | 1,000/mo | 50,000/mo | Unlimited |
      | Team Members | 3 | 25 | Unlimited |
      | Support | Email | Priority | Dedicated |
      | SLA | - | 99.5% | 99.9% |

      ## Enterprise Features

      Enterprise plans include:
      - Custom integrations
      - Dedicated account manager
      - On-premise deployment options
      - Advanced security features
      - Custom reporting

      Questions about upgrading? Contact our sales team.
    CONTENT
    tags: ['Billing', 'Advanced'],
    status: 'published'
  },
  {
    category: 'authentication',
    title: 'API Authentication Guide',
    content: <<~CONTENT,
      # API Authentication Guide

      Secure your API integrations with proper authentication.

      ## Authentication Methods

      We support multiple authentication methods:

      ### 1. JWT Tokens (Recommended)
      ```bash
      curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \\
           https://api.powernode.org/api/v1/users
      ```

      ### 2. API Keys
      ```bash
      curl -H "X-API-Key: YOUR_API_KEY" \\
           https://api.powernode.org/api/v1/users
      ```

      ## Getting Your Credentials

      1. Log in to your dashboard
      2. Go to **Settings** > **API Access**
      3. Generate new credentials
      4. Store them securely

      ## Token Lifecycle

      - **Access Tokens**: Valid for 15 minutes
      - **Refresh Tokens**: Valid for 7 days
      - **API Keys**: Valid until revoked

      ## Refreshing Tokens

      ```javascript
      const response = await fetch('/api/auth/refresh', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${refreshToken}`
        }
      });
      ```

      ## Security Best Practices

      - ✅ Store credentials in environment variables
      - ✅ Use HTTPS for all requests
      - ✅ Rotate API keys regularly
      - ✅ Monitor for unusual activity
      - ❌ Never commit credentials to code
      - ❌ Don't share credentials via email

      ## Rate Limiting

      API requests are limited by plan:
      - Free: 100 requests/hour
      - Pro: 1,000 requests/hour  
      - Enterprise: 10,000 requests/hour

      ## Error Handling

      ```json
      {
        "success": false,
        "error": "Authentication required",
        "code": "UNAUTHORIZED"
      }
      ```

      Common error codes:
      - `UNAUTHORIZED`: Invalid or missing credentials
      - `FORBIDDEN`: Insufficient permissions
      - `RATE_LIMITED`: Too many requests
    CONTENT
    tags: ['API', 'Security', 'Advanced'],
    is_featured: true,
    status: 'published'
  },
  {
    category: 'rest-api',
    title: 'REST API Overview',
    content: <<~CONTENT,
      # REST API Overview

      Comprehensive guide to our REST API endpoints.

      ## Base URL

      All API requests should be made to:
      ```
      https://api.powernode.org/api/v1/
      ```

      ## Request Format

      - Use JSON for request bodies
      - Set `Content-Type: application/json`
      - Include authentication headers

      ## Standard Response Format

      ```json
      {
        "success": true,
        "data": {
          "id": "uuid",
          "name": "Example Resource"
        },
        "meta": {
          "pagination": {
            "current_page": 1,
            "total_pages": 5,
            "total_count": 100
          }
        }
      }
      ```

      ## Core Endpoints

      ### Users
      - `GET /users` - List users
      - `POST /users` - Create user
      - `GET /users/{id}` - Get user
      - `PUT /users/{id}` - Update user
      - `DELETE /users/{id}` - Delete user

      ### Subscriptions
      - `GET /subscriptions` - List subscriptions
      - `POST /subscriptions` - Create subscription
      - `GET /subscriptions/{id}` - Get subscription
      - `PUT /subscriptions/{id}` - Update subscription

      ### Billing
      - `GET /invoices` - List invoices
      - `GET /invoices/{id}` - Get invoice
      - `POST /payments` - Process payment

      ## Pagination

      Large result sets are paginated:
      ```bash
      curl "https://api.powernode.org/api/v1/users?page=2&per_page=50"
      ```

      ## Filtering and Sorting

      ```bash
      # Filter by status
      curl "https://api.powernode.org/api/v1/users?status=active"

      # Sort by created date
      curl "https://api.powernode.org/api/v1/users?sort=created_at&order=desc"
      ```

      ## Webhooks

      Subscribe to real-time events:
      - `subscription.created`
      - `payment.succeeded`
      - `user.updated`

      Configure webhooks in your dashboard under **Settings** > **Webhooks**.

      ## SDKs and Libraries

      Official SDKs available for:
      - JavaScript/Node.js
      - Python
      - Ruby
      - PHP
      - Go

      ## Support

      API support is available:
      - Documentation: [https://docs.powernode.org](https://docs.powernode.org)
      - Email: api-support@powernode.org
      - Discord: [Join our community](https://discord.gg/powernode)
    CONTENT
    tags: ['API', 'Integration', 'Advanced'],
    is_featured: true,
    status: 'published'
  },
  {
    category: 'troubleshooting',
    title: 'Common Integration Issues',
    content: <<~CONTENT,
      # Common Integration Issues

      Solutions to frequently encountered integration problems.

      ## Connection Timeouts

      **Symptoms**: API requests fail with timeout errors

      **Solutions**:
      1. Increase timeout values in your client
      2. Implement retry logic with exponential backoff
      3. Check your network connectivity
      4. Verify firewall settings

      ```javascript
      const client = axios.create({
        timeout: 30000, // 30 seconds
        retry: 3,
        retryDelay: 1000
      });
      ```

      ## Authentication Failures

      **Symptoms**: 401 Unauthorized responses

      **Common Causes**:
      - Expired tokens
      - Invalid API keys
      - Incorrect header format

      **Solutions**:
      ```bash
      # Correct format
      curl -H "Authorization: Bearer YOUR_TOKEN" \\
           -H "Content-Type: application/json" \\
           https://api.powernode.org/api/v1/users
      ```

      ## Rate Limiting

      **Symptoms**: 429 Too Many Requests

      **Solutions**:
      - Implement request throttling
      - Use exponential backoff
      - Monitor rate limit headers
      - Consider upgrading your plan

      ```javascript
      if (response.status === 429) {
        const retryAfter = response.headers['retry-after'];
        setTimeout(() => retryRequest(), retryAfter * 1000);
      }
      ```

      ## Webhook Delivery Issues

      **Symptoms**: Missing webhook notifications

      **Troubleshooting**:
      1. Check webhook endpoint URL
      2. Verify SSL certificate
      3. Ensure 200 response code
      4. Check webhook logs in dashboard

      **Webhook Verification**:
      ```javascript
      const crypto = require('crypto');

      function verifyWebhook(payload, signature, secret) {
        const expectedSignature = crypto
          .createHmac('sha256', secret)
          .update(payload)
          .digest('hex');
        
        return signature === expectedSignature;
      }
      ```

      ## Data Synchronization Issues

      **Symptoms**: Inconsistent data between systems

      **Solutions**:
      - Implement idempotency keys
      - Use pagination for large datasets
      - Handle race conditions properly
      - Implement conflict resolution

      ## Performance Optimization

      **Slow API Responses**:
      - Use appropriate filters
      - Implement caching
      - Request only needed fields
      - Use batch operations when available

      ```bash
      # Request specific fields only
      curl "https://api.powernode.org/api/v1/users?fields=id,name,email"

      # Use filters to reduce data
      curl "https://api.powernode.org/api/v1/users?created_after=2024-01-01"
      ```

      ## Getting Help

      If these solutions don't resolve your issue:
      1. Check our status page: [status.powernode.org](https://status.powernode.org)
      2. Search the knowledge base
      3. Contact support with:
          - Request/response headers
          - Error messages
          - Timestamp of the issue
          - Your account ID

      ## Emergency Contact

      For critical production issues:
      - Email: emergency@powernode.org
      - Phone: +1 (555) 123-POWER
      - Response time: < 15 minutes
    CONTENT
    tags: ['Troubleshooting', 'API', 'Integration', 'Advanced'],
    status: 'published'
  }
]

puts "\nCreating articles..."
created_articles = []

articles_data.each do |article_data|
  category = categories[article_data[:category]]
  next unless category

  article = KnowledgeBaseArticle.create!(
    title: article_data[:title],
    content: article_data[:content],
    category: category,
    author: admin_user,
    status: article_data[:status] || 'published',
    is_public: true,
    is_featured: article_data[:is_featured] || false,
    published_at: Time.current
  )

  # Add tags
  if article_data[:tags]
    article_tags = article_data[:tags].map { |tag_name| tags[tag_name] }.compact
    article.tags = article_tags
    article_tags.each(&:increment_usage!)
  end

  created_articles << article
  puts "  ✓ Created article: #{article.title}"
end

# Create some article views for realistic data
puts "\nSimulating article views..."
created_articles.each do |article|
  # Create random views (between 10-100)
  view_count = rand(10..100)
  view_count.times do |i|
    article.article_views.create!(
      session_id: SecureRandom.hex(16),
      ip_address: "192.168.1.#{rand(1..254)}",
      user_agent: "Mozilla/5.0 (compatible; TestBot/1.0)",
      created_at: rand(30.days.ago..Time.current)
    )
  end
  article.update!(views_count: view_count)
end

puts "\nKnowledge Base content seeding completed!"
puts "\nContent Summary:"
puts "  • Categories: #{KnowledgeBaseCategory.count} (#{KnowledgeBaseCategory.root_categories.count} root, #{KnowledgeBaseCategory.count - KnowledgeBaseCategory.root_categories.count} subcategories)"
puts "  • Articles: #{KnowledgeBaseArticle.count} (#{KnowledgeBaseArticle.published.count} published)"
puts "  • Tags: #{KnowledgeBaseTag.count}"
puts "  • Article Views: #{KnowledgeBaseArticleView.count}"
puts "  • Featured Articles: #{KnowledgeBaseArticle.featured.count}"

puts "\nSample articles created:"
created_articles.each do |article|
  puts "  • #{article.title} (#{article.category.name})"
end