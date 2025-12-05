# Platform Patterns and Standards

**Comprehensive pattern discovery, standardization recommendations, and component guidelines**

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Backend Patterns](#backend-patterns)
3. [Frontend Patterns](#frontend-patterns)
4. [Worker Patterns](#worker-patterns)
5. [Cross-Platform Patterns](#cross-platform-patterns)
6. [Component Standardization](#component-standardization)
7. [Standardization Recommendations](#standardization-recommendations)
8. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

The Powernode platform demonstrates strong architectural consistency with well-defined patterns across all services. Key findings:

- **Pattern Compliance**: 95%+ consistency across codebase
- **Backend**: Standardized API controllers, service patterns, authentication
- **Frontend**: Feature-based architecture, permission-based access control
- **Worker**: BaseJob inheritance, API-only communication

---

## Backend Patterns

### Controller Pattern

**Standard Structure**:
```ruby
class Api::V1::UsersController < ApplicationController
  include UserSerialization

  before_action :set_user, only: [:show, :update, :destroy]
  before_action -> { require_permission('admin.user.view') }, only: [:index, :stats]

  def index
    render json: { success: true, data: users.map { |user| user_data(user) } }, status: :ok
  end
end
```

**Standardization Elements**:
- **Namespace**: `Api::V1` for all API controllers
- **Inheritance**: `ApplicationController` base class
- **Concerns**: Modular functionality via includes
- **Permission Checks**: Lambda-based permission requirements
- **Response Format**: Consistent `{success, data, error}` structure
- **Status Codes**: Semantic HTTP status codes

**Usage**: 25+ controllers follow this pattern (95%+ consistency)

### Model Pattern

**Standard Structure**:
```ruby
class User < ApplicationRecord
  # 1. Authentication
  has_secure_password

  # 2. Concerns
  include PasswordSecurity

  # 3. Associations
  belongs_to :account
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  # 4. Validations
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: %w[active inactive suspended] }

  # 5. Scopes
  scope :active, -> { where(status: 'active') }

  # 6. Callbacks
  before_create :set_defaults

  # 7. Public Methods
  def full_name
    "#{first_name} #{last_name}"
  end

  # 8. Private Methods
  private

  def set_defaults
    # ...
  end
end
```

**Structure Order**: Authentication → Concerns → Associations → Validations → Scopes → Callbacks → Methods → Private

### Service Pattern

```ruby
class BillingService
  include ActiveModel::Model

  attr_accessor :subscription, :account, :user

  def create_subscription_with_payment(plan:, payment_method:, **options)
    # Delegate complex operations to worker service
    WorkerJobService.enqueue_billing_job('create_subscription_with_payment', job_data)

    { success: true, message: "Subscription creation initiated", job_id: job.id }
  end
end
```

**Elements**:
- **ActiveModel::Model**: Provides validations and attribute handling
- **Worker Delegation**: Complex operations delegated to worker service
- **Keyword Arguments**: Consistent parameter patterns
- **Response Format**: Uniform success/error responses

### Authentication Pattern

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account
  end

  private

  def authenticate_request
    # JWT token validation
    # Permission-based access control
    # Impersonation support
  end

  def require_permission(permission)
    render_unauthorized unless current_user.has_permission?(permission)
  end
end
```

**Features**:
- JWT-based authentication
- Permission-based authorization (not role-based)
- Impersonation support
- Consistent error responses

---

## Frontend Patterns

### Component Architecture

**Directory Structure**:
```
src/features/[domain]/
├── components/     # Feature-specific components
├── hooks/          # Custom hooks
├── services/       # API services
├── types/          # TypeScript definitions
└── utils/          # Utility functions
```

**Component Pattern**:
```typescript
interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger';
  size?: 'xs' | 'sm' | 'md' | 'lg';
  loading?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(({
  variant = 'primary',
  size = 'md',
  className = '',
  ...props
}, ref) => {
  const baseClasses = 'btn-theme';
  // Implementation...
});
```

**Elements**:
- TypeScript interfaces with proper prop typing
- forwardRef for DOM elements
- Default props with sensible defaults
- Theme classes: `btn-theme`, `bg-theme-*`, `text-theme-*`

### API Service Pattern

**Base Client**:
```typescript
const api: AxiosInstance = axios.create({
  baseURL: getAPIBaseURL(),
  timeout: 10000,
});

// Request/Response interceptors for auth and error handling
```

**Feature Service**:
```typescript
export const usersApi = {
  getUsers: async () => {
    const response = await api.get('/users');
    return response.data;
  },

  createUser: async (userData: CreateUserData) => {
    const response = await api.post('/users', userData);
    return response.data;
  }
};
```

**Elements**:
- Axios-based HTTP client
- Dynamic backend URL resolution
- Centralized error interceptors
- Full TypeScript type safety
- Consistent response format

### Permission-Based Access Control (CRITICAL)

```typescript
// Hook pattern
export const usePermissions = () => {
  const { currentUser } = useAuth();

  const hasPermission = (permission: string): boolean => {
    return currentUser?.permissions?.includes(permission) || false;
  };

  return { hasPermission };
};

// Component usage
const { hasPermission } = usePermissions();
const canManageUsers = hasPermission('users.manage');

if (!canManageUsers) return <AccessDenied />;
```

**CRITICAL RULES**:
- **Permission-Only**: No role-based access control on frontend
- **Consistent Naming**: `resource.action` format (e.g., `users.manage`)
- **Type Safety**: Permission constants defined

### State Management Pattern

```typescript
// Redux Toolkit slice
export const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    setCurrentUser: (state, action) => {
      state.currentUser = action.payload;
    },
  }
});
```

**Usage**: Context for simple state, Redux for complex application state

---

## Worker Patterns

### BaseJob Inheritance

```ruby
class BaseJob
  include Sidekiq::Job

  sidekiq_options retry: 3, dead: true, queue: 'default'

  sidekiq_retry_in do |count, exception|
    # Exponential backoff with API error handling
  end

  def perform(*args)
    execute(*args)  # Abstract method
  end
end
```

**Concrete Job**:
```ruby
class SubscriptionRenewalJob < BaseJob
  sidekiq_options queue: 'billing'

  def execute(subscription_id)
    # Business logic using API client
    api_client.renew_subscription(subscription_id)
  end
end
```

**Elements**:
- All jobs inherit from `BaseJob`
- Consistent retry and queue settings
- API communication only (no direct database)
- Centralized retry logic

### API Client Pattern

```ruby
class BackendApiClient
  BASE_URL = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000/api/v1')

  def initialize
    @token = ENV['WORKER_TOKEN']
  end

  def renew_subscription(subscription_id)
    post("/subscriptions/#{subscription_id}/renew", {})
  end

  private

  def post(path, data)
    # HTTP request with auth headers
  end
end
```

**Features**:
- Environment-based configuration
- Worker token-based authentication
- Structured API error handling
- RESTful API patterns

---

## Cross-Platform Patterns

### Configuration Management

```ruby
# Backend
JWT_SECRET = Rails.application.credentials.jwt_secret

# Worker
WORKER_TOKEN = ENV.fetch('WORKER_TOKEN')
```

```typescript
// Frontend
const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || 'http://localhost:3000/api/v1';
```

### Error Handling

**Backend**:
```ruby
def render_validation_errors(exception)
  render json: {
    success: false,
    error: errors.first,
    details: errors
  }, status: :unprocessable_content
end
```

**Frontend**:
```typescript
try {
  const result = await api.post('/users', userData);
  showNotification('User created successfully', 'success');
} catch (error) {
  showNotification(error.response?.data?.error || 'Operation failed', 'error');
}
```

### Logging Pattern

```ruby
Rails.logger.info "Starting #{self.class.name} with args: #{args.inspect}"
Rails.logger.error "Internal error: #{exception.message}"
```

---

## Component Standardization

### FlexContainer System

**File**: `frontend/src/shared/components/ui/FlexContainer.tsx`

**Components**:
- `FlexContainer` - Full flex control
- `FlexItemsCenter` - Replaces `flex items-center space-x-*` (1,399 instances)
- `FlexBetween` - `justify-between` layouts
- `FlexCentered` - Centered content
- `FlexRow`, `FlexCol` - Directional shortcuts

**Usage**:
```tsx
// Before (manual pattern)
<div className="flex items-center space-x-1">
  <Star className="w-4 h-4" />
  <span>{rating}</span>
</div>

// After (standardized)
<FlexItemsCenter gap="xs">
  <Star className="w-4 h-4" />
  <span>{rating}</span>
</FlexItemsCenter>
```

### GridContainer System

**File**: `frontend/src/shared/components/ui/GridContainer.tsx`

**Components**:
- `GridContainer` - Flexible grid configuration
- `GridCols2`, `GridCols3`, `GridCols4` - Common layouts (264 instances)
- `GridAutoFit` - Auto-responsive grids
- `GridResponsive` - Mobile-first patterns

### AsyncState Management

**File**: `frontend/src/shared/hooks/useAsyncState.ts`

**Hooks**:
- `useAsyncState<T>` - Complete async state management
- `useLoadingState` - Simple loading/error handling
- `useAsyncOperations` - Multiple async operations

### StatusIndicator Component

**File**: `frontend/src/shared/components/ui/StatusIndicator.tsx`

**Components**:
- `StatusIndicator` - Universal status display
- `ActiveStatus`, `InactiveStatus`, `LoadingStatus`, `ErrorStatus`

---

## Standardization Recommendations

### High Priority

#### 1. Documentation Standardization
- Enhance Rails Architect with controller and auth patterns
- Update API Developer with response format standards
- Document React component architecture patterns
- Standardize worker job patterns

#### 2. Permission System Documentation
```typescript
// CRITICAL: Document permission-only access control
// Frontend: NEVER use roles for access control
const canManage = hasPermission('users.manage');  // ✅ CORRECT
const isAdmin = user.role === 'admin';           // ❌ FORBIDDEN
```

**Actions**:
- Document permission naming conventions (`resource.action`)
- Create permission validation tools
- Update all MCP specialists with permission patterns

#### 3. API Response Format
```ruby
# Standard Success Response
{ success: true, data: object_or_array, message?: "Optional" }

# Standard Error Response
{ success: false, error: "Primary error", details?: [], code?: "ERROR_CODE" }
```

### Medium Priority

#### 4. Pattern Validation Tooling
```bash
#!/bin/bash
echo "=== Pattern Compliance Check ==="

# Controller namespace compliance
find server/app/controllers -name "*.rb" | grep -c "api/v1"

# Response format compliance
grep -r "render json:" server/app/controllers/ | grep -c '"success":'

# Permission-based auth compliance
grep -r "hasPermission.*includes" frontend/src/ | wc -l
```

#### 5. Testing Pattern Standardization

**Backend**:
```ruby
RSpec.describe Api::V1::UsersController, type: :controller do
  let(:current_account) { create(:account) }
  let(:current_user) { create(:user, account: current_account) }

  describe 'GET #index' do
    context 'with proper permissions' do
      before { current_user.grant_permission('users.view') }

      it 'returns users successfully' do
        get :index, headers: headers
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end
    end
  end
end
```

**Frontend**:
```typescript
describe('ComponentWithPermissions', () => {
  it('renders for users with permission', () => {
    const mockUser = { permissions: ['users.manage'] };
    render(
      <TestProviders initialUser={mockUser}>
        <ComponentWithPermissions />
      </TestProviders>
    );
    expect(screen.getByRole('button', { name: /create/i })).toBeInTheDocument();
  });
});
```

### Low Priority

#### 6. Performance Pattern Documentation
- Database query optimization patterns
- Caching strategies
- Frontend memoization and lazy loading

#### 7. Architecture Evolution Framework
- Pattern proposal process
- Implementation guidelines
- Deprecation workflows

---

## Implementation Roadmap

### Phase 1: Documentation Enhancement (Week 1-2)
- [ ] Update Backend MCP specialists with discovered patterns
- [ ] Enhance Frontend MCP specialists with component patterns
- [ ] Document Worker patterns in Background Job Engineer
- [ ] Create cross-cutting pattern documentation

### Phase 2: Pattern Standardization (Week 3-4)
- [ ] Implement missing pattern documentation
- [ ] Create pattern validation tools
- [ ] Update development workflows with pattern checks
- [ ] Enhance code review guidelines

### Phase 3: Architecture Enhancement (Week 5-6)
- [ ] Implement high-priority standardization opportunities
- [ ] Create pattern enforcement tooling
- [ ] Update developer onboarding with pattern guidelines
- [ ] Establish pattern evolution process

---

## Success Metrics

### Quantitative
- **Pattern Compliance**: Target 98% (current: ~95%)
- **Code Review Time**: 30% reduction in pattern-related comments
- **Developer Onboarding**: 40% faster time-to-productivity
- **Bug Rate**: 25% reduction in pattern-related bugs
- **Documentation Coverage**: 100% of patterns documented

### Qualitative
- **Developer Satisfaction**: Improved consistency and predictability
- **Code Quality**: More maintainable and readable codebase
- **Team Velocity**: Faster feature development
- **Platform Stability**: More reliable system behavior

---

## Quick Reference Commands

```bash
# Pattern compliance audit
grep -r "class.*Controller" $POWERNODE_ROOT/server/app/controllers/ | wc -l
grep -r "class.*Service" $POWERNODE_ROOT/server/app/services/ | wc -l
grep -r "export.*Component" $POWERNODE_ROOT/frontend/src/ | wc -l

# Permission audit (frontend should use permissions, not roles)
grep -r "hasPermission.*includes" frontend/src/ | wc -l  # Should be high
grep -r "\.roles\?\." frontend/src/ | wc -l              # Should be minimal

# Response format audit
grep -c "render json:.*success:" server/app/controllers/**/*.rb

# Worker job inheritance
grep -r "< BaseJob" worker/app/jobs/ | wc -l
```

---

**Document Status**: ✅ Complete
**Consolidates**: PLATFORM_PATTERNS_ANALYSIS.md, PLATFORM_STANDARDIZATION_RECOMMENDATIONS.md, PLATFORM_AUDIT_STRATEGY.md, STANDARDIZATION_COMPONENT_PATTERNS.md

