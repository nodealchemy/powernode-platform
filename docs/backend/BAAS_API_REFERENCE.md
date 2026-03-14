# BaaS API Reference

**Billing-as-a-Service API for multi-tenant billing**

---

## Table of Contents

1. [Overview](#overview)
2. [Authentication](#authentication)
3. [Tenants API](#tenants-api)
4. [Customers API](#customers-api)
5. [Subscriptions API](#subscriptions-api)
6. [Invoices API](#invoices-api)
7. [Usage API](#usage-api)
8. [Error Handling](#error-handling)

---

## Overview

The BaaS API enables SaaS platforms to embed billing functionality. It provides multi-tenant subscription management, invoicing, and usage-based billing.

### Base URL

```
/api/v1/baas
```

### Features

- Multi-tenant isolation
- Customer management
- Subscription lifecycle
- Invoice generation and management
- Usage-based metering
- Webhook notifications

---

## Authentication

All BaaS API requests require API key authentication.

### Headers

```http
Authorization: Bearer <api_key>
X-Tenant-ID: <tenant_id>  # Optional, derived from API key
```

### Scopes

API keys can be scoped to specific resources:

| Scope | Access |
|-------|--------|
| `customers` | Customer CRUD operations |
| `subscriptions` | Subscription management |
| `invoices` | Invoice operations |
| `usage` | Usage metering |

---

## Tenants API

### Get Current Tenant

```http
GET /api/v1/baas/tenant
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "tenant_abc123",
    "name": "Acme Corp",
    "slug": "acme",
    "tier": "growth",
    "environment": "production",
    "default_currency": "USD",
    "timezone": "America/New_York"
  }
}
```

### Update Tenant

```http
PATCH /api/v1/baas/tenant
```

**Request Body:**
```json
{
  "name": "Acme Corporation",
  "webhook_url": "https://api.acme.com/webhooks/billing",
  "webhook_secret": "whsec_...",
  "default_currency": "USD",
  "timezone": "America/New_York",
  "branding": {
    "logo_url": "https://...",
    "primary_color": "#1a73e8"
  },
  "metadata": {
    "external_id": "acme_123"
  }
}
```

### Get Dashboard Stats

```http
GET /api/v1/baas/tenant/dashboard
```

**Response:**
```json
{
  "success": true,
  "data": {
    "total_customers": 150,
    "active_subscriptions": 142,
    "mrr": 15000.00,
    "arr": 180000.00,
    "churn_rate": 2.5,
    "growth_rate": 8.3
  }
}
```

### Get Rate Limits

```http
GET /api/v1/baas/tenant/limits
```

**Response:**
```json
{
  "success": true,
  "data": {
    "api_calls": { "used": 5000, "limit": 10000, "reset_at": "2025-02-01T00:00:00Z" },
    "customers": { "used": 150, "limit": 1000 },
    "subscriptions": { "used": 142, "limit": 1000 }
  }
}
```

### Get Billing Configuration

```http
GET /api/v1/baas/tenant/billing_configuration
```

**Response:**
```json
{
  "success": true,
  "data": {
    "invoice_prefix": "INV",
    "invoice_due_days": 30,
    "auto_invoice": true,
    "auto_charge": true,
    "tax_enabled": true,
    "tax_provider": "stripe_tax",
    "dunning_enabled": true,
    "dunning_attempts": 3,
    "dunning_interval_days": 7,
    "usage_billing_enabled": true,
    "trial_enabled": true,
    "default_trial_days": 14
  }
}
```

### Update Billing Configuration

```http
PATCH /api/v1/baas/tenant/billing_configuration
```

---

## Customers API

### List Customers

```http
GET /api/v1/baas/customers
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | Filter by status |
| `email` | string | Filter by email |
| `page` | integer | Page number |
| `per_page` | integer | Items per page (max: 100) |

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "cus_abc123",
      "external_id": "user_456",
      "email": "john@example.com",
      "name": "John Doe",
      "status": "active",
      "currency": "USD",
      "created_at": "2025-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "total_pages": 5,
      "total_count": 150,
      "per_page": 30
    }
  }
}
```

### Get Customer

```http
GET /api/v1/baas/customers/:id
```

### Create Customer

```http
POST /api/v1/baas/customers
```

**Request Body:**
```json
{
  "external_id": "user_456",
  "email": "john@example.com",
  "name": "John Doe",
  "address_line1": "123 Main St",
  "address_line2": "Suite 100",
  "city": "San Francisco",
  "state": "CA",
  "postal_code": "94102",
  "country": "US",
  "tax_id": "XX-XXXXXXX",
  "tax_id_type": "us_ein",
  "tax_exempt": false,
  "currency": "USD",
  "metadata": {
    "plan_type": "business"
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "cus_abc123",
    "external_id": "user_456",
    "email": "john@example.com",
    "name": "John Doe",
    "status": "active",
    "created_at": "2025-01-30T10:30:00Z"
  }
}
```

### Update Customer

```http
PATCH /api/v1/baas/customers/:id
```

### Delete Customer

```http
DELETE /api/v1/baas/customers/:id
```

**Note:** Cannot delete customers with active subscriptions. Archives the customer instead.

---

## Subscriptions API

### List Subscriptions

```http
GET /api/v1/baas/subscriptions
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | active, canceled, paused, past_due |
| `customer_id` | string | Filter by customer |
| `page` | integer | Page number |
| `per_page` | integer | Items per page |

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "sub_abc123",
      "customer_id": "cus_xyz789",
      "plan_id": "plan_growth",
      "status": "active",
      "billing_interval": "month",
      "unit_amount": 9900,
      "currency": "USD",
      "quantity": 5,
      "current_period_start": "2025-01-01T00:00:00Z",
      "current_period_end": "2025-02-01T00:00:00Z",
      "created_at": "2025-01-01T10:30:00Z"
    }
  ],
  "meta": {
    "pagination": { ... }
  }
}
```

### Get Subscription

```http
GET /api/v1/baas/subscriptions/:id
```

### Create Subscription

```http
POST /api/v1/baas/subscriptions
```

**Request Body:**
```json
{
  "customer_id": "cus_xyz789",
  "external_id": "sub_external_123",
  "plan_id": "plan_growth",
  "billing_interval": "month",
  "billing_interval_count": 1,
  "unit_amount": 9900,
  "currency": "USD",
  "quantity": 5,
  "trial_days": 14,
  "metadata": {
    "source": "api"
  }
}
```

### Update Subscription

```http
PATCH /api/v1/baas/subscriptions/:id
```

### Cancel Subscription

```http
POST /api/v1/baas/subscriptions/:id/cancel
```

**Request Body:**
```json
{
  "reason": "Customer requested",
  "at_period_end": true
}
```

### Pause Subscription

```http
POST /api/v1/baas/subscriptions/:id/pause
```

### Resume Subscription

```http
POST /api/v1/baas/subscriptions/:id/resume
```

---

## Invoices API

### List Invoices

```http
GET /api/v1/baas/invoices
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | draft, open, paid, void, uncollectible |
| `customer_id` | string | Filter by customer |
| `page` | integer | Page number |
| `per_page` | integer | Items per page |

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "inv_abc123",
      "number": "INV-2025-0042",
      "customer_id": "cus_xyz789",
      "subscription_id": "sub_abc123",
      "status": "open",
      "currency": "USD",
      "subtotal": 9900,
      "tax": 990,
      "total": 10890,
      "amount_due": 10890,
      "amount_paid": 0,
      "due_date": "2025-02-15",
      "period_start": "2025-01-01",
      "period_end": "2025-02-01",
      "created_at": "2025-01-01T10:30:00Z"
    }
  ],
  "meta": {
    "pagination": { ... }
  }
}
```

### Get Invoice

```http
GET /api/v1/baas/invoices/:id
```

### Create Invoice

```http
POST /api/v1/baas/invoices
```

**Request Body:**
```json
{
  "customer_id": "cus_xyz789",
  "subscription_id": "sub_abc123",
  "external_id": "inv_external_123",
  "currency": "USD",
  "due_date": "2025-02-15",
  "period_start": "2025-01-01",
  "period_end": "2025-02-01",
  "line_items": [
    {
      "description": "Growth Plan - 5 seats",
      "amount_cents": 9900,
      "quantity": 1,
      "metadata": {}
    }
  ],
  "metadata": {}
}
```

### Update Invoice

```http
PATCH /api/v1/baas/invoices/:id
```

**Note:** Only draft invoices can be updated.

### Delete Invoice

```http
DELETE /api/v1/baas/invoices/:id
```

**Note:** Only draft invoices can be deleted.

### Finalize Invoice

```http
POST /api/v1/baas/invoices/:id/finalize
```

Transitions invoice from draft to open and assigns an invoice number.

### Pay Invoice

```http
POST /api/v1/baas/invoices/:id/pay
```

**Request Body:**
```json
{
  "payment_reference": "pi_abc123"
}
```

### Void Invoice

```http
POST /api/v1/baas/invoices/:id/void
```

**Request Body:**
```json
{
  "reason": "Customer requested credit"
}
```

### Add Line Item

```http
POST /api/v1/baas/invoices/:id/line_items
```

**Request Body:**
```json
{
  "description": "Additional API calls",
  "amount_cents": 500,
  "quantity": 1,
  "metadata": {}
}
```

### Remove Line Item

```http
DELETE /api/v1/baas/invoices/:id/line_items/:item_id
```

---

## Usage API

### Record Usage Event

```http
POST /api/v1/baas/usage_events
```

**Request Body:**
```json
{
  "customer_id": "cus_xyz789",
  "subscription_id": "sub_abc123",
  "meter_id": "api_calls",
  "idempotency_key": "evt_abc123",
  "quantity": 100,
  "timestamp": "2025-01-30T10:30:00Z",
  "billing_period_start": "2025-01-01",
  "billing_period_end": "2025-02-01",
  "properties": {
    "endpoint": "/api/users",
    "method": "GET"
  },
  "metadata": {}
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "ue_abc123",
    "customer_id": "cus_xyz789",
    "meter_id": "api_calls",
    "quantity": 100,
    "status": "pending",
    "created_at": "2025-01-30T10:30:00Z"
  }
}
```

### Batch Record Usage

```http
POST /api/v1/baas/usage_events/batch
```

**Request Body:**
```json
{
  "events": [
    {
      "customer_id": "cus_xyz789",
      "meter_id": "api_calls",
      "idempotency_key": "evt_001",
      "quantity": 50
    },
    {
      "customer_id": "cus_xyz789",
      "meter_id": "storage",
      "idempotency_key": "evt_002",
      "quantity": 1024
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "successful": 2,
    "failed": 0,
    "errors": []
  }
}
```

**Note:** Maximum 1000 events per batch.

### List Usage Records

```http
GET /api/v1/baas/usage
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `customer_id` | string | Filter by customer |
| `meter_id` | string | Filter by meter |
| `status` | string | pending, processed, billed |
| `start_date` | datetime | Start date (ISO8601) |
| `end_date` | datetime | End date (ISO8601) |
| `page` | integer | Page number |
| `per_page` | integer | Items per page |

### Get Usage Summary

```http
GET /api/v1/baas/usage/summary
```

**Required Parameters:**
- `customer_id`: Customer ID

**Optional Parameters:**
- `start_date`: Period start
- `end_date`: Period end

**Response:**
```json
{
  "success": true,
  "data": {
    "customer_id": "cus_xyz789",
    "period": {
      "start": "2025-01-01",
      "end": "2025-01-31"
    },
    "meters": [
      {
        "meter_id": "api_calls",
        "total_quantity": 15000,
        "billable_amount": 1500
      },
      {
        "meter_id": "storage",
        "total_quantity": 102400,
        "billable_amount": 5120
      }
    ],
    "total_billable": 6620
  }
}
```

### Get Aggregated Usage

```http
GET /api/v1/baas/usage/aggregate
```

**Required Parameters:**
- `customer_id`: Customer ID
- `meter_id`: Meter ID

**Optional Parameters:**
- `start_date`: Period start
- `end_date`: Period end

### Get Usage Analytics

```http
GET /api/v1/baas/usage/analytics
```

**Optional Parameters:**
- `start_date`: Period start (default: 30 days ago)
- `end_date`: Period end (default: today)

**Response:**
```json
{
  "success": true,
  "data": {
    "period": {
      "start": "2025-01-01",
      "end": "2025-01-30"
    },
    "total_events": 50000,
    "total_customers": 150,
    "meters": [
      {
        "meter_id": "api_calls",
        "total_quantity": 1500000,
        "unique_customers": 145,
        "daily_average": 50000
      }
    ],
    "trends": {
      "daily": [ ... ],
      "weekly": [ ... ]
    }
  }
}
```

---

## Error Handling

### Error Response Format

```json
{
  "success": false,
  "error": "Error message description"
}
```

Or with multiple errors:

```json
{
  "success": false,
  "errors": [
    "Field1 is required",
    "Field2 must be a valid email"
  ]
}
```

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (successful delete) |
| 207 | Multi-Status (batch with partial failures) |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden (insufficient scope) |
| 404 | Not Found |
| 422 | Unprocessable Entity |
| 429 | Rate Limited |
| 500 | Internal Server Error |

### Common Errors

| Error | Description |
|-------|-------------|
| `Unauthorized` | Invalid or missing API key |
| `Forbidden` | API key lacks required scope |
| `Customer not found` | Invalid customer ID |
| `Subscription not found` | Invalid subscription ID |
| `Invoice not found` | Invalid invoice ID |
| `Cannot delete customer with active subscriptions` | Customer has active subs |
| `Cannot update non-draft invoice` | Invoice already finalized |
| `Maximum 1000 events per batch` | Batch too large |

---

## Rate Limits

| Tier | Requests/Minute | Burst |
|------|-----------------|-------|
| Starter | 100 | 20 |
| Growth | 1000 | 100 |
| Business | 10000 | 1000 |

Rate limit headers:
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 950
X-RateLimit-Reset: 1706619600
```

---

## Webhooks

BaaS sends webhooks for billing events:

| Event | Description |
|-------|-------------|
| `customer.created` | New customer created |
| `customer.updated` | Customer updated |
| `subscription.created` | New subscription |
| `subscription.updated` | Subscription changed |
| `subscription.canceled` | Subscription canceled |
| `invoice.created` | Invoice generated |
| `invoice.finalized` | Invoice ready for payment |
| `invoice.paid` | Invoice payment received |
| `invoice.past_due` | Invoice past due date |
| `usage.threshold_reached` | Usage limit warning |

### Webhook Payload

```json
{
  "id": "evt_abc123",
  "type": "subscription.created",
  "created_at": "2025-01-30T10:30:00Z",
  "data": {
    "object": { ... }
  }
}
```

### Webhook Verification

Verify webhooks using the signature header:

```http
X-Webhook-Signature: sha256=abc123...
```

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `server/app/controllers/api/v1/baas/`
