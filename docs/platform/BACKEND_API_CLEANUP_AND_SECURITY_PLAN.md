# Backend API Cleanup and Security Plan

## Overview

This plan addresses four critical issues in the Powernode backend API:

1. **Duplicate Admin Namespace in routes.rb** - Three admin namespaces exist (lines 274-382, 683-697, 829-903)
2. **Orphaned Action** - `WorkersController#current_token` has no corresponding route
3. **Missing Authentication** - `Internal::JobsController` and `Internal::ReverseProxyController` lack authentication
4. **Inconsistent Authentication Patterns** - Internal controllers use different authentication approaches

---

## Issue 1: Duplicate Admin Namespace Definitions

### Current State

The `routes.rb` file contains **three** separate `namespace :admin` blocks:

| Block | Lines | Contents |
|-------|-------|----------|
| **Primary** | 274-382 | Main admin routes: jobs, users, pages, circuit_breakers, validation_rules, maintenance, rate_limiting, proxy_settings |
| **Secondary** | 683-697 | Only `review_moderation` resource |
| **Tertiary** | 829-903 | Duplicate of: jobs, users, pages, maintenance, rate_limiting |

### Analysis

- **Lines 829-903 duplicate lines 274-382** for: `admin/jobs`, `admin/users`, `admin/pages`, `admin/maintenance/*`, `admin/rate_limiting/*`
- The comment on line 849 says "Knowledge Base admin functionality moved to main /api/v1/kb endpoints" suggesting this was left behind during refactoring
- **Lines 683-697 contain only `review_moderation`** which should be consolidated into the primary block

### Recommendation: Keep Primary Block (274-382), Consolidate Others

**Risk Level**: LOW - Route deduplication does not change behavior when identical routes exist

### Implementation Steps

**Step 1.1**: Remove duplicate block at lines 829-903 entirely

```ruby
# DELETE LINES 829-903 (entire third admin namespace block)
```

**Step 1.2**: Move `review_moderation` from lines 683-697 into primary admin block (after proxy_settings, before closing `end`)

The `review_moderation` routes should be added to the primary admin namespace at line 381:

```ruby
# Add after proxy_settings routes (line 381), before the closing `end`
resource :review_moderation, only: [] do
  collection do
    get :queue
    post :bulk_action
    get :analytics
    get :settings
    post :update_settings
  end
  
  member do
    get 'history/:review_id', to: 'review_moderation#history'
  end
end
```

Then delete lines 683-697.

---

## Issue 2: WorkersController#current_token - Orphaned Action

### Current State

- **Action exists**: `/server/app/controllers/api/v1/workers_controller.rb` lines 258-292
- **No route defined**: `grep -n "current_token" server/config/routes.rb` returns nothing
- **Action purpose**: Retrieves current system worker token for super admins only

### Analysis

The `current_token` action:
- Requires super admin permission (`super_admin`)
- Only works for system workers
- Returns the `WORKER_TOKEN` environment variable
- Validates the token matches the worker

### Recommendation: Add Route

This is a legitimate administrative function that should have a route. Add it as a member action on the workers resource.

**Risk Level**: LOW - Adding a new route, no existing functionality affected

### Implementation

**Step 2.1**: Add route at line 916 (after `health_check` in workers resource):

```ruby
resources :workers do
  member do
    post :regenerate_token
    post :suspend
    post :activate
    post :revoke
    post :test_worker
    post :test_results
    post :health_check
    get :current_token  # ADD THIS LINE
  end
  
  # ... rest of workers routes
end
```

---

## Issue 3: Missing Authentication on Internal Controllers

### Current State

| Controller | Authentication | Skip authenticate_request | before_action |
|------------|----------------|---------------------------|---------------|
| `Internal::AccountsController` | JWT Service Token | YES | `authenticate_service_token` |
| `Internal::UsersController` | JWT Service Token | YES | `authenticate_service_token` |
| `Internal::WorkersController` | Worker Token (env var) | YES | `authenticate_worker_service!` |
| `Internal::InvitationsController` | Worker Token (env var) | YES | `authenticate_worker` |
| **`Internal::JobsController`** | **NONE** | NO | **NONE** |
| **`Internal::ReverseProxyController`** | **NONE** | NO | **NONE** |

### Analysis

**Critical Security Gap**: `JobsController` and `ReverseProxyController` inherit from `ApplicationController` which includes `Authentication` concern. This means `authenticate_request` runs by default. However:

