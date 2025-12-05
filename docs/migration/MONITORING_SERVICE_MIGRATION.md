# Monitoring Service Migration Guide

**Version**: 1.0
**Date**: October 15, 2025
**Migration**: AiMonitoringService/AiComprehensiveMonitoringService → UnifiedMonitoringService

---

## 📋 Overview

This guide helps you migrate from deprecated monitoring services to the current standard `UnifiedMonitoringService`.

### Deprecated Services
- ❌ **AiMonitoringService** (will be removed in v2.0)
- ❌ **AiComprehensiveMonitoringService** (will be removed in v2.0)

### Current Standard
- ✅ **UnifiedMonitoringService** (use this)

---

## 🚀 Quick Migration

### Before (Deprecated)
```ruby
# DON'T USE - Deprecated
service = AiMonitoringService.new(account: current_user.account)
metrics = service.get_dashboard_metrics(time_range: 1.hour)
```

### After (Current Standard)
```ruby
# USE THIS - Current standard
service = UnifiedMonitoringService.new(account: current_user.account)
dashboard = service.get_dashboard(time_range: 1.hour)
```

---

## 📊 Feature Mapping

### AiMonitoringService → UnifiedMonitoringService

#### 1. Dashboard Metrics

**Before (AiMonitoringService)**:
```ruby
service = AiMonitoringService.new(account: account)
metrics = service.get_dashboard_metrics(time_range: 1.hour)

# Returns:
# {
#   overview: {...},
#   providers: [...],
#   alerts: [...],
#   system_health: {...},
#   cost_analysis: {...},
#   performance_trends: {...}
# }
```

**After (UnifiedMonitoringService)**:
```ruby
service = UnifiedMonitoringService.new(account: account)
dashboard = service.get_dashboard(time_range: 1.hour)

# Returns:
# {
#   timestamp: "2025-10-15T...",
#   time_range_seconds: 3600,
#   overview: {...},
#   health_score: 85,
#   components: {
#     system: {...},
#     providers: {...},
#     agents: {...},
#     workflows: {...},
#     conversations: {...},
#     costs: {...},
#     resources: {...}
#   }
# }
```

**Migration Steps**:
1. Change method name: `get_dashboard_metrics` → `get_dashboard`
2. Access components via `dashboard[:components][:providers]` instead of `dashboard[:providers]`
3. New feature: Health score available at `dashboard[:health_score]`

#### 2. Real-time Status

**Before (AiMonitoringService)**:
```ruby
service = AiMonitoringService.new(account: account)
status = service.get_realtime_status

# Returns provider-focused status
```

**After (UnifiedMonitoringService)**:
```ruby
service = UnifiedMonitoringService.new(account: account)
overview = service.get_system_overview

# Returns:
# {
#   status: 'excellent|good|fair|degraded|critical',
#   active_workflows: 5,
#   active_agents: 12,
#   total_executions_today: 150,
#   total_cost_today: 25.50,
#   avg_response_time: 1200,
#   success_rate: 95.5
# }
```

**Migration Steps**:
1. Change method: `get_realtime_status` → `get_system_overview`
2. Use `get_provider_metrics(time_range)` for provider-specific data

#### 3. Recording Executions

**Before (AiMonitoringService)**:
```ruby
service = AiMonitoringService.new(account: account)
service.record_execution(provider, 'agent_execution', {
  success: true,
  execution_time_ms: 1200,
  cost: 0.05
})
```

**After (UnifiedMonitoringService)**:
```ruby
# Automatic recording via BaseMonitoringService concern
# No manual recording needed - handled by service layer

# If manual recording needed:
service = UnifiedMonitoringService.new(account: account)
service.record_metric('execution', {
  provider_id: provider.id,
  success: true,
  duration_ms: 1200,
  cost: 0.05
})
```

**Migration Steps**:
1. Remove manual `record_execution` calls
2. Metrics are now automatically recorded by services
3. Use `record_metric` only for custom metrics

