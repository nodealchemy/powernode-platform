# Powernode Platform API Communications - Comprehensive Analysis

## Overview

This document provides a complete mapping of all API communications between the three main services in the Powernode platform:

- **Backend** (Rails 8 API - `server/`)
- **Frontend** (React TypeScript - `frontend/`)
- **Worker** (Sidekiq Service - `worker/`)

**Total Endpoints Discovered:** ~350+ endpoints across all services

---

## Communication Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND (React)                         │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  API Services   │    │  WebSocket Hooks │                    │
│  │  (96 files)     │    │  (17 channels)   │                    │
│  └────────┬────────┘    └────────┬────────┘                    │
└───────────┼─────────────────────┼──────────────────────────────┘
            │ HTTP REST           │ WebSocket
            │ (Bearer JWT)        │ (ActionCable)
            ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                       BACKEND (Rails API)                       │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐│
│  │  API Controllers │    │  WebSocket      │    │  Internal    ││
│  │  (254 controllers)│   │  Channels       │    │  API         ││
│  └─────────────────┘    └─────────────────┘    └──────┬───────┘│
└──────────────────────────────────────────────────────┼─────────┘
                                                       │ HTTP REST
                                                       │ (Service Token)
                                                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                        WORKER (Sidekiq)                         │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  BackendApiClient│    │  Background Jobs│                    │
│  │  (47+ endpoints) │    │  (195 job files)│                    │
│  └─────────────────┘    └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

**Note:** There is NO direct Frontend ↔ Worker communication. All worker operations are triggered through the Backend API.

---

## 1. FRONTEND → BACKEND API COMMUNICATIONS

### 1.1 Authentication & Session Management

**Justification:** Core security layer - all user authentication flows, JWT token management, and session handling.

| Endpoint | Method | Purpose | Auth |
|----------|--------|---------|------|
| `/api/v1/auth/register` | POST | User registration with account creation | No |
| `/api/v1/auth/login` | POST | User login, returns JWT tokens | No |
| `/api/v1/auth/logout` | POST | Logout, blacklist tokens | Yes |
| `/api/v1/auth/refresh` | POST | Refresh access token using refresh token | No |
| `/api/v1/auth/me` | GET | Get current authenticated user + permissions | Yes |
| `/api/v1/auth/forgot-password` | POST | Initiate password reset flow | No |
| `/api/v1/auth/reset-password` | POST | Complete password reset with token | No |
| `/api/v1/auth/verify-email` | POST | Verify email with token | No |
| `/api/v1/auth/resend-verification` | POST | Resend email verification | Yes |
| `/api/v1/auth/verify-2fa` | POST | Verify 2FA code during login | No |

**Response Format:**
```json
{
  "success": true,
  "data": {
    "user": { "id": "uuid", "email": "...", "permissions": [...] },
    "access_token": "jwt...",
    "refresh_token": "jwt...",
    "expires_in": 900
  }
}
```

---

### 1.2 Two-Factor Authentication

**Justification:** Enhanced security for user accounts with TOTP-based 2FA.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/two_factor/status` | GET | Check 2FA enrollment status |
| `/api/v1/two_factor/enable` | POST | Generate 2FA secret and QR code |
| `/api/v1/two_factor/verify_setup` | POST | Verify 2FA setup with code |
| `/api/v1/two_factor/disable` | DELETE | Disable 2FA with verification |
| `/api/v1/two_factor/backup_codes` | GET | Retrieve backup codes |
| `/api/v1/two_factor/regenerate_backup_codes` | POST | Generate new backup codes |

---

### 1.3 Account & User Management

**Justification:** Multi-tenant account management with user lifecycle operations.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/accounts/current` | GET | Get current user's account |
| `/api/v1/accounts/current` | PUT | Update current account settings |
| `/api/v1/accounts/usage` | GET | Get account usage metrics |
| `/api/v1/users` | GET | List users in current account (paginated) |
| `/api/v1/users` | POST | Create new user in account |
| `/api/v1/users/{id}` | GET/PUT/DELETE | User CRUD operations |
| `/api/v1/users/{id}/suspend` | PUT | Suspend user account |
| `/api/v1/users/{id}/activate` | PUT | Activate suspended user |
| `/api/v1/users/{id}/reset_password` | POST | Admin password reset |
| `/api/v1/users/{id}/unlock` | PUT | Unlock locked account |
| `/api/v1/users/stats` | GET | User statistics |