1. These controllers include `ApiResponse` concern redundantly (already in ApplicationController)
2. They do NOT skip `authenticate_request`
3. They do NOT add service-level authentication

**Current behavior**: These endpoints require a valid JWT user token OR worker token, which is somewhat protected but inconsistent with other internal controllers that use service-specific authentication.

### Recommendation: Add Consistent Service Authentication

Internal endpoints should use the service token pattern (JWT with `service: 'worker'` and `type: 'service'`) for consistency and to avoid requiring user-level authentication.

**Risk Level**: MEDIUM - Changes authentication requirement; must coordinate with worker service

### Implementation

**Step 3.1**: Update `Internal::JobsController`

File: `/server/app/controllers/api/v1/internal/jobs_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::JobsController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token
  
  # ... existing actions remain unchanged ...

  private

  def authenticate_service_token
    token = request.headers['Authorization']&.split(' ')&.last
    
    unless token.present?
      render_error('Service token required', status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first

      unless payload['service'] == 'worker' && payload['type'] == 'service'
        render_error('Invalid service token', status: :unauthorized)
        return
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error('Invalid service token', status: :unauthorized)
    end
  end
end
```

**Step 3.2**: Update `Internal::ReverseProxyController`

File: `/server/app/controllers/api/v1/internal/reverse_proxy_controller.rb`

```ruby
# frozen_string_literal: true

class Api::V1::Internal::ReverseProxyController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token
  
  # ... existing actions remain unchanged ...

  private

  def authenticate_service_token
    token = request.headers['Authorization']&.split(' ')&.last
    
    unless token.present?
      render_error('Service token required', status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first

      unless payload['service'] == 'worker' && payload['type'] == 'service'
        render_error('Invalid service token', status: :unauthorized)
        return
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error('Invalid service token', status: :unauthorized)
    end
  end
end
```

**Step 3.3**: Also remove redundant `include ApiResponse` from both controllers (already included via ApplicationController)

---

## Issue 4: Authentication Pattern Standardization

### Current Internal Authentication Patterns

1. **JWT Service Token** (`authenticate_service_token`):
   - Used by: `AccountsController`, `UsersController`
   - Validates: `payload['service'] == 'worker' && payload['type'] == 'service'`
   - Token: JWT signed with `jwt_secret_key`

2. **Worker Token** (`authenticate_worker_service!` / `authenticate_worker`):
   - Used by: `WorkersController`, `InvitationsController`
   - Validates: `ActiveSupport::SecurityUtils.secure_compare(token, worker_token)`
   - Token: Static `WORKER_TOKEN` environment variable

### Recommendation: Standardize on JWT Service Token

The JWT Service Token pattern is preferable because:
- Tokens can expire
- Tokens are cryptographically signed
- Tokens can contain additional claims (service name, permissions)
- No static secrets in environment variables

However, this would require worker service changes. For now, document both patterns as acceptable and ensure all internal controllers use one of them.

**Risk Level**: LOW - Documentation only; no immediate code changes

### Documentation

Create or update `/docs/backend/INTERNAL_API_AUTHENTICATION.md`:

```markdown
# Internal API Authentication

## Overview

Internal API endpoints (under `/api/v1/internal/`) are used for service-to-service 
communication, primarily between the main Rails backend and the Sidekiq worker service.

## Accepted Authentication Methods

### 1. JWT Service Token (Preferred)

Controllers: `AccountsController`, `UsersController`, `JobsController`, `ReverseProxyController`

Token format:
```json
{
  "service": "worker",
  "type": "service",
  "iat": 1234567890,
  "exp": 1234571490
}
```

Authorization header: `Authorization: Bearer <jwt_token>`

### 2. Worker Token (Legacy)

Controllers: `WorkersController`, `InvitationsController`

Token: Static `WORKER_TOKEN` environment variable

Authorization header: `Authorization: Bearer <worker_token>`

### Security Requirements

All internal controllers MUST:
1. Include `skip_before_action :authenticate_request`
2. Include a `before_action` that authenticates the service
3. Return 401 Unauthorized for invalid/missing tokens
4. Log authentication failures for security monitoring
```

---

## Testing Strategy

### Unit Tests

**Step T1**: Create/update RSpec tests for internal controller authentication