#### 4. Alerts

**Before (AiMonitoringService)**:
```ruby
service = AiMonitoringService.new(account: account)

# Trigger alert
service.trigger_alert('low_success_rate', provider, {
  message: "Success rate dropped to 75%",
  success_rate: 75
})

# Get active alerts
alerts = service.get_active_alerts
```

**After (UnifiedMonitoringService)**:
```ruby
service = UnifiedMonitoringService.new(account: account)

# Get alerts with filters
alerts = service.get_alerts(filters: { severity: 'high' })

# Check and trigger alerts automatically
service.check_and_trigger_alerts

# Returns:
# {
#   total_alerts: 5,
#   by_severity: { low: 2, medium: 2, high: 1 },
#   by_type: { low_success_rate: 3, high_latency: 2 },
#   recent_alerts: [...]
# }
```

**Migration Steps**:
1. Remove manual `trigger_alert` calls (now automatic)
2. Use `get_alerts(filters)` to retrieve alerts
3. Use `check_and_trigger_alerts` for periodic checks

---

### AiComprehensiveMonitoringService → UnifiedMonitoringService

#### 1. Unified Dashboard

**Before (AiComprehensiveMonitoringService)**:
```ruby
service = AiComprehensiveMonitoringService.new(account: account)
dashboard = service.get_unified_dashboard(
  time_range: 1.hour,
  components: ['system', 'providers', 'agents']
)
```

**After (UnifiedMonitoringService)**:
```ruby
service = UnifiedMonitoringService.new(account: account)
dashboard = service.get_dashboard(
  time_range: 1.hour,
  components: ['system', 'providers', 'agents']
)
```

**Migration Steps**:
1. Change method: `get_unified_dashboard` → `get_dashboard`
2. Same parameters and return structure

#### 2. Component Metrics

**Before (AiComprehensiveMonitoringService)**:
```ruby
service = AiComprehensiveMonitoringService.new(account: account)

# Providers
providers_data = service.get_all_providers_metrics(time_range: 1.hour)

# Agents
agents_data = service.get_all_agents_metrics(time_range: 1.hour)

# Workflows
workflows_data = service.get_all_workflows_metrics(time_range: 1.hour)
```

**After (UnifiedMonitoringService)**:
```ruby
service = UnifiedMonitoringService.new(account: account)

# Providers
providers_data = service.get_provider_metrics(time_range: 1.hour)

# Agents
agents_data = service.get_agent_metrics(time_range: 1.hour)

# Workflows
workflows_data = service.get_workflow_metrics(time_range: 1.hour)
```

**Migration Steps**:
1. Rename methods: `get_all_X_metrics` → `get_X_metrics`
2. Return structure is the same

#### 3. Health Scoring

**Before (AiComprehensiveMonitoringService)**:
```ruby
service = AiComprehensiveMonitoringService.new(account: account)
health = service.get_system_health_comprehensive

# Returns:
# {
#   overall_health: 85,
#   status: 'good',
#   components: {...},
#   alerts: {...},
#   recommendations: [...]
# }
```

**After (UnifiedMonitoringService)**:
```ruby
service = UnifiedMonitoringService.new(account: account)
health_score = service.calculate_health_score

# For detailed health:
dashboard = service.get_dashboard
status = dashboard[:overview][:status]

# Returns health score (0-100)
# Status: 'excellent', 'good', 'fair', 'degraded', 'critical'
```

**Migration Steps**:
1. Use `calculate_health_score` for numeric score
2. Use `get_system_overview` for status and components
3. Recommendations now in separate service (if needed)

---

## 🔄 Common Migration Patterns

### Pattern 1: Controller Integration

**Before**:
```ruby
class Api::V1::MonitoringController < ApplicationController
  def dashboard
    service = AiMonitoringService.new(account: current_user.account)
    metrics = service.get_dashboard_metrics(time_range: params[:time_range]&.to_i&.hours || 1.hour)

    render json: {
      success: true,
      data: metrics
    }
  end
end
```