---

### 1.4 Roles & Permissions

**Justification:** Permission-based access control system (NEVER role-based on frontend).

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/roles` | GET | List all roles |
| `/api/v1/roles` | POST | Create new role |
| `/api/v1/roles/{id}` | GET/PUT/DELETE | Role CRUD |
| `/api/v1/roles/{id}/users` | GET | Get users assigned to role |
| `/api/v1/roles/assignable` | GET | Get roles current user can assign |
| `/api/v1/permissions` | GET | Get all available permissions |
| `/api/v1/users/{id}/roles/{role_id}` | POST/DELETE | Assign/remove role |

---

### 1.5 Team Invitations & Delegations

**Justification:** Team collaboration features for inviting users and delegating account access.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/invitations` | GET | List pending invitations |
| `/api/v1/invitations` | POST | Send new invitation |
| `/api/v1/invitations/{id}/resend` | POST | Resend invitation email |
| `/api/v1/invitations/{id}` | DELETE | Cancel invitation |
| `/api/v1/invitations/{token}/accept` | POST | Accept invitation (public) |
| `/api/v1/accounts/current/delegations` | GET/POST | List/create delegations |
| `/api/v1/accounts/current/delegations/{id}` | GET/PATCH/DELETE | Delegation CRUD |
| `/api/v1/accounts/current/delegations/{id}/activate` | PATCH | Activate delegation |
| `/api/v1/accounts/current/delegations/{id}/revoke` | PATCH | Revoke delegation |

---

### 1.6 Billing & Subscriptions

**Justification:** Core monetization - subscription management, payment processing, and invoicing.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/billing` | GET | Billing overview dashboard |
| `/api/v1/billing/subscription` | GET | Subscription billing details |
| `/api/v1/billing/invoices` | GET | List invoices (paginated) |
| `/api/v1/billing/invoices` | POST | Create new invoice |
| `/api/v1/billing/payment-methods` | GET/POST | Payment method management |
| `/api/v1/billing/payment-methods/{id}` | DELETE | Remove payment method |
| `/api/v1/billing/payment-methods/{id}/default` | PUT | Set default payment method |
| `/api/v1/billing/payment-intent` | POST | Create payment intent |
| `/api/v1/billing/history` | GET | Billing history |
| `/api/v1/subscriptions` | GET/POST | List/create subscriptions |
| `/api/v1/subscriptions/{id}` | GET/PATCH/DELETE | Subscription CRUD |
| `/api/v1/plans` | GET | List available plans |
| `/api/v1/public/plans` | GET | Public plan list (no auth) |
| `/api/v1/plans/{id}` | GET | Plan details |

---

### 1.7 Payment Gateways

**Justification:** Multi-gateway payment integration (Stripe, PayPal) with PCI compliance.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/payment_gateways` | GET | List configured gateways |
| `/api/v1/payment_gateways/{gateway}` | GET/PUT | Gateway config CRUD |
| `/api/v1/payment_gateways/{gateway}/test_connection` | POST | Test gateway (async job) |
| `/api/v1/gateway_connection_jobs/{id}` | GET | Check test job status |
| `/api/v1/payment_gateways/{gateway}/webhook_events` | GET | Webhook event history |
| `/api/v1/payment_gateways/{gateway}/transactions` | GET | Transaction history |
| `/api/v1/payment_methods` | GET/POST/DELETE | Payment method CRUD |
| `/api/v1/payment_methods/setup_intent` | POST | Create Stripe setup intent |
| `/api/v1/payment_methods/{id}/set_default` | PUT | Set default method |

---

### 1.8 Webhooks Management

**Justification:** Allow accounts to receive event notifications via webhooks.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/webhooks` | GET | List webhook endpoints |
| `/api/v1/webhooks` | POST | Create webhook endpoint |
| `/api/v1/webhooks/{id}` | GET/PUT/DELETE | Webhook CRUD |
| `/api/v1/webhooks/{id}/test` | POST | Test webhook delivery |
| `/api/v1/webhooks/{id}/toggle_status` | POST | Enable/disable webhook |
| `/api/v1/webhooks/available_events` | GET | Get available event types |
| `/api/v1/webhooks/deliveries` | GET | Delivery history |
| `/api/v1/webhooks/stats` | GET | Webhook statistics |
| `/api/v1/webhooks/retry_failed` | POST | Retry failed deliveries |

---

### 1.9 API Keys Management

**Justification:** Programmatic API access for integrations.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/api_keys` | GET | List API keys |
| `/api/v1/api_keys` | POST | Create new API key |
| `/api/v1/api_keys/{id}` | GET/PUT/DELETE | API key CRUD |
| `/api/v1/api_keys/{id}/regenerate` | POST | Regenerate key |
| `/api/v1/api_keys/{id}/toggle_status` | POST | Enable/revoke key |
| `/api/v1/api_keys/usage` | GET | Usage statistics |
| `/api/v1/api_keys/scopes` | GET | Available scopes |
| `/api/v1/api_keys/validate` | POST | Validate key |

