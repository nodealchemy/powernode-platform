# Frontend Test Engineer Specialist

**MCP Connection**: `frontend_test_engineer`
**Primary Role**: Frontend testing specialist implementing unit, integration, and E2E tests for React application

## Role & Responsibilities

The Frontend Test Engineer specializes in comprehensive testing strategies for React applications, ensuring code quality, user experience reliability, and integration testing across the Powernode subscription platform frontend.

### Core Areas
- **Unit Testing**: Component testing with Jest and React Testing Library
- **Integration Testing**: Feature-level testing and API integration
- **End-to-End Testing**: User workflow testing with Cypress
- **Performance Testing**: Frontend performance benchmarking
- **Accessibility Testing**: A11y compliance and screen reader testing
- **Visual Regression Testing**: UI consistency and visual change detection
- **Test Automation**: CI/CD pipeline integration and automated test execution

### Integration Points
- **Platform Architect**: Testing strategy coordination and quality gates
- **React Architect**: Component testing standards and architecture validation
- **UI Component Developer**: Component unit testing and design system validation
- **Backend Test Engineer**: Integration testing coordination and API contract testing
- **DevOps Engineer**: CI/CD pipeline integration and test automation

## Frontend Testing Architecture

### Testing Stack Configuration
```json
// package.json dependencies
{
  "devDependencies": {
    "@testing-library/react": "^13.4.0",
    "@testing-library/jest-dom": "^5.16.5",
    "@testing-library/user-event": "^14.4.3",
    "cypress": "^12.17.4",
    "jest": "^27.5.1",
    "jest-environment-jsdom": "^27.5.1",
    "msw": "^1.3.2",
    "@storybook/testing-library": "^0.2.2"
  }
}
```

### Jest Configuration
```javascript
// jest.config.js
module.exports = {
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['<rootDir>/src/setupTests.ts'],
  moduleNameMapping: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '\\.(css|less|scss|sass)$': 'identity-obj-proxy',
    '\\.(jpg|jpeg|png|gif|svg)$': '<rootDir>/src/__mocks__/fileMock.js'
  },
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.tsx',
    '!src/index.tsx',
    '!src/setupTests.ts'
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  }
};
```

## Unit Testing Patterns

### Component Testing Standards
```typescript
// Component test example: Button.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { Button } from '@/shared/components/ui/Button';
import { ThemeProvider } from '@/shared/contexts/ThemeContext';

const renderWithTheme = (ui: React.ReactElement) => {
  return render(
    <ThemeProvider>
      {ui}
    </ThemeProvider>
  );
};

describe('Button Component', () => {
  it('renders with correct text', () => {
    renderWithTheme(<Button>Click me</Button>);
    expect(screen.getByRole('button', { name: /click me/i })).toBeInTheDocument();
  });

  it('handles click events', () => {
    const handleClick = jest.fn();
    renderWithTheme(<Button onClick={handleClick}>Click me</Button>);
    
    fireEvent.click(screen.getByRole('button'));
    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('applies disabled state correctly', () => {
    renderWithTheme(<Button disabled>Disabled</Button>);
    const button = screen.getByRole('button');
    
    expect(button).toBeDisabled();
    expect(button).toHaveClass('opacity-50', 'cursor-not-allowed');
  });

  it('supports different variants', () => {
    renderWithTheme(<Button variant="primary">Primary</Button>);
    const button = screen.getByRole('button');
    
    expect(button).toHaveClass('bg-theme-primary');
  });
});
```

### Hook Testing Patterns
```typescript
// Hook test example: useAuth.test.ts
import { renderHook, act } from '@testing-library/react';
import { useAuth } from '@/features/auth/hooks/useAuth';
import { AuthProvider } from '@/features/auth/contexts/AuthContext';

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <AuthProvider>{children}</AuthProvider>
);

describe('useAuth Hook', () => {
  it('initializes with null user', () => {
    const { result } = renderHook(() => useAuth(), { wrapper });
    
    expect(result.current.currentUser).toBeNull();
    expect(result.current.isAuthenticated).toBe(false);
    expect(result.current.isLoading).toBe(false);
  });

  it('handles login successfully', async () => {
    const { result } = renderHook(() => useAuth(), { wrapper });
    
    await act(async () => {
      await result.current.login('test@example.com', 'password');
    });
    
    expect(result.current.isAuthenticated).toBe(true);
    expect(result.current.currentUser).toBeTruthy();
  });

  it('handles login errors', async () => {
    const { result } = renderHook(() => useAuth(), { wrapper });
    
    await act(async () => {
      try {
        await result.current.login('invalid@example.com', 'wrong');
      } catch (error) {
        expect(error).toBeDefined();
      }
    });
    
    expect(result.current.isAuthenticated).toBe(false);
  });
});
```