**After**:
```ruby
class Api::V1::Ai::MonitoringController < ApplicationController
  def dashboard
    service = UnifiedMonitoringService.new(account: current_user.account)
    time_range = params[:time_range]&.to_i&.hours || 1.hour
    components = params[:components]&.split(',') || UnifiedMonitoringService::COMPONENTS

    dashboard = service.get_dashboard(
      time_range: time_range,
      components: components
    )

    render_success(data: dashboard)
  end
end
```

### Pattern 2: Background Job Monitoring

**Before**:
```ruby
class MonitoringJob < ApplicationJob
  def perform(account_id)
    account = Account.find(account_id)
    service = AiMonitoringService.new(account: account)

    # Record metrics
    providers = account.ai_providers
    providers.each do |provider|
      service.record_execution(provider, 'health_check', {
        success: provider.healthy?,
        execution_time_ms: 100
      })
    end
  end
end
```

**After**:
```ruby
class MonitoringJob < ApplicationJob
  def perform(account_id)
    account = Account.find(account_id)
    service = UnifiedMonitoringService.new(account: account)

    # Check and trigger alerts (automatic recording)
    service.check_and_trigger_alerts

    # Generate health report
    report = service.get_dashboard(time_range: 1.hour)

    # Store or notify based on health score
    if report[:health_score] < 70
      NotificationService.alert_low_health(account, report)
    end
  end
end
```

### Pattern 3: Real-time Monitoring

**Before**:
```ruby
class MonitoringChannel < ApplicationCable::Channel
  def subscribed
    stream_from "monitoring:#{current_user.account_id}"
    send_initial_status
  end

  def send_initial_status
    service = AiMonitoringService.new(account: current_user.account)
    status = service.get_realtime_status
    transmit(status)
  end
end
```

**After**:
```ruby
class Ai::MonitoringChannel < ApplicationCable::Channel
  def subscribed
    stream_from "ai_monitoring:#{current_user.account_id}"
    send_initial_dashboard
  end

  def send_initial_dashboard
    service = UnifiedMonitoringService.new(account: current_user.account)
    dashboard = service.get_dashboard(
      time_range: 5.minutes,
      components: ['system', 'providers']
    )
    transmit(dashboard)
  end

  # Periodic updates
  def request_update
    send_initial_dashboard
  end
end
```

---

## 🧪 Testing Your Migration

### Test Checklist

```ruby
# spec/services/monitoring_migration_spec.rb
RSpec.describe 'Monitoring Service Migration' do
  let(:account) { create(:account) }
  let(:service) { UnifiedMonitoringService.new(account: account) }

  describe 'dashboard metrics' do
    it 'returns dashboard data' do
      dashboard = service.get_dashboard(time_range: 1.hour)

      expect(dashboard).to have_key(:timestamp)
      expect(dashboard).to have_key(:overview)
      expect(dashboard).to have_key(:health_score)
      expect(dashboard).to have_key(:components)
    end

    it 'includes requested components' do
      dashboard = service.get_dashboard(
        time_range: 1.hour,
        components: ['system', 'providers']
      )

      expect(dashboard[:components]).to have_key(:system)
      expect(dashboard[:components]).to have_key(:providers)
      expect(dashboard[:components]).not_to have_key(:agents)
    end
  end

  describe 'health scoring' do
    it 'calculates health score' do
      score = service.calculate_health_score

      expect(score).to be_between(0, 100)
      expect(score).to be_a(Integer)
    end
  end

  describe 'system overview' do
    it 'returns system status' do
      overview = service.get_system_overview

      expect(overview).to have_key(:status)
      expect(overview).to have_key(:active_workflows)
      expect(overview).to have_key(:active_agents)
      expect(overview[:status]).to be_in(['excellent', 'good', 'fair', 'degraded', 'critical'])
    end
  end
end
```