---

### 1.10 Audit Logs & Security

**Justification:** Compliance and security monitoring with comprehensive audit trail.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/audit_logs` | GET | Query audit logs (filtered) |
| `/api/v1/audit_logs/{id}` | GET | Specific audit log entry |
| `/api/v1/audit_logs/security_summary` | GET | Security analytics |
| `/api/v1/audit_logs/compliance_summary` | GET | Compliance metrics |
| `/api/v1/audit_logs/activity_timeline` | GET | Activity timeline |
| `/api/v1/audit_logs/risk_analysis` | GET | Risk assessment |
| `/api/v1/audit_logs/stats` | GET | Log statistics |
| `/api/v1/audit_logs/export` | POST | Export logs |
| `/api/v1/audit_logs/cleanup` | DELETE | Cleanup old logs |

---

### 1.11 Admin Settings & System Management

**Justification:** Platform administration and system configuration.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/admin_settings` | GET | Admin dashboard overview |
| `/api/v1/admin_settings` | PUT | Update system settings |
| `/api/v1/admin_settings/metrics` | GET | System metrics |
| `/api/v1/admin_settings/users` | GET | All users (admin) |
| `/api/v1/admin_settings/accounts` | GET | All accounts (admin) |
| `/api/v1/admin_settings/system_logs` | GET | System logs |
| `/api/v1/admin_settings/suspend_account` | POST | Suspend account |
| `/api/v1/admin_settings/activate_account` | POST | Activate account |
| `/api/v1/admin_settings/health` | GET | System health |
| `/api/v1/admin_settings/security` | GET/PUT | Security configuration |
| `/api/v1/admin_settings/security/regenerate_jwt_secret` | POST | Rotate JWT secret |

---

### 1.12 Rate Limiting (Admin)

**Justification:** API protection and abuse prevention.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/admin/rate_limiting/statistics` | GET | Rate limiting stats |
| `/api/v1/admin/rate_limiting/violations` | GET | Violation history |
| `/api/v1/admin/rate_limiting/status` | GET | Current status |
| `/api/v1/admin/rate_limiting/limits/{identifier}` | GET/DELETE | Per-user limits |
| `/api/v1/admin/rate_limiting/disable` | POST | Temporarily disable |
| `/api/v1/admin/rate_limiting/enable` | POST | Re-enable |

---

### 1.13 Impersonation

**Justification:** Admin support capability to debug user issues.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/impersonations` | POST | Start impersonation |
| `/api/v1/impersonations` | DELETE | Stop impersonation |
| `/api/v1/impersonations` | GET | Active sessions |
| `/api/v1/impersonations/history` | GET | Impersonation history |
| `/api/v1/impersonations/users` | GET | Impersonatable users |
| `/api/v1/impersonations/validate` | POST | Validate impersonation token |

---

### 1.14 Analytics & Reporting

**Justification:** Business intelligence and KPI tracking.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/analytics/live` | GET | Live analytics dashboard |
| `/api/v1/analytics/revenue` | GET | Revenue metrics |
| `/api/v1/analytics/growth` | GET | Growth analytics |
| `/api/v1/analytics/churn` | GET | Churn analysis |
| `/api/v1/analytics/cohorts` | GET | Cohort analysis |
| `/api/v1/analytics/customers` | GET | Customer analytics |
| `/api/v1/analytics/export` | GET/POST | Export analytics |
| `/api/v1/reports` | GET/POST | Report management |
| `/api/v1/reports/requests/{id}` | GET | Report request status |

---

### 1.15 Workers & Services Management

**Justification:** Monitor and manage background worker instances.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/workers` | GET | List all workers |
| `/api/v1/workers` | POST | Register new worker |
| `/api/v1/workers/{id}` | GET/PATCH/DELETE | Worker CRUD |
| `/api/v1/workers/{id}/regenerate_token` | POST | Rotate worker token |
| `/api/v1/workers/{id}/suspend` | POST | Suspend worker |
| `/api/v1/workers/{id}/activate` | POST | Activate worker |
| `/api/v1/workers/{id}/health_check` | POST | Health check |
| `/api/v1/workers/{id}/test_worker` | POST | Test worker |
| `/api/v1/workers/{id}/activities` | GET | Worker activity log |
| `/api/v1/workers/{id}/config` | GET/PUT | Worker configuration |
| `/api/v1/workers/stats` | GET | Worker statistics |
| `/api/v1/admin/services` | GET/POST/PATCH/DELETE | Service management |

