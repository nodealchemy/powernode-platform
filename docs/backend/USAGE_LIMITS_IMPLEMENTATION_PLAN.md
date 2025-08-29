# Usage Limits Implementation Plan

## Overview
This document outlines the implementation plan for usage limits in the Powernode subscription platform. We've identified 4 easily implementable limits based on existing model relationships.

## Selected Usage Limits (Ready to Implement)

### ✅ 1. Maximum Users per Account
**Current State**: Account has_many :users relationship exists
**Implementation**: Simple count check before user creation
```ruby
# Implementation location: User model or UsersController
def can_add_user?(account)
  plan_limit = account.subscription.plan.limits['max_users']
  return true if plan_limit >= 9999 # Unlimited
  account.users.count < plan_limit
end
```

### ✅ 2. Maximum API Keys
**Current State**: ApiKey belongs_to :account relationship exists
**Implementation**: Count check before API key creation
```ruby
# Implementation location: ApiKey model or ApiKeysController
def can_create_api_key?(account)
  plan_limit = account.subscription.plan.limits['max_api_keys']
  return true if plan_limit >= 100 # Unlimited
  account.api_keys.active.count < plan_limit
end
```

### ✅ 3. Maximum Webhook Endpoints  
**Current State**: WebhookEndpoint model exists with account relationship
**Implementation**: Count check before webhook creation
```ruby
# Implementation location: WebhookEndpoint model or WebhooksController
def can_create_webhook?(account)
  plan_limit = account.subscription.plan.limits['max_webhooks'] 
  return true if plan_limit >= 100 # Unlimited
  account.webhook_endpoints.active.count < plan_limit
end
```

### ✅ 4. Maximum Workers
**Current State**: Worker belongs_to :account relationship exists
**Implementation**: Count check before worker creation
```ruby
# Implementation location: Worker model or WorkersController
def can_create_worker?(account)
  plan_limit = account.subscription.plan.limits['max_workers']
  return true if plan_limit >= 100 # Unlimited
  account.workers.count < plan_limit
end
```

## Implementation Steps

### Phase 1: Backend Plan Limits Structure

1. **Update Plan Model**
```ruby
# server/app/models/plan.rb
class Plan < ApplicationRecord
  # Add default limits structure
  after_initialize :set_default_limits

  private

  def set_default_limits
    self.limits ||= {
      'max_users' => 2,
      'max_api_keys' => 5,
      'max_webhooks' => 5,
      'max_workers' => 3
    }
  end
end
```

2. **Create Usage Limit Service**
```ruby
# server/app/services/usage_limit_service.rb
class UsageLimitService
  def self.can_add_user?(account)
    check_limit(account, 'max_users', account.users.count)
  end

  def self.can_create_api_key?(account)
    check_limit(account, 'max_api_keys', account.api_keys.active.count)
  end

  def self.can_create_webhook?(account)
    check_limit(account, 'max_webhooks', account.webhook_endpoints.active.count)
  end

  def self.can_create_worker?(account)
    check_limit(account, 'max_workers', account.workers.count)
  end

  private

  def self.check_limit(account, limit_key, current_count)
    plan = account.subscription&.plan
    return false unless plan

    plan_limit = plan.limits[limit_key]
    return true if plan_limit >= 999 # Unlimited threshold

    current_count < plan_limit
  end
end
```

### Phase 2: Controller Integration

1. **Update Controllers with Limit Checks**
```ruby
# server/app/controllers/api/v1/users_controller.rb
def create
  unless UsageLimitService.can_add_user?(current_account)
    render_error('User limit reached for your current plan')
    return
  end
  
  # Existing user creation logic...
end
```

2. **Update API Keys Controller**
```ruby
# server/app/controllers/api/v1/api_keys_controller.rb  
def create
  unless UsageLimitService.can_create_api_key?(current_account)
    render_error('API key limit reached for your current plan')
    return
  end
  
  # Existing API key creation logic...
end
```

3. **Update Webhook Endpoints Controller**
```ruby
# server/app/controllers/api/v1/webhook_endpoints_controller.rb
def create
  unless UsageLimitService.can_create_webhook?(current_account)
    render_error('Webhook endpoint limit reached for your current plan')
    return
  end
  
  # Existing webhook creation logic...
end
```

4. **Update Workers Controller**
```ruby
# server/app/controllers/api/v1/workers_controller.rb
def create
  unless UsageLimitService.can_create_worker?(current_account)
    render_error('Worker limit reached for your current plan')
    return
  end
  
  # Existing worker creation logic...
end
```

### Phase 3: Frontend Integration

1. **Update API Services to Handle Limit Errors**
```typescript
// frontend/src/shared/services/api.ts
// Add handling for usage limit errors (already structured for this)
```

2. **Add Usage Limit Display Components**
```typescript
// frontend/src/shared/components/UsageLimitDisplay.tsx
interface UsageLimitProps {
  current: number;
  limit: number;
  label: string;
}

export const UsageLimitDisplay: React.FC<UsageLimitProps> = ({ current, limit, label }) => {
  const isUnlimited = limit >= 999;
  const percentage = isUnlimited ? 0 : (current / limit) * 100;
  
  return (
    <div className="usage-limit-display">
      <span>{label}: {current}{isUnlimited ? '' : `/${limit}`}</span>
      {!isUnlimited && <div className="progress-bar" style={{width: `${percentage}%`}} />}
    </div>
  );
};
```

### Phase 4: Database Migration

1. **Update Plan Seeds with New Limits**
```ruby
# server/db/seeds.rb - Update existing plan seeds
plans.each do |plan_data|
  plan_data[:limits] = {
    'max_users' => plan_specific_user_limit,
    'max_api_keys' => plan_specific_api_limit,  
    'max_webhooks' => plan_specific_webhook_limit,
    'max_workers' => plan_specific_worker_limit
  }
end
```

### Phase 5: Testing

1. **Add Usage Limit Tests**
```ruby
# spec/services/usage_limit_service_spec.rb
RSpec.describe UsageLimitService do
  describe '.can_add_user?' do
    it 'returns false when user limit is reached' do
      # Test implementation
    end
    
    it 'returns true when limit is not reached' do
      # Test implementation  
    end
    
    it 'returns true for unlimited plans' do
      # Test implementation
    end
  end
  
  # Similar tests for other limits...
end
```

2. **Controller Integration Tests**
```ruby
# spec/controllers/api/v1/users_controller_spec.rb
describe 'POST #create' do
  context 'when user limit is reached' do
    it 'returns error message' do
      # Test implementation
    end
  end
end
```

## Implementation Priority

1. **High Priority**: Users limit (most impactful for revenue)
2. **Medium Priority**: API Keys and Webhooks (developer-focused features)
3. **Low Priority**: Workers (advanced feature)

## Error Handling

- Consistent error messages across all limits
- Clear upgrade prompts when limits are reached
- Grace period considerations for existing accounts

## Future Enhancements (NOT in this implementation)

- API request rate limiting (requires middleware/Redis)
- Storage limits (requires file system integration)
- Bandwidth limiting (requires network monitoring)
- Email notification limits (requires email service integration)

## Timeline Estimate

- **Phase 1-2 (Backend)**: 2-3 days
- **Phase 3 (Frontend)**: 1-2 days  
- **Phase 4-5 (Migration/Testing)**: 1-2 days
- **Total**: 4-7 days implementation time

## Success Metrics

- All 4 usage limits enforced correctly
- Clear error messages when limits are reached
- Upgrade prompts drive plan conversions
- No performance impact on existing operations