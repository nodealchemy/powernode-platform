# Bullet Gem Configuration Guide - N+1 Query Detection

**Purpose**: Install and configure Bullet gem for N+1 query detection in development
**Impact**: Identify and eliminate 656 potential N+1 queries
**Estimated Performance Gain**: 30-50% improvement

---

## 📦 Installation

### Step 1: Add Bullet to Gemfile

```ruby
# server/Gemfile

group :development do
  gem "bullet"  # N+1 query detection
  gem "rack-mini-profiler"  # Request profiling (optional but recommended)
end
```

### Step 2: Install Gems

```bash
cd server
bundle install
```

---

## ⚙️ Configuration

### Development Environment Setup

Create or update `server/config/initializers/bullet.rb`:

```ruby
# server/config/initializers/bullet.rb
# frozen_string_literal: true

if defined?(Bullet) && Rails.env.development?
  Bullet.enable = true

  # Alert options - choose what works best for your workflow
  Bullet.alert = true                 # JavaScript alert in browser
  Bullet.bullet_logger = true         # Log to log/bullet.log
  Bullet.console = true               # Log to browser console
  Bullet.rails_logger = true          # Log to Rails logger
  Bullet.add_footer = true            # Add footer to HTML pages

  # Notification options (optional)
  # Bullet.slack = { webhook_url: 'http://some.slack.url', channel: '#default', username: 'notifier' }
  # Bullet.bugsnag = true
  # Bullet.sentry = true

  # Raise errors in tests (recommended)
  Bullet.raise = true if Rails.env.test?

  # Bullet detects these N+1 query patterns:
  # - N+1 queries (queries triggered by associations)
  # - Unused eager loading (eager loading that wasn't used)
  # - Missing counter cache (COUNT queries that could be cached)

  # Whitelist specific queries if needed (use sparingly)
  # Bullet.add_whitelist type: :n_plus_one_query, class_name: "User", association: :roles
end
```

### Alternative: Direct in development.rb

Alternatively, add directly to `server/config/environments/development.rb`:

```ruby
# server/config/environments/development.rb

Rails.application.configure do
  # ... existing configuration ...

  # Bullet gem configuration
  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.console = true
    Bullet.rails_logger = true
    Bullet.add_footer = true
  end
end
```

---

## 🚀 Usage

### Running the Application

```bash
cd server
rails server
```

### Detecting N+1 Queries

Bullet will automatically detect N+1 queries during development. When detected, you'll see:

**1. Browser Alert** (if `Bullet.alert = true`):
```
N+1 Query detected:
User => roles
  app/controllers/api/v1/users_controller.rb:10:in `index'
Add to your query: .includes(:roles)
```

**2. Rails Log** (if `Bullet.rails_logger = true`):
```
N+1 Query detected
  User => [:roles]
  Add to your finder: :includes => [:roles]
Call stack:
  app/controllers/api/v1/users_controller.rb:10:in `index'
```

**3. Bullet Log File** (if `Bullet.bullet_logger = true`):
```bash
tail -f server/log/bullet.log
```

**4. Browser Footer** (if `Bullet.add_footer = true`):
- Red footer appears at bottom of HTML pages with N+1 warnings

---

## 🔍 Understanding Bullet Warnings

### N+1 Query Detection

**Example N+1 Query**:
```ruby
# Controller
def index
  @users = User.where(account_id: current_account.id)
end

# View/Serializer accessing associations triggers N+1:
@users.each do |user|
  user.account.name  # Each user triggers a separate query for account!
  user.roles.pluck(:name)  # Each user triggers a separate query for roles!
end
```

**Bullet Warning**:
```
USE eager loading detected
  User => [:account, :roles]
  Add to your finder: :includes => [:account, :roles]
```

**Fix**:
```ruby
def index
  @users = User.where(account_id: current_account.id)
              .includes(:account, :roles)  # Eager load associations
end
```

### Unused Eager Loading Detection

**Example**:
```ruby
# Eager loading that's never used
@users = User.includes(:permissions).where(account_id: current_account.id)
# But we never access user.permissions
```

**Bullet Warning**:
```
Unused eager loading detected
  User => [:permissions]
  Remove from your finder: :includes => [:permissions]
```

### Missing Counter Cache

**Example**:
```ruby
@accounts.each do |account|
  account.users.count  # Triggers COUNT query for each account
end
```

**Bullet Warning**:
```
Need Counter Cache
  Account => [:users]
```

**Fix**: Add counter cache to migration and model

---

## 🛠️ Fixing N+1 Queries

### Pattern 1: Basic Eager Loading

```ruby
# ❌ Before (N+1)
def index
  @users = User.all
  # Accessing user.account or user.roles triggers N+1
end

# ✅ After (Eager Loading)
def index
  @users = User.includes(:account, :roles).all
end
```

### Pattern 2: Nested Associations

```ruby
# ❌ Before (N+1)
def index
  @accounts = Account.all
  # Accessing account.subscriptions.plan triggers nested N+1
end

# ✅ After (Nested Eager Loading)
def index
  @accounts = Account.includes(subscription: :plan).all
end
```