---

### 1.16 Marketplace & Apps

**Justification:** App marketplace for extending platform functionality.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/apps` | GET/POST | List/create apps |
| `/api/v1/apps/{id}` | GET/PUT/DELETE | App CRUD |
| `/api/v1/apps/{id}/publish` | POST | Publish to marketplace |
| `/api/v1/apps/{id}/unpublish` | POST | Remove from marketplace |
| `/api/v1/apps/{id}/analytics` | GET | App analytics |
| `/api/v1/apps/{id}/app_plans` | GET/POST/PUT/DELETE | App pricing plans |
| `/api/v1/apps/{id}/app_features` | GET/POST/PUT/DELETE | App features |
| `/api/v1/apps/{id}/app_endpoints` | GET/POST/PUT/DELETE | App endpoints |
| `/api/v1/apps/{id}/app_webhooks` | GET/POST/PUT/DELETE | App webhooks |
| `/api/v1/marketplace_listings` | GET | Public marketplace |
| `/api/v1/app_subscriptions` | GET/POST/PATCH/DELETE | App subscriptions |
| `/api/v1/app_reviews` | GET/POST/PUT/DELETE | App reviews |

---

### 1.17 AI Orchestration System

**Justification:** Complete AI workflow automation with agents, providers, and monitoring.

#### Workflows
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/ai/workflows` | GET/POST | List/create workflows |
| `/api/v1/ai/workflows/{id}` | GET/PATCH/DELETE | Workflow CRUD |
| `/api/v1/ai/workflows/{id}/execute` | POST | Execute workflow |
| `/api/v1/ai/workflows/{id}/duplicate` | POST | Duplicate workflow |
| `/api/v1/ai/workflows/{id}/validate` | GET | Validate structure |
| `/api/v1/ai/workflows/{id}/export` | GET | Export workflow |
| `/api/v1/ai/workflows/import` | POST | Import workflow |
| `/api/v1/ai/workflows/templates` | GET | Workflow templates |
| `/api/v1/ai/workflows/{id}/runs` | GET | List workflow runs |
| `/api/v1/ai/workflows/{id}/runs/{run_id}` | GET/PATCH/DELETE | Run CRUD |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/cancel` | POST | Cancel run |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/retry` | POST | Retry run |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/pause` | POST | Pause run |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/resume` | POST | Resume run |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/logs` | GET | Run logs |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/node_executions` | GET | Node executions |

#### Agents
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/ai/agents` | GET/POST | List/create agents |
| `/api/v1/ai/agents/{id}` | GET/PATCH/DELETE | Agent CRUD |
| `/api/v1/ai/agents/{id}/execute` | POST | Execute agent |
| `/api/v1/ai/agents/{id}/clone` | POST | Clone agent |
| `/api/v1/ai/agents/{id}/test` | POST | Test agent |
| `/api/v1/ai/agents/{id}/pause` | POST | Pause agent |
| `/api/v1/ai/agents/{id}/resume` | POST | Resume agent |
| `/api/v1/ai/agents/{id}/stats` | GET | Agent statistics |
| `/api/v1/ai/agents/agent_types` | GET | Available types |

#### Providers
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/ai/providers` | GET/POST/PATCH/DELETE | Provider CRUD |
| `/api/v1/ai/providers/{id}/test_connection` | POST | Test connection |
| `/api/v1/ai/providers/{id}/sync_models` | POST | Sync models |
| `/api/v1/ai/providers/{id}/models` | GET | List models |
| `/api/v1/ai/providers/available` | GET | Available providers |
| `/api/v1/ai/providers/{id}/credentials` | GET/POST/PATCH/DELETE | Credential management |