File: `/server/spec/requests/api/v1/internal/jobs_controller_spec.rb`

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::JobsController', type: :request do
  let(:valid_service_token) do
    JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
  end
  
  let(:invalid_service_token) do
    JWT.encode(
      { service: 'other', type: 'user', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
  end

  describe 'authentication' do
    let(:job) { create(:background_job) }

    context 'without authorization header' do
      it 'returns 401 unauthorized' do
        get "/api/v1/internal/jobs/#{job.job_id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid service token' do
      it 'returns 401 unauthorized' do
        get "/api/v1/internal/jobs/#{job.job_id}",
            headers: { 'Authorization' => "Bearer #{invalid_service_token}" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid service token' do
      it 'returns 200 success' do
        get "/api/v1/internal/jobs/#{job.job_id}",
            headers: { 'Authorization' => "Bearer #{valid_service_token}" }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
```

**Step T2**: Similar test file for `ReverseProxyController`

### Integration Tests

**Step T3**: Test route consolidation

```ruby
# Verify routes exist and are not duplicated
RSpec.describe 'Admin routes' do
  it 'has single path for admin/jobs' do
    routes = Rails.application.routes.routes.select { |r| 
      r.path.spec.to_s.include?('/api/v1/admin/jobs')
    }
    # Should have exactly 2 routes: index and show
    expect(routes.count).to eq(2)
  end
end
```

### Manual Testing Checklist

- [ ] `curl -X GET http://localhost:3000/api/v1/internal/jobs/test-id` returns 401
- [ ] `curl -X GET http://localhost:3000/api/v1/internal/jobs/test-id -H "Authorization: Bearer VALID_TOKEN"` returns expected response
- [ ] `curl -X POST http://localhost:3000/api/v1/internal/reverse_proxy/validate` returns 401
- [ ] Admin routes work correctly after consolidation
- [ ] Worker service can still communicate with internal endpoints

---

## Risk Assessment

| Change | Risk Level | Rollback Complexity | Impact if Failed |
|--------|------------|---------------------|------------------|
| Remove duplicate admin routes | LOW | Easy - restore lines | Route confusion only |
| Add `current_token` route | LOW | Easy - remove line | No new functionality |
| Add auth to JobsController | MEDIUM | Easy - revert file | Worker jobs fail |
| Add auth to ReverseProxyController | MEDIUM | Easy - revert file | Proxy operations fail |
| Route consolidation | LOW | Easy - restore lines | Route confusion only |

### Mitigation Strategies

1. **Deploy during low-traffic period**
2. **Monitor worker service logs** for authentication failures
3. **Verify worker service has valid JWT service tokens** before deployment
4. **Have rollback ready** in case of issues

---

## Implementation Order

1. **Phase 1: Documentation** (No risk)
   - Create internal API authentication documentation
   
2. **Phase 2: Route Cleanup** (Low risk)
   - Remove duplicate admin namespace (lines 829-903)
   - Move review_moderation into primary admin namespace
   - Add `current_token` route to workers
   
3. **Phase 3: Security Hardening** (Medium risk)
   - Update JobsController with authentication
   - Update ReverseProxyController with authentication
   - Remove redundant `include ApiResponse` statements
   
4. **Phase 4: Testing** (No risk)
   - Add/update RSpec tests
   - Perform integration testing
   - Verify worker service compatibility

---

## Files to Modify

### Critical Files for Implementation

1. **`/server/config/routes.rb`**
   - Remove lines 829-903 (duplicate admin namespace)
   - Move lines 683-697 into primary admin namespace at line 381
   - Add `get :current_token` to workers resource at line 916

2. **`/server/app/controllers/api/v1/internal/jobs_controller.rb`**
   - Add `skip_before_action :authenticate_request`
   - Add `before_action :authenticate_service_token`
   - Add `authenticate_service_token` private method
   - Remove redundant `include ApiResponse`

3. **`/server/app/controllers/api/v1/internal/reverse_proxy_controller.rb`**
   - Add `skip_before_action :authenticate_request`
   - Add `before_action :authenticate_service_token`
   - Add `authenticate_service_token` private method
   - Remove redundant `include ApiResponse`

4. **`/server/spec/requests/api/v1/internal/`** (new test files)
   - `jobs_controller_spec.rb`
   - `reverse_proxy_controller_spec.rb`

5. **`/docs/backend/INTERNAL_API_AUTHENTICATION.md`** (new documentation)
   - Document authentication patterns
   - Document security requirements

---

## Summary

This plan addresses four security and maintenance issues:

1. **Route duplication**: Clean up three admin namespaces into one
2. **Orphaned action**: Add missing route for `current_token`
3. **Security gap**: Add proper service authentication to internal controllers
4. **Standardization**: Document internal API authentication patterns

Total estimated implementation time: 2-3 hours including testing.