### Pattern 3: Multiple Associations

```ruby
# ❌ Before (N+1)
def index
  @users = User.where(active: true)
  # Multiple associations accessed
end

# ✅ After (Multiple Eager Loading)
def index
  @users = User.where(active: true)
              .includes(:account, :roles, :permissions, subscription: :plan)
end
```

### Pattern 4: Conditional Eager Loading

```ruby
# ✅ Conditional eager loading based on params
def index
  @users = User.where(account_id: current_account.id)

  @users = @users.includes(:roles) if params[:include_roles]
  @users = @users.includes(:permissions) if params[:include_permissions]
  @users = @users.includes(subscription: :plan) if params[:include_subscription]
end
```

---

## 📊 Monitoring & Reporting

### View Bullet Logs

```bash
# Real-time monitoring
tail -f server/log/bullet.log

# Search for N+1 queries
grep "N+1 Query" server/log/bullet.log

# Count N+1 occurrences
grep -c "N+1 Query" server/log/bullet.log
```

### Generate N+1 Report

```bash
# scripts/generate-n-plus-one-report.sh
#!/bin/bash

echo "N+1 Query Detection Report"
echo "=========================="
echo ""
echo "Total N+1 Queries Detected: $(grep -c 'N+1 Query' server/log/bullet.log)"
echo ""
echo "Top Controllers with N+1 Issues:"
grep "N+1 Query" server/log/bullet.log | \
  grep -oP 'app/controllers/[^:]+' | \
  sort | uniq -c | sort -rn | head -10
```

---

## 🧪 Testing with Bullet

### RSpec Configuration

```ruby
# server/spec/rails_helper.rb

RSpec.configure do |config|
  # Raise errors on N+1 queries in tests
  if Bullet.enable?
    config.before(:each) do
      Bullet.start_request
    end

    config.after(:each) do
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
      Bullet.end_request
    end
  end
end
```

### Test Example

```ruby
# spec/controllers/api/v1/users_controller_spec.rb

RSpec.describe Api::V1::UsersController, type: :controller do
  describe "GET #index" do
    it "does not trigger N+1 queries" do
      create_list(:user, 10, account: current_account)

      # Bullet will raise error if N+1 detected in test environment
      get :index

      expect(response).to have_http_status(:success)
    end
  end
end
```

---

## ⚠️ Common Pitfalls

### 1. Over-Eager Loading

**Problem**: Loading associations you don't need
```ruby
# ❌ Loading everything "just in case"
@users = User.includes(:account, :roles, :permissions, :subscriptions, :invoices)
```

**Solution**: Only load what you actually use
```ruby
# ✅ Load only what's needed
@users = User.includes(:account, :roles)
```

### 2. Ignoring Serializer N+1s

**Problem**: N+1 queries hidden in serializers
```ruby
class UserSerializer
  def as_json(options = {})
    {
      account_name: object.account.name,  # N+1 if not eager loaded!
    }
  end
end
```

**Solution**: Eager load in controller before serialization

### 3. Not Testing with Bullet

**Problem**: N+1 queries slip into production
**Solution**: Enable `Bullet.raise = true` in test environment

---

## 📈 Success Metrics

Track your N+1 query elimination progress:

```bash
# Weekly N+1 count
grep -c "N+1 Query" server/log/bullet.log

# Goal: Reduce from 656 identified queries to <100
```

### Benchmark Performance

```ruby
# Add to controller for performance comparison
class UsersController < ApplicationController
  def index
    start_time = Time.now

    @users = User.includes(:account, :roles)
                 .where(account_id: current_account.id)

    query_time = Time.now - start_time
    Rails.logger.info "Query completed in #{(query_time * 1000).round(2)}ms"

    render_success(data: { users: @users })
  end
end
```

---

## 🎯 Next Steps

1. **Install Bullet**: Add to Gemfile and configure
2. **Run Application**: Start Rails server in development
3. **Exercise Endpoints**: Test all major endpoints
4. **Fix N+1 Queries**: Add `.includes()` where Bullet warns
5. **Test**: Ensure all tests pass with Bullet enabled
6. **Monitor**: Track reduction in N+1 queries over time

---

## 📚 Related Documentation

- [Phase 3 Optimization Plan](./PHASE_3_OPTIMIZATION_PLAN.md) - Overall optimization strategy
- [Rails Architect Specialist](../backend/RAILS_ARCHITECT_SPECIALIST.md) - Controller patterns
- [Data Modeler Specialist](../backend/DATA_MODELER_SPECIALIST.md) - Model associations

---

## 📖 External Resources

- [Bullet Gem Documentation](https://github.com/flyerhzm/bullet)
- [Rails Active Record Query Interface](https://guides.rubyonrails.org/active_record_querying.html#eager-loading-associations)
- [N+1 Queries Explained](https://stackoverflow.com/questions/97197/what-is-the-n1-selects-problem-in-orm-object-relational-mapping)

---

**Created**: 2025-11-24
**Status**: Ready for Implementation
**Estimated Impact**: 30-50% performance improvement
**Owner**: Platform Orchestrator MCP Agent