#### Monitoring
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/ai/monitoring/dashboard` | GET | Monitoring dashboard |
| `/api/v1/ai/monitoring/health` | GET | Health status |
| `/api/v1/ai/monitoring/metrics` | GET | System metrics |
| `/api/v1/ai/monitoring/circuit_breakers` | GET/POST | Circuit breaker status |

---

### 1.18 Content Management

**Justification:** CMS for pages and knowledge base.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/pages` | GET | List public pages |
| `/api/v1/pages/{slug}` | GET | Get public page |
| `/api/v1/admin/pages` | GET/POST/PUT/DELETE | Admin page CRUD |
| `/api/v1/admin/pages/{id}/publish` | POST | Publish page |
| `/api/v1/admin/pages/{id}/duplicate` | POST | Duplicate page |
| `/api/v1/kb/articles` | GET/POST/PUT/DELETE | KB articles |
| `/api/v1/kb/categories` | GET/POST/PUT/DELETE | KB categories |
| `/api/v1/kb/comments` | GET/POST/PUT/DELETE | Article comments |

---

### 1.19 File Storage

**Justification:** Multi-provider file storage management.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/storage` | GET | List storage providers |
| `/api/v1/storage/{id}` | GET/PUT/DELETE | Provider CRUD |
| `/api/v1/storage` | POST | Create provider |
| `/api/v1/storage/{id}/test` | POST | Test connection |
| `/api/v1/storage/{id}/set_default` | POST | Set default |

---

### 1.20 WebSocket Channels

**Justification:** Real-time updates without polling.

| Channel | Purpose |
|---------|---------|
| `AiAgentExecutionChannel` | Agent execution status |
| `AiConversationChannel` | AI conversation streaming |
| `AiOrchestrationChannel` | Multi-agent orchestration events |
| `AiStreamingChannel` | AI response streaming |
| `AiWorkflowMonitoringChannel` | Workflow monitoring dashboard |
| `AiWorkflowOrchestrationChannel` | Workflow execution events |
| `AnalyticsChannel` | Live analytics updates |
| `CodeFactoryChannel` | Code factory execution status |
| `CustomerChannel` | Customer event notifications |
| `DevopsPipelineChannel` | CI/CD pipeline status |
| `GitJobLogsChannel` | Git operation log streaming |
| `McpChannel` | MCP tool execution events |
| `MissionChannel` | Mission pipeline status |
| `NotificationChannel` | Real-time notifications |
| `SubscriptionChannel` | Subscription lifecycle events |
| `TeamChannelChannel` | Team chat messaging |
| `TeamExecutionChannel` | Team task execution status |

**Connection:** `ws[s]://{host}:3000/cable?token={jwt}`

---

## 2. WORKER → BACKEND API COMMUNICATIONS

### 2.1 Authentication

**Mechanism:** Service-to-service bearer token authentication

```
Authorization: Bearer {WORKER_TOKEN}
```

**Configuration:**
- Token: `ENV['WORKER_TOKEN']`
- Base URL: `ENV['BACKEND_API_URL']` (default: `http://localhost:3000`)
- Timeout: 120 seconds
- Retry: 3 attempts with exponential backoff

---

### 2.2 Account & Subscription Operations

**Justification:** Worker needs account/subscription data for billing automation.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/accounts/{id}` | GET | `BillingAutomationJob`, `SubscriptionRenewalJob` | Get account details |
| `/api/v1/accounts/{id}/subscription` | GET | `BackendApiClient` | Get account subscription |
| `/api/v1/accounts/{id}/payment_methods` | GET | `BillingAutomationJob` | Get payment methods |
| `/api/v1/accounts` | GET | `MetricsAggregationJob` | List active accounts |
| `/api/v1/subscriptions` | GET | `BillingAutomationJob` | Query subscriptions for renewal |
| `/api/v1/subscriptions/{id}` | GET | `BillingAutomationJob` | Get subscription details |
| `/api/v1/subscriptions/{id}` | PATCH | `BillingAutomationJob` | Update subscription status |

---

### 2.3 Billing & Payment Processing

**Justification:** Automated billing operations - invoice generation and payment processing.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/billing/generate_invoice` | POST | `BillingAutomationJob` | Generate renewal/conversion invoice |
| `/api/v1/billing/process_payment` | POST | `BillingAutomationJob` | Process payment on invoice |
| `/api/v1/billing/process_renewal` | POST | `SubscriptionRenewalJob` | Process subscription renewal |
| `/api/v1/invoices` | GET/POST | `ApiClient` | Invoice operations (legacy) |
| `/api/v1/payments` | POST | `ApiClient` | Process payment (legacy) |