## Integration Testing

### API Integration Testing with MSW
```typescript
// API integration test: userApi.test.ts
import { rest } from 'msw';
import { setupServer } from 'msw/node';
import { userApi } from '@/features/users/services/userApi';

const server = setupServer(
  rest.get('/api/v1/users', (req, res, ctx) => {
    return res(ctx.json({
      success: true,
      data: [
        { id: '1', name: 'John Doe', email: 'john@example.com' }
      ]
    }));
  }),

  rest.post('/api/v1/users', (req, res, ctx) => {
    return res(ctx.json({
      success: true,
      data: { id: '2', name: 'Jane Doe', email: 'jane@example.com' }
    }));
  })
);

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('User API Integration', () => {
  it('fetches users successfully', async () => {
    const users = await userApi.getUsers();
    
    expect(users.success).toBe(true);
    expect(users.data).toHaveLength(1);
    expect(users.data[0].name).toBe('John Doe');
  });

  it('creates user successfully', async () => {
    const newUser = {
      name: 'Jane Doe',
      email: 'jane@example.com'
    };
    
    const result = await userApi.createUser(newUser);
    
    expect(result.success).toBe(true);
    expect(result.data.name).toBe(newUser.name);
  });
});
```

### Feature Integration Testing
```typescript
// Feature integration test: UserManagement.integration.test.tsx
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { UserManagement } from '@/features/users/components/UserManagement';
import { TestProviders } from '@/shared/test-utils/TestProviders';

describe('User Management Integration', () => {
  it('displays users and handles creation workflow', async () => {
    render(
      <TestProviders>
        <UserManagement />
      </TestProviders>
    );

    // Wait for users to load
    await waitFor(() => {
      expect(screen.getByText('John Doe')).toBeInTheDocument();
    });

    // Open create user modal
    fireEvent.click(screen.getByRole('button', { name: /create user/i }));
    
    // Fill form
    fireEvent.change(screen.getByLabelText(/name/i), {
      target: { value: 'New User' }
    });
    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: 'newuser@example.com' }
    });
    
    // Submit form
    fireEvent.click(screen.getByRole('button', { name: /save/i }));
    
    // Verify success
    await waitFor(() => {
      expect(screen.getByText('User created successfully')).toBeInTheDocument();
    });
  });
});
```

## End-to-End Testing with Cypress

### Cypress Configuration
```javascript
// cypress.config.js
const { defineConfig } = require('cypress');

module.exports = defineConfig({
  e2e: {
    baseUrl: 'http://localhost:3002',
    supportFile: 'cypress/support/e2e.ts',
    specPattern: 'cypress/e2e/**/*.cy.{js,jsx,ts,tsx}',
    video: true,
    screenshotOnRunFailure: true,
    viewportWidth: 1280,
    viewportHeight: 720,
    defaultCommandTimeout: 10000,
    requestTimeout: 10000,
    responseTimeout: 10000
  },
  component: {
    devServer: {
      framework: 'create-react-app',
      bundler: 'webpack'
    },
    specPattern: 'src/**/*.cy.{js,jsx,ts,tsx}'
  }
});
```

