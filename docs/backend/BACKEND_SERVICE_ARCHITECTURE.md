# Backend Service Architecture

**Comprehensive guide to the Rails service layer architecture**

---

## Table of Contents

1. [Overview](#overview)
2. [Service Domains](#service-domains)
3. [AI Services](#ai-services)
4. [MCP Services](#mcp-services)
5. [Billing Services](#billing-services)
6. [BaaS Services](#baas-services)
7. [DevOps Services](#devops-services)
8. [Infrastructure Services](#infrastructure-services)
9. [Service Patterns](#service-patterns)

---

## Overview

The Powernode backend uses a service-oriented architecture with services organized in `server/app/services/`. Services encapsulate business logic and are called from controllers, jobs, and other services.

### Directory Structure (634 service files across 22+ namespaces)

```
server/app/services/
├── ai/                    # AI orchestration, agents, providers (317 files)
├── mcp/                   # Model Context Protocol services (101 files)
├── devops/                # CI/CD and deployment services (38 files)
├── a2a/                   # Agent-to-Agent protocol (17 files)
├── chat/                  # Conversation management (10 files)
├── security/              # Auth, encryption, security (11 files)
├── orchestration/         # Workflow orchestration (8 files)
├── cost_optimization/     # Cost tracking and optimization (7 files)
├── storage_providers/     # Storage backend implementations (7 files)
├── concerns/              # Shared service concerns (7 files)
├── provider_testing/      # Provider health checks (6 files)
├── shared/                # Cross-cutting utilities (4 files)
├── billing/               # Payment and subscription services (2 files)
├── data_management/       # Data sanitization and management (2 files)
├── monitoring/            # Health monitoring (2 files)
├── permissions/           # Permission management (2 files)
├── rate_limiting/         # Request rate limiting (2 files)
├── audit/                 # Audit log services (2 files)
├── admin/                 # Admin panel services (2 files)
├── auth/                  # Authentication services (1 file)
├── accounts/              # Account management (1 file)
├── analytics/             # Analytics processing
├── baas/                  # Billing-as-a-Service API services
├── notifications/         # Notification delivery
└── services/              # Service management
```

---

## Service Domains

### Quick Reference

| Domain | Service Count | Primary Responsibility |
|--------|---------------|------------------------|
| AI | 317 | Agent execution, provider management, workflows, knowledge, memory |
| MCP | 101 | Node executors, orchestration, protocol handling |
| DevOps | 38 | CI/CD, Git, deployment, registry |
| A2A | 17 | Agent-to-Agent protocol |
| Security | 11 | Authentication, authorization, encryption |
| Chat | 10 | Conversation management, context building |
| Orchestration | 8 | Workflow orchestration coordination |
| Cost Optimization | 7 | Cost tracking, optimization, budgets |
| Storage | 7 | S3, GCS, NFS, SMB, local |
| Provider Testing | 6 | Connection testing, health checks |
| Billing | 2 | Subscriptions, payments |
| Others | 25+ | Admin, audit, monitoring, permissions, rate limiting |

---

## AI Services

Located in `server/app/services/ai/`. Handles AI agent orchestration, provider management, and workflow execution.

### Core Services

#### AgentOrchestrationService

**File**: `agent_orchestration_service.rb`

Primary service for executing AI agents with full orchestration support.

```ruby
class Ai::AgentOrchestrationService
  def initialize(agent:, account:, user: nil)
  def execute(input_parameters)
  def execute_with_streaming(input_parameters, &block)
end
```

**Responsibilities**:
- Agent execution lifecycle management
- Provider selection and fallback
- Token tracking and cost calculation
- Streaming response handling

#### McpAgentExecutor

**File**: `mcp_agent_executor.rb`

Executes agents through the MCP protocol.

```ruby
class Ai::McpAgentExecutor
  def initialize(agent:, execution:, account:)
  def execute(input_parameters)
end
```

### Provider Management

#### ProviderLoadBalancerService

**File**: `provider_load_balancer_service.rb`

Intelligent load balancing across AI providers.

```ruby
class Ai::ProviderLoadBalancerService
  LOAD_BALANCING_STRATEGIES = %w[
    round_robin
    weighted_round_robin
    least_connections
    cost_optimized
    performance_based
  ].freeze

  def initialize(account, capability: "text_generation", strategy: "cost_optimized")
  def select_provider(request_metadata = {})
  def execute_with_fallback(request_type, **options, &block)
  def load_balancing_stats
end
```

**Strategies**:
- `round_robin`: Simple rotation
- `weighted_round_robin`: Performance-weighted rotation
- `least_connections`: Route to least loaded
- `cost_optimized`: Minimize cost per request
- `performance_based`: Optimize for speed

#### ProviderCircuitBreakerService

**File**: `provider_circuit_breaker_service.rb`

Circuit breaker pattern for provider resilience.

```ruby
class Ai::ProviderCircuitBreakerService
  def initialize(provider)
  def provider_available?
  def record_success
  def record_failure(error)
  def circuit_state  # :closed, :open, :half_open
end
```

#### ProviderTestService

**File**: `provider_test_service.rb`

Tests provider connectivity and capabilities.

### Workflow Services

#### WorkflowValidationService

**File**: `workflow_validation_service.rb`

Validates workflow structure and configuration.

```ruby
class Ai::WorkflowValidationService
  def initialize(workflow)
  def validate
  def validate_node(node)
  def validate_edges
end
```

#### WorkflowRecoveryService

**File**: `workflow_recovery_service.rb`

Handles workflow failure recovery.

#### WorkflowCheckpointRecoveryService

**File**: `workflow_checkpoint_recovery_service.rb`

Checkpoint-based recovery for long-running workflows.

#### WorkflowCircuitBreakerService

**File**: `workflow_circuit_breaker_service.rb`

Circuit breaker for workflow execution.

#### WorkflowRetryStrategyService

**File**: `workflow_retry_strategy_service.rb`

Configurable retry strategies for workflows.

### Node Validators

Located in `server/app/services/ai/workflow_validators/`.

| Validator | Node Type | Purpose |
|-----------|-----------|---------|
| `BaseValidator` | All | Base validation logic |
| `AiAgentValidator` | ai_agent | Validates agent configuration |
| `ApiCallValidator` | api_call | Validates API call config |
| `ConditionValidator` | condition | Validates condition expressions |
| `DelayValidator` | delay | Validates delay configuration |
| `HumanApprovalValidator` | human_approval | Validates approval setup |
| `LoopValidator` | loop | Validates loop configuration |
| `SubWorkflowValidator` | sub_workflow | Validates nested workflows |
| `TransformValidator` | transform | Validates transform rules |
| `WebhookValidator` | webhook | Validates webhook config |

### Support Services

| Service | Purpose |
|---------|---------|
| `AnalyticsInsightsService` | AI usage analytics |
| `CostOptimizationService` | AI cost optimization |
| `CredentialEncryptionService` | Secure credential storage |
| `DebuggingService` | AI execution debugging |
| `ErrorRecoveryService` | Error handling strategies |

---

## MCP Services

Located in `server/app/services/mcp/`. Implements the Model Context Protocol for workflow execution.

### Core Components

#### AiWorkflowOrchestrator

Primary orchestrator for workflow execution (not in mcp/ but central to MCP).

#### Orchestrator Modules

Located in `server/app/services/mcp/orchestrator/`.

| Module | Purpose |
|--------|---------|
| `Validation` | Pre-execution validation |
| `Compensation` | Rollback on failure |

#### Node Executors

See [NODE_EXECUTOR_REFERENCE.md](NODE_EXECUTOR_REFERENCE.md) for complete documentation.

50 node executor classes in `server/app/services/mcp/node_executors/`:
- Control flow: start, end, condition, loop, split, merge, delay, scheduler
- AI: ai_agent, sub_workflow
- Integration: api_call, webhook, notification, email, database, file operations
- Content: page and KB article CRUD
- DevOps: CI/CD, Git operations, deployment
- MCP: tool, prompt, resource execution

### Support Services

| Service | Purpose |
|---------|---------|
| `ConditionalEvaluator` | Evaluates conditional expressions |
| `ExecutionTracer` | Execution tracing and debugging |

---

## Billing Services

Located in `server/app/services/billing/`. Handles subscription lifecycle, payments, and usage.

### SubscriptionService

**File**: `subscription_service.rb`

Core subscription lifecycle management.

```ruby
class Billing::SubscriptionService
  def initialize(subscription)
  def create(plan:, payment_method:)
  def update(params)
  def cancel(reason: nil, at_period_end: false)
  def pause
  def resume
  def change_plan(new_plan:, prorate: true)
end
```

### PaymentProcessingService

**File**: `payment_processing_service.rb`

Processes payments through configured providers.

```ruby
class Billing::PaymentProcessingService
  def initialize(account)
  def process_payment(amount:, currency:, payment_method:)
  def refund(payment_id, amount: nil)
end
```

### FeaturePlanService

**File**: `feature_plan_service.rb`

Manages plan features and entitlements.

```ruby
class Billing::FeaturePlanService
  def initialize(plan)
  def feature_enabled?(feature_key)
  def feature_limit(feature_key)
  def compare_plans(other_plan)
end
```

### UsageLimitService

**File**: `usage_limit_service.rb`

Tracks and enforces usage limits.

```ruby
class Billing::UsageLimitService
  def initialize(subscription)
  def check_limit(feature_key, quantity: 1)
  def record_usage(feature_key, quantity: 1)
  def reset_usage(feature_key)
  def usage_summary
end
```

### SubscriptionBroadcastService

**File**: `subscription_broadcast_service.rb`

Broadcasts subscription changes via ActionCable.

### PayPalService

**File**: `paypal_service.rb`

PayPal payment integration.

---

## BaaS Services

Located in `server/app/services/baas/`. Implements Billing-as-a-Service for multi-tenant billing.

### TenantService

**File**: `tenant_service.rb` (inferred from controller)

Manages BaaS tenants.

```ruby
class BaaS::TenantService
  def initialize(account: nil, tenant: nil)
  def create_tenant(params)
  def update_tenant(params)
  def dashboard_stats
  def check_rate_limits
end
```

### BillingApiService

**File**: `billing_api_service.rb` (inferred from controller)

Core BaaS billing operations.

```ruby
class BaaS::BillingApiService
  def initialize(tenant:)

  # Customers
  def list_customers(status:, email:, page:, per_page:)
  def get_customer(id)
  def create_customer(params)
  def update_customer(id, params)

  # Subscriptions
  def list_subscriptions(status:, customer_id:, page:, per_page:)
  def get_subscription(id)
  def create_subscription(params)
  def update_subscription(id, params)
  def cancel_subscription(id, params)

  # Invoices
  def list_invoices(status:, customer_id:, page:, per_page:)
  def get_invoice(id)
  def create_invoice(params)
  def finalize_invoice(id)
  def pay_invoice(id, params)
  def void_invoice(id, params)
end
```

### UsageMeteringService

**File**: `usage_metering_service.rb` (inferred from controller)

Usage-based billing metering.

```ruby
class BaaS::UsageMeteringService
  def initialize(tenant:)
  def record_usage(params)
  def record_batch(events)
  def list_records(customer_id:, meter_id:, status:, start_date:, end_date:, page:, per_page:)
  def customer_usage_summary(customer_id:, start_date:, end_date:)
  def get_usage(customer_id:, meter_id:, start_date:, end_date:)
  def analytics(start_date:, end_date:)
end
```

---

## DevOps Services

Located in `server/app/services/devops/`. Handles CI/CD, Git operations, and deployments.

### Core Services

| Service | Purpose |
|---------|---------|
| `BaseExecutor` | Base class for executors |
| `ExecutionService` | Orchestrates DevOps executions |
| `ProviderClient` | Provider API client |

### Execution Services

| Service | Purpose |
|---------|---------|
| `GithubActionExecutor` | GitHub Actions integration |
| `McpServerExecutor` | MCP server execution |
| `RestApiExecutor` | REST API calls |
| `WebhookExecutor` | Webhook handling |

### Git Services

Located in `server/app/services/devops/git/`.

| Service | Purpose |
|---------|---------|
| `CredentialEncryptionService` | Git credential encryption |
| `OAuthService` | Git OAuth integration |

### Support Services

| Service | Purpose |
|---------|---------|
| `CredentialEncryptionService` | DevOps credential security |
| `PromptRenderer` | Template rendering |
| `RegistryService` | Container registry ops |
| `WorkflowGenerator` | CI workflow generation |

---

## Infrastructure Services

### Cost Optimization

Located in `server/app/services/cost_optimization/`.

| Service | Purpose |
|---------|---------|
| `BudgetManagement` | Budget tracking and alerts |
| `CostAnalysis` | Cost analysis and reporting |
| `CostTracking` | Real-time cost tracking |
| `ProviderOptimization` | Provider cost optimization |
| `Recommendations` | Cost reduction suggestions |
| `UsagePatterns` | Usage pattern analysis |

### Storage Providers

Located in `server/app/services/storage_providers/`.

| Service | Backend |
|---------|---------|
| `S3Storage` | AWS S3 |
| `GcsStorage` | Google Cloud Storage |
| `LocalStorage` | Local filesystem |
| `NfsStorage` | NFS mounts |
| `SmbStorage` | SMB/CIFS shares |

### Provider Testing

Located in `server/app/services/provider_testing/`.

| Service | Purpose |
|---------|---------|
| `ConnectionTesting` | Test provider connections |
| `HealthChecks` | Provider health monitoring |
| `LoadTesting` | Load/stress testing |
| `Reporting` | Test result reporting |

### Other Infrastructure Services

| Service | Purpose |
|---------|---------|
| `FileStorageService` | File storage abstraction |
| `WebhookHealthService` | Webhook health monitoring |
| `CorsConfigurationService` | CORS configuration |
| `ConsentManagementService` | GDPR consent management |
| `SensitiveDataSanitizer` | PII data sanitization |
| `SettingsUpdateService` | Settings management |
| `PdfReportService` | PDF report generation |
| `JsonSchemaValidator` | JSON schema validation |
| `PermissionSeeder` | Permission data seeding |
| `PageService` | CMS page management |

---

## Service Patterns

### Standard Service Structure

```ruby
# frozen_string_literal: true

class DomainName::ServiceName
  def initialize(required_dependency:, optional_dependency: nil)
    @required_dependency = required_dependency
    @optional_dependency = optional_dependency
    @logger = Rails.logger
  end

  def primary_action(params)
    validate_params!(params)
    result = perform_action(params)
    { success: true, data: result }
  rescue StandardError => e
    @logger.error "#{self.class.name} error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def validate_params!(params)
    raise ArgumentError, "Required param missing" unless params[:required]
  end

  def perform_action(params)
    # Implementation
  end
end
```

### Return Value Convention

All services should return a hash with:

```ruby
# Success
{ success: true, data: result_data }
{ success: true, data: result_data, meta: { pagination: ... } }

# Failure
{ success: false, error: "Error message" }
{ success: false, errors: ["Error 1", "Error 2"] }
```

### Service Concerns

Located in `server/app/services/concerns/`.

| Concern | Purpose |
|---------|---------|
| `AiNodeExecutors` | AI node execution helpers |
| `AiOrchestrationBroadcasting` | ActionCable broadcasting |
| `AiMonitoringConcern` | AI monitoring helpers |
| `AiWorkflowService` | Workflow service helpers |
| `BaseAiService` | Base AI service functionality |
| `CircuitBreakerCore` | Circuit breaker implementation |

### Using Concerns

```ruby
class MyService
  include Concerns::CircuitBreakerCore

  def execute
    with_circuit_breaker do
      # Protected operation
    end
  end
end
```

---

## Best Practices

### 1. Keep Services Focused

Each service should have a single responsibility:
- **Good**: `PaymentProcessingService` handles payments only
- **Bad**: `UserService` that handles auth, profiles, and preferences

### 2. Use Dependency Injection

```ruby
def initialize(account:, payment_processor: nil)
  @account = account
  @payment_processor = payment_processor || Billing::PaymentProcessingService.new(account)
end
```

### 3. Handle Errors Gracefully

```ruby
def execute
  result = perform_operation
  { success: true, data: result }
rescue SpecificError => e
  { success: false, error: e.message, error_code: "SPECIFIC_ERROR" }
rescue StandardError => e
  Rails.logger.error "Unexpected error: #{e.message}"
  { success: false, error: "An unexpected error occurred" }
end
```

### 4. Log Appropriately

```ruby
@logger.info "Starting operation for account #{@account.id}"
@logger.debug "Processing with params: #{params.inspect}"
@logger.warn "Rate limit approaching for #{@account.id}"
@logger.error "Operation failed: #{error.message}"
```

### 5. Use Transactions

```ruby
def create_with_dependencies
  ActiveRecord::Base.transaction do
    primary = create_primary_record
    create_dependent_records(primary)
    { success: true, data: primary }
  end
rescue ActiveRecord::RecordInvalid => e
  { success: false, errors: e.record.errors.full_messages }
end
```

---

**Document Status**: Complete
**Last Updated**: 2026-02-26
**Source**: `server/app/services/` (634 files)
