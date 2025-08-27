# Powernode Platform Testing Strategy

## Overview

The Powernode subscription management platform employs a comprehensive, multi-layered testing strategy designed to ensure reliability, security, and maintainability across all services. This document outlines our testing philosophy, patterns, and procedures.

## Testing Philosophy

### Core Principles

1. **Quality Through Automation**: All critical user journeys must have automated test coverage
2. **Test-Driven Development**: Write tests before implementation for new features
3. **Service Isolation**: Each service (Backend, Frontend, Worker) has independent test suites
4. **Permission-Based Security**: All access control testing uses permissions, never roles
5. **CI/CD Integration**: Every commit and pull request is validated through automated testing

### Coverage Goals

| Service | Current Status | Target Coverage | Priority |
|---------|----------------|-----------------|----------|
| Backend API | 945+ tests passing | 90%+ statements | Critical |
| Frontend React | 70%+ coverage achieved | 75%+ statements | High |
| Worker Service | DNS/API fixes applied | 80%+ statements | High |
| Integration | Cross-service testing | 60%+ scenarios | Medium |

## Service-Specific Testing Strategies

### Backend API Testing (Rails + RSpec)

**Test Structure**: `/server/spec/`
- **Controllers** (`spec/controllers/`): API endpoint validation, permission checks
- **Models** (`spec/models/`): Business logic, validations, associations
- **Services** (`spec/services/`): Complex business operations
- **Integration** (`spec/requests/`): End-to-end API workflows
- **Security** (`spec/security/`): Authentication, authorization, vulnerability testing

**Key Patterns**:
```ruby
# Permission-based access control testing
RSpec.describe Api::V1::UsersController do
  describe 'GET #index' do
    context 'with users.read permission' do
      before { grant_permission(current_user, 'users.read') }
      it 'returns user list' do
        expect(response).to have_http_status(:ok)
      end
    end
    
    context 'without users.read permission' do
      it 'returns unauthorized' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

# API response structure validation
expect(json_response).to match({
  success: true,
  data: a_hash_including(:users),
  pagination: a_hash_including(:total, :pages)
})
```

### Frontend Testing (React + Jest + React Testing Library)

**Test Structure**: `/frontend/src/`
- **Components** (`**/*.test.tsx`): UI component behavior and accessibility
- **Services** (`services/*.test.ts`): API client logic and error handling
- **Utilities** (`shared/**/*.test.ts`): Pure functions and helpers
- **Integration** (`__tests__/integration/`): User journey flows

**Key Patterns**:
```typescript
// Permission-based UI testing
describe('AdminPanel', () => {
  it('shows admin content when user has admin.access permission', () => {
    const userWithPermission = {
      permissions: ['admin.access', 'users.manage']
    };
    
    render(<AdminPanel />, { user: userWithPermission });
    expect(screen.getByText('Admin Dashboard')).toBeInTheDocument();
  });
  
  it('shows access denied when user lacks admin.access permission', () => {
    const userWithoutPermission = {
      permissions: ['users.read']
    };
    
    render(<AdminPanel />, { user: userWithoutPermission });
    expect(screen.getByText('Access Denied')).toBeInTheDocument();
  });
});

// API service testing
describe('authAPI', () => {
  it('handles login success', async () => {
    mockApi.post.mockResolvedValueOnce({
      data: { success: true, data: { token: 'abc123' } }
    });
    
    const result = await authAPI.login('user@example.com', 'password');
    expect(result.success).toBe(true);
    expect(result.data.token).toBe('abc123');
  });
});
```

### Worker Service Testing (Sidekiq + RSpec)

**Test Structure**: `/worker/spec/`
- **Jobs** (`spec/jobs/`): Background job execution and retry logic
- **Services** (`spec/services/`): API client and external service integration
- **Performance** (`spec/performance/`): Load testing and resource usage
- **Integration** (`spec/integration/`): Backend communication workflows

**Key Patterns**:
```ruby
# Job testing with API mocking
RSpec.describe EmailDeliveryJob do
  describe '#execute' do
    it 'sends email via backend API' do
      stub_backend_api_success(:post, '/api/v1/emails', { sent: true })
      
      job = EmailDeliveryJob.new
      result = job.execute(user_id: 123, template: 'welcome')
      
      expect(result).to be_success
      expect_api_request(:post, '/api/v1/emails')
    end
  end
end

# API client testing with WebMock
RSpec.describe BackendApiClient do
  describe '#get_user' do
    it 'fetches user data successfully' do
      stub_request(:get, 'http://localhost:3000/api/v1/users/123')
        .to_return(status: 200, body: { success: true, data: { id: 123 } }.to_json)
      
      client = BackendApiClient.new
      result = client.get_user(123)
      
      expect(result['success']).to be true
      expect(result['data']['id']).to eq 123
    end
  end
end
```

## Critical Testing Requirements

### Permission-Based Access Control (MANDATORY)

**✅ Always Test Permissions**:
```typescript
// Frontend - CORRECT
const canManageUsers = currentUser?.permissions?.includes('users.manage');
if (!canManageUsers) return <AccessDenied />;

// Backend - CORRECT
before_action :require_permission('users.manage'), only: [:create, :update, :destroy]
```

**❌ Never Test Roles**:
```typescript
// Frontend - FORBIDDEN
const isAdmin = currentUser?.roles?.includes('admin'); // NEVER DO THIS
const canManage = currentUser?.role === 'manager';     // NEVER DO THIS

// Backend - FORBIDDEN  
if user.roles.include?('admin') # NEVER DO THIS
```