### E2E Test Examples
```typescript
// cypress/e2e/user-authentication.cy.ts
describe('User Authentication Flow', () => {
  beforeEach(() => {
    cy.visit('/');
  });

  it('allows user to login successfully', () => {
    cy.get('[data-cy=login-button]').click();
    cy.get('[data-cy=email-input]').type('admin@powernode.com');
    cy.get('[data-cy=password-input]').type('password123');
    cy.get('[data-cy=submit-button]').click();
    
    cy.url().should('include', '/dashboard');
    cy.get('[data-cy=user-menu]').should('contain', 'Admin User');
  });

  it('handles login errors gracefully', () => {
    cy.get('[data-cy=login-button]').click();
    cy.get('[data-cy=email-input]').type('invalid@example.com');
    cy.get('[data-cy=password-input]').type('wrongpassword');
    cy.get('[data-cy=submit-button]').click();
    
    cy.get('[data-cy=error-message]')
      .should('be.visible')
      .and('contain', 'Invalid credentials');
  });
});

// cypress/e2e/subscription-management.cy.ts
describe('Subscription Management', () => {
  beforeEach(() => {
    cy.login('admin@powernode.com', 'password123');
    cy.visit('/subscriptions');
  });

  it('creates new subscription successfully', () => {
    cy.get('[data-cy=create-subscription]').click();
    
    cy.get('[data-cy=plan-select]').select('Pro Plan');
    cy.get('[data-cy=billing-interval]').select('Monthly');
    cy.get('[data-cy=customer-email]').type('customer@example.com');
    
    cy.get('[data-cy=submit-subscription]').click();
    
    cy.get('[data-cy=success-notification]')
      .should('contain', 'Subscription created successfully');
      
    cy.get('[data-cy=subscription-list]')
      .should('contain', 'customer@example.com')
      .and('contain', 'Pro Plan');
  });
});
```

### Custom Cypress Commands
```typescript
// cypress/support/commands.ts
declare global {
  namespace Cypress {
    interface Chainable {
      login(email: string, password: string): Chainable<void>;
      logout(): Chainable<void>;
      seedDatabase(): Chainable<void>;
    }
  }
}

Cypress.Commands.add('login', (email: string, password: string) => {
  cy.request({
    method: 'POST',
    url: '/api/v1/auth/login',
    body: { email, password }
  }).then((response) => {
    window.localStorage.setItem('accessToken', response.body.data.accessToken);
    window.localStorage.setItem('refreshToken', response.body.data.refreshToken);
  });
});

Cypress.Commands.add('logout', () => {
  window.localStorage.removeItem('accessToken');
  window.localStorage.removeItem('refreshToken');
});

Cypress.Commands.add('seedDatabase', () => {
  cy.exec('cd $POWERNODE_ROOT/server && rails db:seed:test');
});
```

## Performance Testing

### Performance Test Setup
```typescript
// Performance testing utilities
export const measureComponentPerformance = (component: React.ComponentType) => {
  const start = performance.now();
  render(React.createElement(component));
  const end = performance.now();
  return end - start;
};

// Performance test example
describe('Performance Tests', () => {
  it('renders large data table within performance threshold', () => {
    const largeDataset = Array.from({ length: 1000 }, (_, i) => ({
      id: i,
      name: `User ${i}`,
      email: `user${i}@example.com`
    }));

    const renderTime = measureComponentPerformance(() => (
      <DataTable data={largeDataset} />
    ));

    expect(renderTime).toBeLessThan(100); // 100ms threshold
  });
});
```

## Accessibility Testing

### A11y Testing Setup
```typescript
// Accessibility testing with jest-axe
import { axe, toHaveNoViolations } from 'jest-axe';

expect.extend(toHaveNoViolations);

describe('Accessibility Tests', () => {
  it('has no accessibility violations', async () => {
    const { container } = render(<Button>Accessible Button</Button>);
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });
});
```

### Cypress A11y Testing
```typescript
// cypress/e2e/accessibility.cy.ts
describe('Accessibility Testing', () => {
  it('has no accessibility violations on dashboard', () => {
    cy.visit('/dashboard');
    cy.injectAxe();
    cy.checkA11y();
  });

  it('supports keyboard navigation', () => {
    cy.visit('/dashboard');
    cy.get('body').tab(); // Focus first element
    cy.focused().should('have.attr', 'data-cy', 'main-nav');
  });
});
```

## Test Data Management

### Test Fixtures
```typescript
// src/test-utils/fixtures.ts
export const userFixtures = {
  adminUser: {
    id: '1',
    name: 'Admin User',
    email: 'admin@powernode.com',
    role: 'system.admin',
    permissions: ['users.manage', 'billing.manage', 'admin.access']
  },
  
  regularUser: {
    id: '2',
    name: 'Regular User',
    email: 'user@powernode.com', 
    role: 'account.member',
    permissions: ['billing.read', 'users.read']
  }
};

export const subscriptionFixtures = {
  activeSubscription: {
    id: '1',
    status: 'active',
    plan: 'Pro Plan',
    billingInterval: 'monthly',
    nextBillingDate: '2024-02-01'
  }
};
```

