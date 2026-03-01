# frozen_string_literal: true

# API & Integrations Articles
# Documentation for API and integration features

puts "  🔌 Creating API & Integrations articles..."

api_cat = KnowledgeBase::Category.find_by!(slug: "api-integrations")
author = User.find_by!(email: "admin@powernode.org")

# Article 37: API Integration Fundamentals (Featured)
api_fundamentals_content = <<~MARKDOWN
# API Integration Fundamentals

Build powerful integrations with Powernode's comprehensive REST API.

## API Overview

### Base Information

```yaml
API Details:
  Base URL: https://api.powernode.org/api/v1
  Format: JSON
  Authentication: JWT / API Key
  Rate Limit: 1000 requests/hour
```

### Available Resources

| Resource | Description |
|----------|-------------|
| `/auth` | Authentication |
| `/users` | User management |
| `/subscriptions` | Subscription CRUD |
| `/customers` | Customer management |
| `/invoices` | Invoice access |
| `/plans` | Plan management |
| `/analytics` | Metrics and reports |

## Authentication

### JWT Token Authentication

```bash
# Login to get token
POST /api/v1/auth/login
{
  "email": "user@example.com",
  "password": "your-password"
}

# Response
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in": 3600
}
```

### API Key Authentication

```bash
# Use API key in header
curl https://api.powernode.org/api/v1/subscriptions \\
  -H "Authorization: Bearer YOUR_API_KEY"
```

### Creating API Keys

1. Navigate to **Settings > API Keys**
2. Click **Generate Key**
3. Select permissions
4. Copy and store securely

## Common Operations

### List Resources

```bash
GET /api/v1/subscriptions
GET /api/v1/subscriptions?status=active&page=1&per_page=25
```

### Get Single Resource

```bash
GET /api/v1/subscriptions/{id}
```

### Create Resource

```bash
POST /api/v1/subscriptions
Content-Type: application/json

{
  "customer_id": "cust_123",
  "plan_id": "plan_456",
  "trial_days": 14
}
```

### Update Resource

```bash
PUT /api/v1/subscriptions/{id}
Content-Type: application/json

{
  "plan_id": "plan_789"
}
```

### Delete Resource

```bash
DELETE /api/v1/subscriptions/{id}
```

## Response Format

### Success Response

```json
{
  "success": true,
  "data": {
    "id": "sub_123",
    "customer_id": "cust_456",
    "plan_id": "plan_789",
    "status": "active"
  }
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "validation_error",
    "message": "Invalid email format",
    "details": {
      "field": "email"
    }
  }
}
```

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 422 | Validation Error |
| 429 | Rate Limited |
| 500 | Server Error |

## Pagination

### Request Parameters

```bash
GET /api/v1/subscriptions?page=2&per_page=50
```

### Response Metadata

```json
{
  "data": [...],
  "meta": {
    "current_page": 2,
    "per_page": 50,
    "total_pages": 10,
    "total_count": 487
  }
}
```

## Rate Limiting

### Headers

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 950
X-RateLimit-Reset: 1642687200
```

### Handling Rate Limits

```javascript
if (response.status === 429) {
  const retryAfter = response.headers.get('Retry-After');
  await sleep(retryAfter * 1000);
  return retry(request);
}
```

## SDK Availability

### Official SDKs

| Language | Package |
|----------|---------|
| JavaScript | `@powernode/sdk` |
| Python | `powernode-python` |
| Ruby | `powernode-ruby` |
| PHP | `powernode/powernode-php` |

### JavaScript Example

```javascript
import { Powernode } from '@powernode/sdk';

const client = new Powernode('your-api-key');

// List subscriptions
const subscriptions = await client.subscriptions.list({
  status: 'active'
});

// Create subscription
const subscription = await client.subscriptions.create({
  customerId: 'cust_123',
  planId: 'plan_456'
});
```

---

For webhook configuration, see [Webhook Configuration Guide](/kb/webhook-configuration-guide).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "api-integration-fundamentals") do |article|
  article.title = "API Integration Fundamentals"
  article.category = api_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Build integrations with Powernode's REST API including authentication, CRUD operations, pagination, rate limiting, and SDK usage."
  article.content = api_fundamentals_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ API Integration Fundamentals"

# Article 38: Webhook Configuration Guide
webhook_guide_content = <<~MARKDOWN
# Webhook Configuration Guide

Receive real-time notifications when events occur in your Powernode account.

## What Are Webhooks?

Webhooks deliver HTTP notifications to your server when events happen:

```
Event Occurs → Powernode → Your Server
     ↓              ↓            ↓
  (Payment)    HTTP POST    Process Event