---

### 2.4 Payment Reconciliation

**Justification:** Financial integrity - reconcile local records with payment providers.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/reconciliation/stripe_payments` | GET | `PaymentReconciliationJob` | Get local Stripe payments |
| `/api/v1/reconciliation/paypal_payments` | GET | `PaymentReconciliationJob` | Get local PayPal payments |
| `/api/v1/reconciliation/report` | POST | `PaymentReconciliationJob` | Submit reconciliation report |
| `/api/v1/reconciliation/corrections` | POST | `PaymentReconciliationJob` | Create correction for missing |
| `/api/v1/reconciliation/flags` | POST | `PaymentReconciliationJob` | Flag discrepancies |
| `/api/v1/reconciliation/investigations` | POST | `PaymentReconciliationJob` | Flag amount mismatches |

---

### 2.5 Webhook Processing

**Justification:** Handle incoming payment provider webhooks asynchronously.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/webhooks/payment_succeeded` | POST | `ProcessWebhookJob` | Handle successful payment |
| `/api/v1/webhooks/payment_failed` | POST | `ProcessWebhookJob` | Handle failed payment |
| `/api/v1/webhooks/subscription_updated` | POST | `ProcessWebhookJob` | Handle subscription update |
| `/api/v1/webhooks/subscription_cancelled` | POST | `ProcessWebhookJob` | Handle cancellation |
| `/api/v1/webhooks/subscription_activated` | POST | `ProcessWebhookJob` | Handle activation |
| `/api/v1/webhooks/payment_method_attached` | POST | `ProcessWebhookJob` | Handle new payment method |
| `/api/v1/webhooks/payment_intent_succeeded` | POST | `ProcessWebhookJob` | Handle payment intent success |
| `/api/v1/webhooks/payment_intent_failed` | POST | `ProcessWebhookJob` | Handle payment intent failure |

---

### 2.6 Reports & Analytics

**Justification:** Async report generation with large data exports.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/reports/requests/{id}` | GET | `GenerateReportJob` | Get report request |
| `/api/v1/reports/requests/{id}` | PATCH | `GenerateReportJob` | Update status (processing/completed/failed) |
| `/api/v1/analytics/export` | GET | `GenerateReportJob` | Get analytics data for report |
| `/api/v1/analytics/update_revenue_snapshots` | POST | `MetricsAggregationJob` | Update revenue snapshots |
| `/api/v1/reports/scheduled` | GET | `ScheduledReportJob` | Get due scheduled reports |

---

### 2.7 AI Workflow Execution

**Justification:** Execute AI workflows asynchronously with real-time status updates.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/ai/workflows/runs/lookup/{run_id}` | GET | `AiWorkflowExecutionJob` | Look up workflow run |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/process` | POST | `AiWorkflowExecutionJob` | Execute workflow |
| `/api/v1/ai/workflows/{id}/runs/{run_id}` | PATCH | `AiWorkflowExecutionJob` | Update run status |
| `/api/v1/ai/workflows/{id}/runs/{run_id}/broadcast` | POST | `AiWorkflowExecutionJob` | Broadcast real-time status |

---

### 2.8 File Processing

**Justification:** Async file processing with status tracking.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/worker/processing_jobs/{id}` | GET | `FileProcessingWorker` | Get processing job details |
| `/api/v1/worker/processing_jobs/{id}` | PATCH | `FileProcessingWorker` | Update job status |
| `/api/v1/worker/files/{id}` | GET | `FileProcessingWorker` | Get file object |
| `/api/v1/worker/files/{id}` | PATCH | `FileProcessingWorker` | Update file metadata |
| `/api/v1/worker/files/{id}/download` | GET | `FileProcessingWorker` | Download file content |
| `/api/v1/worker/files/{id}/processed` | POST | `FileProcessingWorker` | Upload processed file |

---

### 2.9 Notifications & Audit

**Justification:** Log notifications and audit trail for compliance.

| Endpoint | Method | Job(s) Using | Purpose |
|----------|--------|--------------|---------|
| `/api/v1/notifications` | POST | `SendNotificationEmailJob`, Billing jobs | Log notification |
| `/api/v1/audit_logs` | POST | `TestEmailJob`, Notification jobs | Create audit entry |
| `/api/v1/alerts` | POST | `PaymentReconciliationJob` | Create system alert |