### Test Data Management

**Database State**:
- Use database transactions for test isolation
- FactoryBot for consistent test data creation
- Database cleaning between test suites

**External Services**:
- VCR cassettes for HTTP interactions
- WebMock for request stubbing
- Mock Stripe/PayPal responses for payment testing

## CI/CD Integration

### Pipeline Configuration

The testing pipeline runs automatically on:
- Every commit to feature branches
- Pull requests to develop/main branches
- Nightly comprehensive test runs

### Quality Gates

Tests must pass these requirements:
- **Coverage Thresholds**: Backend 90%+, Frontend 75%+, Worker 80%+
- **Security Scanning**: No critical vulnerabilities
- **Performance**: Tests complete within defined timeouts
- **Pattern Compliance**: Permission-based access control only

### Pipeline Performance

Optimized for speed and reliability:
- **Parallel Execution**: 4x concurrent test processing
- **Selective Testing**: Only test changed services (60-80% time savings)
- **Enhanced Caching**: Multi-layer dependency and build caching
- **Performance Monitoring**: Automatic threshold enforcement

Target execution times:
- Backend tests: < 3 minutes
- Frontend tests: < 2 minutes  
- Worker tests: < 1 minute
- **Total pipeline**: < 8 minutes

## Test Environment Setup

### Local Development

```bash
# Start all services
./scripts/auto-dev.sh ensure

# Run specific test suites
cd server && bundle exec rspec                    # Backend tests
cd frontend && npm test                           # Frontend tests
cd worker && bundle exec rspec                    # Worker tests

# Run with coverage
./scripts/test-with-coverage.sh                   # All services with coverage
```

### Service Dependencies

**Required Services**:
- PostgreSQL database (test database isolation)
- Redis (for Sidekiq job testing)
- Mock external APIs (Stripe, PayPal, email services)

**Environment Variables**:
```bash
# Test environment configuration
RAILS_ENV=test
NODE_ENV=test
BACKEND_API_URL=http://localhost:3000
WORKER_TOKEN=test-worker-token-123
DATABASE_URL=postgresql://localhost/powernode_test
```

## Troubleshooting Common Issues

### Worker Service Tests

**DNS Resolution Errors**:
```ruby
# Fixed: Use localhost instead of test-backend.local
def build_api_url(path)
  base_url = 'http://localhost:3000'  # Not test-backend.local
  "#{base_url}#{path}"
end
```

**API Client Method Visibility**:
```ruby
# Fixed: Make HTTP methods public
class BackendApiClient
  # HTTP methods - made public for testing
  public
  
  def get(path, params = {})
    make_request(:get, path, params)
  end
end
```

### VCR Cassette Issues

**Regenerate Stale Cassettes**:
```bash
cd worker
rm -rf spec/vcr_cassettes/*
VCR_RECORD_MODE=once bundle exec rspec  # Re-record all interactions
```

**Filter Sensitive Data**:
```ruby
VCR.configure do |config|
  config.filter_sensitive_data('<API_KEY>') { ENV['API_KEY'] }
  config.filter_sensitive_data('<TOKEN>') { ENV['AUTH_TOKEN'] }
end
```

### Frontend Test Failures

**Mock API Services**:
```typescript
// Always mock external APIs in tests
jest.mock('../services/api', () => ({
  get: jest.fn(),
  post: jest.fn(),
  put: jest.fn(),
  delete: jest.fn()
}));
```

**Permission Testing Setup**:
```typescript
// Provide mock user with specific permissions
const renderWithPermissions = (permissions: string[]) => {
  const mockUser = { permissions, id: 1, email: 'test@example.com' };
  return render(<Component />, { user: mockUser });
};
```

## Test Maintenance

### Regular Maintenance Tasks

**Weekly**:
- Review test execution times and identify slow tests
- Update VCR cassettes for changed API endpoints
- Check test coverage reports for gaps

**Monthly**:
- Audit permission-based access control tests
- Review and update external service mocks
- Performance benchmark comparison

**Quarterly**:
- Complete security testing audit
- Test environment configuration review
- CI/CD pipeline performance optimization

### Adding New Tests

**Before Implementation**:
1. Write failing tests for new functionality
2. Ensure proper permission-based access control testing
3. Mock all external service dependencies
4. Add integration tests for cross-service functionality

**After Implementation**:
1. Verify all tests pass locally
2. Run full test suite with coverage reporting
3. Update documentation for new testing patterns
4. Submit PR with comprehensive test coverage

## Success Metrics

### Current Achievement

- **Backend**: 945+ passing tests with excellent coverage
- **Frontend**: 70%+ statement coverage with comprehensive auth/billing tests
- **Worker**: DNS resolution fixed, API client method visibility resolved
- **CI/CD**: Automated pipeline with performance optimization

### Continuous Improvement Goals

- Increase frontend coverage to 75%+ statements
- Achieve sub-8-minute total pipeline execution
- Maintain 99%+ test suite reliability
- Zero security vulnerabilities in test environment

## Conclusion

The Powernode testing strategy provides comprehensive coverage across all platform services while maintaining development velocity and deployment confidence. By following these patterns and procedures, the development team can ensure reliable, secure, and maintainable code that supports the platform's subscription management business requirements.

For specific implementation questions or troubleshooting assistance, refer to the detailed guides in the `/docs/testing/` directory or consult with the platform architecture team.