```

## Creating Webhooks

### Via Dashboard

1. Navigate to **Settings > Webhooks**
2. Click **Add Webhook**
3. Configure endpoint:

```yaml
Webhook Configuration:
  URL: https://your-server.com/webhooks/powernode
  Events:
    - subscription.created
    - subscription.cancelled
    - invoice.paid
    - payment.failed
  Secret: whsec_... (auto-generated)
```

4. Save and enable

### Via API

```bash
POST /api/v1/webhooks
{
  "url": "https://your-server.com/webhooks",
  "events": ["subscription.created", "payment.failed"],
  "secret": "optional-custom-secret"
}
```

## Available Events

### Subscription Events

| Event | Description |
|-------|-------------|
| `subscription.created` | New subscription |
| `subscription.updated` | Subscription changed |
| `subscription.cancelled` | Subscription cancelled |
| `subscription.renewed` | Subscription renewed |

### Payment Events

| Event | Description |
|-------|-------------|
| `payment.succeeded` | Payment successful |
| `payment.failed` | Payment failed |
| `invoice.created` | Invoice generated |
| `invoice.paid` | Invoice paid |

### Customer Events

| Event | Description |
|-------|-------------|
| `customer.created` | New customer |
| `customer.updated` | Customer updated |
| `customer.deleted` | Customer deleted |

## Payload Structure

### Event Format

```json
{
  "id": "evt_01HQ7EXAMPLE",
  "type": "subscription.created",
  "created_at": "2024-01-15T10:30:00Z",
  "data": {
    "id": "sub_01HQ7EXAMPLE",
    "customer_id": "cust_01HQ7EXAMPLE",
    "plan_id": "plan_starter",
    "status": "active"
  }
}
```

## Security

### Signature Verification

Verify webhook authenticity:

```javascript
const crypto = require('crypto');

function verifySignature(payload, signature, secret) {
  const expected = crypto
    .createHmac('sha256', secret)
    .update(payload)
    .digest('hex');

  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(`sha256=${expected}`)
  );
}
```

### Headers

```
X-Powernode-Signature: sha256=abc123...
X-Powernode-Timestamp: 1642687200
X-Powernode-Event-ID: evt_01HQ7EXAMPLE
```

## Handling Webhooks

### Best Practices

1. **Respond Quickly** - Return 200 within 30 seconds
2. **Process Async** - Queue for background processing
3. **Idempotency** - Handle duplicate events
4. **Logging** - Log all received events

### Example Handler

```javascript
app.post('/webhooks/powernode', (req, res) => {
  // Verify signature
  if (!verifySignature(req.body, req.headers['x-powernode-signature'])) {
    return res.status(401).send('Invalid signature');
  }

  // Acknowledge receipt immediately
  res.status(200).send('Received');

  // Process asynchronously
  processWebhookAsync(req.body);
});
```

## Retry Logic

### Automatic Retries

Failed deliveries are retried:

```yaml
Retry Schedule:
  - Immediate
  - 1 minute
  - 5 minutes
  - 30 minutes
  - 2 hours
  - 24 hours
```

### Success Criteria

- HTTP 2xx response
- Response within 30 seconds

## Testing Webhooks

### Test Mode

Send test events:
1. Go to webhook settings
2. Click **Send Test**
3. Select event type
4. Review delivery

### Local Development

Use tunneling for local testing:
```bash
# Using ngrok
ngrok http 3000

# Use ngrok URL as webhook endpoint
# https://abc123.ngrok.io/webhooks/powernode
```

---

For API basics, see [API Integration Fundamentals](/kb/api-integration-fundamentals).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "webhook-configuration-guide") do |article|
  article.title = "Webhook Configuration Guide"
  article.category = api_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Configure webhooks for real-time event notifications with signature verification, retry logic, and best practices."
  article.content = webhook_guide_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Webhook Configuration Guide"

puts "  ✅ API & Integrations articles created (2 articles)"