### Test Providers
```typescript
// src/test-utils/TestProviders.tsx
import { ReactNode } from 'react';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ThemeProvider } from '@/shared/contexts/ThemeContext';
import { AuthProvider } from '@/features/auth/contexts/AuthContext';

interface TestProvidersProps {
  children: ReactNode;
  initialUser?: User | null;
}

export const TestProviders = ({ children, initialUser = null }: TestProvidersProps) => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false }
    }
  });

  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <ThemeProvider>
          <AuthProvider initialUser={initialUser}>
            {children}
          </AuthProvider>
        </ThemeProvider>
      </BrowserRouter>
    </QueryClientProvider>
  );
};
```

## CI/CD Integration

### GitHub Actions Test Workflow
```yaml
# .github/workflows/frontend-tests.yml
name: Frontend Tests
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
        cache-dependency-path: frontend/package-lock.json
    
    - name: Install dependencies
      run: cd $POWERNODE_ROOT/frontend && npm ci
    
    - name: Run unit tests
      run: cd $POWERNODE_ROOT/frontend && npm test -- --coverage --watchAll=false
    
    - name: Run linting
      run: cd $POWERNODE_ROOT/frontend && npm run lint
    
    - name: Run type checking
      run: cd $POWERNODE_ROOT/frontend && npm run type-check
    
    - name: Upload coverage reports
      uses: codecov/codecov-action@v3
      with:
        file: ./frontend/coverage/lcov.info
        flags: frontend

  e2e-tests:
    runs-on: ubuntu-latest
    needs: test
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
    
    - name: Install dependencies
      run: cd $POWERNODE_ROOT/frontend && npm ci
    
    - name: Build application
      run: cd $POWERNODE_ROOT/frontend && npm run build
    
    - name: Start application
      run: cd $POWERNODE_ROOT/frontend && npm start &
    
    - name: Wait for application
      run: npx wait-on http://localhost:3002
    
    - name: Run Cypress tests
      run: cd $POWERNODE_ROOT/frontend && npx cypress run
```

## Quick Reference

### Essential Test Commands
```bash
# Unit and integration tests
cd $POWERNODE_ROOT/frontend && npm test                    # Run all tests
cd $POWERNODE_ROOT/frontend && npm test -- --coverage     # Run with coverage
cd $POWERNODE_ROOT/frontend && npm test -- --watch        # Watch mode
cd $POWERNODE_ROOT/frontend && npm test Button.test.tsx   # Run specific test

# End-to-end tests
cd $POWERNODE_ROOT/frontend && npx cypress open           # Interactive mode
cd $POWERNODE_ROOT/frontend && npx cypress run            # Headless mode
cd $POWERNODE_ROOT/frontend && npx cypress run --spec "cypress/e2e/auth.cy.ts"  # Specific spec

# Code quality
cd $POWERNODE_ROOT/frontend && npm run lint               # ESLint
cd $POWERNODE_ROOT/frontend && npm run type-check         # TypeScript check
cd $POWERNODE_ROOT/frontend && npm run test:a11y          # Accessibility tests
```

### Test File Patterns
- **Unit Tests**: `ComponentName.test.tsx`, `hookName.test.ts`
- **Integration Tests**: `FeatureName.integration.test.tsx`
- **E2E Tests**: `user-workflow.cy.ts`
- **Performance Tests**: `ComponentName.perf.test.tsx`

### Testing Standards
- **Coverage Requirements**: 80% minimum for statements, branches, functions, lines
- **Test Naming**: Descriptive test names following "should do X when Y" pattern
- **Data Attributes**: Use `data-cy` attributes for Cypress selectors
- **Accessibility**: All interactive elements must pass axe-core validation
- **Performance**: Component render time < 100ms for standard components

### Mock Patterns
```typescript
// API mocking with MSW
const server = setupServer(
  rest.get('/api/v1/endpoint', (req, res, ctx) => {
    return res(ctx.json({ success: true, data: mockData }));
  })
);

// Module mocking
jest.mock('@/features/auth/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: mockUser,
    isAuthenticated: true,
    login: jest.fn(),
    logout: jest.fn()
  })
}));
```

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**