---

## ⚠️ Breaking Changes

### Removed Features

1. **Manual Metric Recording**
   - Old: `service.record_execution(provider, type, result)`
   - New: Automatic via service layer
   - **Impact**: Remove manual recording code

2. **Redis Key Structure**
   - Old: `metrics:executions:#{provider_id}:#{timestamp}`
   - New: Abstracted by BaseMonitoringService
   - **Impact**: Don't access Redis directly

3. **Alert Key Format**
   - Old: `alert:#{provider_id}:#{type}:#{timestamp}`
   - New: Managed internally
   - **Impact**: Use `get_alerts` API instead

### Changed Behavior

1. **Time Range Handling**
   - Old: Integer minutes
   - New: ActiveSupport::Duration
   - **Migration**: `60` → `1.hour`

2. **Component Filtering**
   - Old: Not available
   - New: Specify components array
   - **Migration**: Add component filtering

3. **Health Scoring**
   - Old: Multiple scoring methods
   - New: Single `calculate_health_score`
   - **Migration**: Use unified scoring

---

## 📈 Performance Improvements

### What's Faster

1. **Component-based Loading**
   ```ruby
   # Only load what you need
   service.get_dashboard(
     time_range: 1.hour,
     components: ['system']  # Faster than loading all components
   )
   ```

2. **Cached Metrics**
   ```ruby
   # Metrics are cached via BaseMonitoringService
   # Subsequent calls within cache window are faster
   ```

3. **Optimized Queries**
   ```ruby
   # Better database query optimization
   # Includes eager loading and aggregation
   ```

---

## 🚨 Common Pitfalls

### Pitfall 1: Accessing Nested Data
```ruby
# ❌ WRONG - Old structure
providers = dashboard[:providers]

# ✅ CORRECT - New structure
providers = dashboard[:components][:providers]
```

### Pitfall 2: Time Range Format
```ruby
# ❌ WRONG - Integer minutes
service.get_dashboard(time_range: 60)

# ✅ CORRECT - ActiveSupport::Duration
service.get_dashboard(time_range: 1.hour)
```

### Pitfall 3: Manual Recording
```ruby
# ❌ WRONG - Manual recording no longer needed
service.record_execution(provider, 'agent', result)

# ✅ CORRECT - Automatic via service layer
# No action needed - metrics recorded automatically
```

---

## 📞 Support & Help

### Need Help?

1. **Check Documentation**
   - [Services Quick Reference](../platform/AI_ORCHESTRATION_SERVICES_QUICK_REFERENCE.md)
   - [Code Quality Evaluation](../platform/AI_ORCHESTRATION_CODE_QUALITY_EVALUATION.md)

2. **Example Implementation**
   - See: `app/controllers/api/v1/ai/monitoring_controller.rb`
   - Reference implementation using UnifiedMonitoringService

3. **Common Questions**

   **Q: Can I still use AiMonitoringService?**
   A: Yes, but it's deprecated. Migrate to UnifiedMonitoringService to avoid breaking changes in v2.0.

   **Q: What happens to my existing metrics?**
   A: Metrics are preserved. UnifiedMonitoringService reads from the same data sources.

   **Q: Do I need to update tests?**
   A: Yes, update test expectations to match new API structure.

---

## ✅ Migration Checklist

- [ ] Identify all usages of AiMonitoringService
- [ ] Identify all usages of AiComprehensiveMonitoringService
- [ ] Update controller actions
- [ ] Update background jobs
- [ ] Update real-time channels (if any)
- [ ] Update tests
- [ ] Verify metrics still work
- [ ] Remove deprecated service references
- [ ] Update documentation
- [ ] Deploy and monitor

---

**Migration Guide Version**: 1.0
**Last Updated**: October 15, 2025
**Maintained by**: Platform Architecture Team