---

### 2.10 Internal APIs (Worker-Only)

**Justification:** Protected endpoints only accessible by authenticated workers.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/internal/users/{id}` | GET | Get user data for emails |
| `/api/v1/internal/accounts/{id}` | GET | Get account data for emails |
| `/api/v1/internal/invitations/{id}` | GET | Get invitation data for emails |
| `/api/v1/internal/workers/{id}/test_results` | POST | Report test completion |
| `/api/v1/internal/jobs/{id}` | GET/PATCH | Track background job status |
| `/api/v1/health` | GET | Backend health check |

---

### 2.11 Worker Resilience Patterns

**Circuit Breaker Configuration:**
```ruby
# Backend API Circuit Breaker
service_name: 'backend_api'
failure_threshold: 5
recovery_timeout: 60 seconds
request_timeout: 120 seconds

# AI Provider Circuit Breaker
service_name: 'ai_provider_{name}'
failure_threshold: 5
recovery_timeout: 120 seconds
request_timeout: 600 seconds (10 min)

# Workflow Execution Circuit Breaker
service_name: 'workflow_execution'
failure_threshold: 3
recovery_timeout: 30 seconds
request_timeout: 300 seconds (5 min)
```

**Retry Strategy:**
- API Client Level: 3 retries, exponential backoff (0.5s base, 2x multiplier)
- Job Level: 3 attempts, 2^attempt seconds sleep
- Sidekiq Level: 3 retries, exponential backoff with jitter
- Retryable status codes: 408, 429, 500, 502, 503, 504

---

## 3. FRONTEND ↔ WORKER COMMUNICATIONS

**There is NO direct Frontend ↔ Worker communication.**

All worker-related operations go through the Backend:

1. **Frontend → Backend:** Request triggers worker operation
2. **Backend:** Enqueues Sidekiq job
3. **Worker → Backend:** Executes job, reports status via API
4. **Backend → Frontend:** WebSocket broadcasts status updates

**Example Flow (Report Generation):**
```
Frontend                Backend                 Worker
   │                       │                       │
   ├──POST /reports────────►                       │
   │                       ├──Enqueue Job──────────►
   │                       │                       │
   │◄──{id, status}────────┤                       │
   │                       │                       │
   │  [WebSocket]          │◄──GET /reports/{id}───┤
   │                       │                       │
   │                       │◄──PATCH status────────┤
   │◄──[status update]─────┤                       │
   │                       │                       │
   │                       │◄──PATCH completed─────┤
   │◄──[completed]─────────┤                       │
```

---

## 4. EXTERNAL WEBHOOK ENDPOINTS

**Justification:** Receive events from external payment providers.

| Endpoint | Method | Source | Purpose |
|----------|--------|--------|---------|
| `/webhooks/stripe` | POST | Stripe | Stripe webhook events |
| `/webhooks/paypal` | POST | PayPal | PayPal webhook events |

**Processing Flow:**
1. Webhook received at endpoint
2. Signature verified
3. Event enqueued to Sidekiq
4. Worker processes event via `/api/v1/webhooks/*` endpoints

---

## 5. SUMMARY STATISTICS

| Category | Count |
|----------|-------|
| **Total Backend Controllers** | 254 |
| **Frontend API Services** | 96 files |
| **Frontend API Calls** | ~400+ unique endpoints |
| **Worker API Calls** | 47+ unique endpoints |
| **WebSocket Channels** | 17 |
| **Background Job Files** | 195 |
| **External Webhooks** | 2 (Stripe, PayPal) |

---

## 6. AUTHENTICATION SUMMARY

| Communication | Auth Method | Token Type |
|---------------|-------------|------------|
| Frontend → Backend | Bearer Token | JWT (15 min access, 7 day refresh) |
| Worker → Backend | Bearer Token | Service Token (long-lived) |
| External Webhooks | Signature | Provider-specific (Stripe sig, PayPal cert) |
| WebSocket | Query Param | JWT access token |

---

## 7. STANDARD RESPONSE FORMAT

All API endpoints follow this structure:

```json
{
  "success": boolean,
  "data": { /* endpoint-specific data */ },
  "error": "string (only on errors)",
  "message": "optional human-readable message",
  "pagination": {
    "current_page": number,
    "per_page": number,
    "total_count": number,
    "total_pages": number
  }
}
```

This comprehensive API mapping ensures complete visibility into all service communications for documentation, debugging, and system design purposes.
