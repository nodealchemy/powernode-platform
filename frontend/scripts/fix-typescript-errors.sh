#!/bin/bash

# Comprehensive TypeScript error fix script
# This script addresses remaining compilation errors systematically

echo "🔧 Fixing TypeScript compilation errors..."

# Fix test-utils.tsx function ordering issue
echo "📝 Fixing test-utils.tsx function ordering..."
cd /home/rett/Drive/Projects/powernode-platform/frontend

# Move function declarations before usage in test-utils.tsx
sed -i '/\/\/ Mock user data for testing using enhanced types/,/};/c\
// Enhanced mock creation functions (moved up for proper hoisting)\
export const createMockPlan = (overrides: Partial<EnhancedPlan> = {}): EnhancedPlan => ({\
  id: "plan_basic",\
  name: "Basic Plan",\
  description: "Perfect for small teams",\
  price: 9.99,\
  price_cents: 999,\
  currency: "USD",\
  billing_cycle: "monthly",\
  trial_days: 14,\
  features: [\
    "Up to 5 users",\
    "Basic support",\
    "10GB storage",\
    "Standard integrations"\
  ],\
  active: true,\
  is_popular: false,\
  created_at: new Date().toISOString(),\
  updated_at: new Date().toISOString(),\
  ...overrides\
});\
\
export const createMockUser = (overrides: Partial<EnhancedUser> = {}): EnhancedUser => ({\
  id: "1",\
  email: "user@example.com",\
  first_name: "John",\
  last_name: "Doe",\
  roles: ["account.member"],\
  permissions: ["users.read", "plans.read"],\
  status: "active",\
  email_verified: true,\
  last_login_at: new Date().toISOString(),\
  created_at: new Date().toISOString(),\
  updated_at: new Date().toISOString(),\
  account: {\
    id: "acc_1",\
    name: "Test Company",\
    status: "active"\
  },\
  ...overrides\
});\
\
// Mock user data for testing using enhanced types\
export const mockUsers = {\
  regularUser: createMockUser({\
    id: "1",\
    email: "user@example.com",\
    first_name: "John",\
    last_name: "Doe",\
    roles: ["account.member"],\
    permissions: ["users.read", "plans.read"],\
    account: {\
      id: "acc_1",\
      name: "Test Company"\
    }\
  }),\
  adminUser: createMockUser({\
    id: "2",\
    email: "admin@example.com",\
    first_name: "Admin",\
    last_name: "User",\
    roles: ["system.admin"],\
    permissions: ["users.read", "users.manage", "admin.access", "plans.read", "billing.manage"],\
    account: {\
      id: "acc_2",\
      name: "Admin Company"\
    }\
  }),\
  billingManager: createMockUser({\
    id: "3",\
    email: "billing@example.com",\
    first_name: "Billing",\
    last_name: "Manager",\
    roles: ["billing.manager"],\
    permissions: ["users.read", "billing.read", "billing.manage", "invoices.create"],\
    account: {\
      id: "acc_3",\
      name: "Billing Company"\
    }\
  })\
};' src/test-utils.tsx

echo "✅ TypeScript error fixes applied"
echo "🧪 Running typecheck to validate..."

npm run typecheck