# frozen_string_literal: true

# System Administration Articles
# Documentation for system-level features

puts "  ⚙️ Creating System Administration articles..."

system_cat = KnowledgeBase::Category.find_by!(slug: "system-administration")
author = User.find_by!(email: "admin@powernode.org")

# Article 33: System Services Management
services_content = <<~MARKDOWN
# System Services Management

Monitor and manage Powernode's system services for optimal performance and reliability.

## Services Dashboard

### Overview

Navigate to **Settings > System > Services**:

```
┌─────────────────────────────────────────────┐
│  System Services                            │
├─────────────────────────────────────────────┤
│  Service     │  Status  │  Health  │ Action │
├──────────────┼──────────┼──────────┼────────┤
│  API Server  │  Running │  ✅ Good │ Config │
│  Background  │  Running │  ✅ Good │ Config │
│  Scheduler   │  Running │  ✅ Good │ Config │
│  Database    │  Running │  ✅ Good │ Stats  │
│  Cache       │  Running │  ✅ Good │ Clear  │
└──────────────┴──────────┴──────────┴────────┘
```

### Service Status

| Status | Description |
|--------|-------------|
| Running | Service operational |
| Degraded | Partial functionality |
| Stopped | Service not running |
| Error | Service failed |

## Available Services

### Core Services

| Service | Purpose |
|---------|---------|
| **API Server** | Handles API requests |
| **Background Jobs** | Async task processing |
| **Scheduler** | Scheduled task execution |
| **Database** | Data persistence |
| **Cache** | Performance caching |

### Optional Services

| Service | Purpose |
|---------|---------|
| **AI Processing** | AI agent execution |
| **File Storage** | File upload handling |
| **Search Index** | Full-text search |
| **Email Delivery** | Notification sending |

## Service Configuration

### Configuration Options

```yaml
Service Settings:
  API Server:
    Port: 3000
    Workers: 4
    Timeout: 30s
    Rate Limiting: enabled

  Background Jobs:
    Concurrency: 10
    Queues:
      - default
      - mailers
      - ai_processing
    Retry Attempts: 3
```

### Environment Variables

Configure via environment:
```bash
RAILS_MAX_THREADS=5
SIDEKIQ_CONCURRENCY=10
DATABASE_POOL=25
REDIS_URL=redis://localhost:6379
```

## Health Monitoring

### Health Checks

Automatic health monitoring:
- Service availability
- Response times
- Error rates
- Resource usage

### Health Endpoints

```bash
# Check overall health
GET /health

# Check specific service
GET /health/database
GET /health/cache
GET /health/background_jobs
```

### Alerts

Configure alerts for:
- Service downtime
- High error rates
- Slow response times
- Resource exhaustion

## Maintenance Mode

### Enabling Maintenance

Temporarily disable access:
1. Navigate to **System > Maintenance**
2. Configure message
3. Set allowed IPs (admin access)
4. Enable maintenance mode

### Maintenance Page

```yaml
Maintenance Configuration:
  Enabled: true
  Message: "System maintenance in progress"
  Expected Duration: "30 minutes"
  Allowed IPs:
    - 10.0.0.0/8
    - 192.168.1.0/24
```

## Database Management

### Database Stats

View database metrics:
- Connection pool usage
- Query performance
- Table sizes
- Index health

### Backup Management

Configure backups:
```yaml
Backup Settings:
  Frequency: Daily
  Retention: 30 days
  Storage: S3
  Encryption: AES-256
```

---

For audit logging, see [Audit Logs and Monitoring](/kb/audit-logs-monitoring).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "system-services-management") do |article|
  article.title = "System Services Management"
  article.category = system_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Monitor and manage Powernode's system services including API, background jobs, database, and maintenance mode."
  article.content = services_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ System Services Management"

# Article 34: Audit Logs and Monitoring
audit_logs_content = <<~MARKDOWN
# Audit Logs and Monitoring

Track all system activity with comprehensive audit logging for security and compliance.

## Audit Log Overview

### What's Logged

All significant events:
- User authentication (login/logout)
- Permission changes
- Data modifications
- Configuration changes
- API access
- Security events

### Accessing Logs

Navigate to **Settings > Audit Logs**:
- Filterable log list
- Detailed event view
- Export capabilities

## Log Structure

### Event Format

```yaml
Audit Log Entry:
  ID: log_01HQ7EXAMPLE
  Timestamp: 2024-01-15T10:30:45Z
  Event Type: user.login
  Actor:
    ID: usr_01HQ7EXAMPLE
    Email: admin@company.com
    IP: 192.168.1.100
  Resource:
    Type: session
    ID: sess_01HQ7EXAMPLE
  Details:
    Browser: Chrome 120
    OS: macOS
    Location: San Francisco, CA
  Status: success
```

### Event Types

| Category | Events |
|----------|--------|
| **Authentication** | login, logout, 2fa_verify, password_change |
| **Users** | create, update, delete, permission_change |
| **Billing** | subscription_change, payment, refund |
| **Data** | create, update, delete, export |
| **System** | config_change, service_restart |
| **Security** | failed_login, suspicious_activity |

## Filtering Logs

### Available Filters

| Filter | Options |
|--------|---------|
| Date Range | Custom dates |
| Event Type | Category selection |
| Actor | User filter |
| Resource | Type/ID filter |
| Status | Success/failure |
| IP Address | Source filter |

### Search Examples

```yaml
Search Queries:
  # All login failures
  event_type: authentication.login
  status: failure

  # Permission changes today
  event_type: user.permission_change
  date: today

  # All actions by specific user
  actor.email: admin@company.com
```

## User Activity Tracking

### Per-User Activity

View individual user activity:
1. Navigate to **Settings > Team**
2. Select user
3. Click **Activity Log**

### Activity Summary

```yaml
User Activity: admin@company.com
  Last 30 Days:
    Logins: 45
    Changes: 128
    Exports: 5
    Failed Actions: 2

  Recent Events:
    - Updated subscription settings
    - Changed user permissions
    - Exported customer data
```

## Compliance Reporting

### Pre-Built Reports

| Report | Purpose |
|--------|---------|
| Access Report | Who accessed what |
| Change Report | What was modified |
| Security Report | Security events |
| Export Report | Data exports |

### Custom Reports

Create compliance reports:
1. Navigate to **Audit Logs > Reports**
2. Configure parameters
3. Generate report
4. Export or schedule

## Log Retention

### Retention Settings

```yaml
Log Retention:
  Standard Events: 90 days
  Security Events: 1 year
  Compliance Events: 7 years
  Archive: S3 bucket
```

### Export and Archive

Export logs for long-term storage:
- JSON format
- CSV format
- Compressed archives
- Automated exports

## Alert Configuration

### Security Alerts

Configure alerts for:

```yaml
Alert Rules:
  - name: Multiple Failed Logins
    condition: failed_login > 5 in 15 minutes
    action: notify_security

  - name: Unusual Access
    condition: login from new_country
    action: email_user + log_security

  - name: Bulk Data Export
    condition: export_size > 10000 records
    action: notify_admin
```

### Notification Channels

- Email
- Slack
- PagerDuty
- Webhook

---

For security configuration, see [Security Configuration Guide](/kb/security-configuration-guide).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "audit-logs-monitoring") do |article|
  article.title = "Audit Logs and Monitoring"
  article.category = system_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Track all system activity with comprehensive audit logging for authentication, data changes, and compliance reporting."
  article.content = audit_logs_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Audit Logs and Monitoring"

# Article 35: Background Workers and Jobs
workers_content = <<~MARKDOWN
# Background Workers and Jobs

Monitor and manage background workers that process asynchronous tasks like email delivery, data processing, and scheduled jobs.

## Workers Overview

### What Are Background Workers?

Background workers handle:
- **Asynchronous Processing** - Tasks that don't need immediate response
- **Scheduled Jobs** - Recurring tasks on schedules
- **Queue Processing** - Managing work queues
- **Long-Running Tasks** - Operations taking seconds to minutes

### Accessing Workers

Navigate to **System > Workers** to:
- View worker status
- Monitor job queues
- Manage job execution
- Review job history

## Workers Dashboard

```
┌─────────────────────────────────────────────────────┐
│  Background Workers                  [Settings]     │
├─────────────────────────────────────────────────────┤
│  Active Workers: 5          Jobs Processing: 12     │
│  Queue Depth: 45            Failed (24h): 3         │
├─────────────────────────────────────────────────────┤
│  Worker     │ Status  │ Processing │ Processed     │
├─────────────┼─────────┼────────────┼───────────────┤
│  worker-01  │ ✅ Busy  │ 3 jobs     │ 1,234         │
│  worker-02  │ ✅ Busy  │ 4 jobs     │ 1,189         │
│  worker-03  │ ✅ Idle  │ 0 jobs     │ 1,156         │
│  worker-04  │ ✅ Busy  │ 5 jobs     │ 987           │
│  worker-05  │ ⚠️ Quiet │ 0 jobs     │ 654           │
└─────────────┴─────────┴────────────┴───────────────┘
```

## Job Queues

### Queue Types

| Queue | Priority | Use Case |
|-------|----------|----------|
| **default** | Normal | General background tasks |
| **critical** | High | Time-sensitive operations |
| **mailers** | Normal | Email delivery |
| **ai_processing** | Low | AI operations |
| **reports** | Low | Report generation |
| **webhooks** | High | Webhook delivery |

### Queue Status

```yaml
Queue Status:
  critical:
    Enqueued: 5
    Processing: 3
    Latency: 0.2s

  default:
    Enqueued: 28
    Processing: 8
    Latency: 1.5s

  mailers:
    Enqueued: 12
    Processing: 4
    Latency: 0.8s

  ai_processing:
    Enqueued: 15
    Processing: 2
    Latency: 5.2s
```

### Queue Management

```yaml
Queue Actions:
  - Pause Queue: Stop processing new jobs
  - Resume Queue: Continue processing
  - Clear Queue: Remove all pending jobs
  - Retry Failed: Re-enqueue failed jobs
  - Prioritize: Move jobs to front
```

## Job Types

### Common Job Types

| Job Type | Description | Typical Duration |
|----------|-------------|-----------------|
| **EmailDeliveryJob** | Send emails | < 5s |
| **WebhookDeliveryJob** | Send webhook | < 10s |
| **ReportGenerationJob** | Generate reports | 30s - 5m |
| **DataExportJob** | Export user data | 1m - 30m |
| **AIProcessingJob** | AI operations | 5s - 2m |
| **SubscriptionRenewalJob** | Process renewals | < 10s |
| **CleanupJob** | Data cleanup | 1m - 10m |

### Job Details

```yaml
Job: EmailDeliveryJob
  ID: job_01HQ7EXAMPLE
  Status: Completed
  Queue: mailers

  Arguments:
    user_id: "usr_01HQ7..."
    template: "welcome"
    locale: "en"

  Timing:
    Enqueued: 2024-01-15 10:30:00
    Started: 2024-01-15 10:30:02
    Completed: 2024-01-15 10:30:03
    Duration: 1.2s

  Attempts: 1
  Result: Success
```

## Monitoring

### Real-Time Metrics

```yaml
Worker Metrics:
  Throughput:
    Current: 45 jobs/min
    Peak (24h): 120 jobs/min
    Average: 35 jobs/min

  Latency:
    Queue Wait: 1.5s avg
    Processing: 3.2s avg
    Total: 4.7s avg

  Success Rate:
    Last Hour: 99.2%
    Last 24h: 98.8%
    Last 7d: 99.1%
```

### Failed Jobs

```yaml
Failed Jobs:
  Total Failed (24h): 15
  Pending Retry: 8
  Dead Jobs: 7

  Recent Failures:
    - WebhookDeliveryJob
      Error: Connection timeout
      Retries: 3/3
      Action: Dead (manual review)

    - AIProcessingJob
      Error: Rate limit exceeded
      Retries: 2/5
      Action: Scheduled retry in 5m
```

### Alerts

```yaml
Alert Configuration:
  - name: High Queue Depth
    condition: queue_depth > 100
    duration: 5m
    notify: ops-team

  - name: Worker Down
    condition: active_workers < 3
    notify: ops-team

  - name: High Failure Rate
    condition: failure_rate > 5%
    duration: 15m
    notify: devops-team

  - name: Long Queue Latency
    condition: latency > 60s
    notify: ops-team
```

## Job Management

### Viewing Jobs

Filter and search jobs:

```yaml
Search Filters:
  - Queue: default, critical, mailers, etc.
  - Status: pending, processing, completed, failed
  - Job Type: EmailDeliveryJob, etc.
  - Time Range: Last hour, day, week
  - User/Account: Specific user's jobs
```

### Job Actions

| Action | Description |
|--------|-------------|
| **Retry** | Re-enqueue failed job |
| **Delete** | Remove from queue |
| **View Details** | See full job info |
| **Download Logs** | Export job logs |

### Bulk Operations

```yaml
Bulk Actions:
  - Retry All Failed: Re-enqueue all failed jobs
  - Delete Old: Remove completed jobs older than X days
  - Clear Dead: Remove dead jobs after review
  - Pause All: Stop all queue processing
```

## Scheduled Jobs

### Cron Jobs

View and manage scheduled tasks:

```yaml
Scheduled Jobs:
  - name: Daily Report Generation
    cron: "0 6 * * *"  # 6 AM daily
    next_run: 2024-01-16 06:00:00
    status: Active

  - name: Subscription Renewals
    cron: "0 * * * *"  # Every hour
    next_run: 2024-01-15 11:00:00
    status: Active

  - name: Data Cleanup
    cron: "0 2 * * 0"  # Sunday 2 AM
    next_run: 2024-01-21 02:00:00
    status: Active
```

### Schedule Management

```yaml
Schedule Actions:
  - Enable/Disable: Toggle scheduled job
  - Run Now: Trigger immediate execution
  - Edit Schedule: Modify cron expression
  - View History: See past executions
```

## Configuration

### Worker Configuration

```yaml
Worker Settings:
  Concurrency: 10  # Jobs per worker
  Queues:
    - critical (priority: 6)
    - webhooks (priority: 5)
    - default (priority: 4)
    - mailers (priority: 3)
    - ai_processing (priority: 2)
    - reports (priority: 1)

  Timeouts:
    Default: 300s
    AI Jobs: 600s
    Reports: 1800s

  Retries:
    Default: 5
    Webhooks: 10
    Backoff: exponential
```

### Resource Limits

```yaml
Resource Configuration:
  Memory Limit: 512MB per job
  CPU Limit: 1 core per job

  Queue Limits:
    critical: 1000 max
    default: 5000 max
    ai_processing: 500 max
```

## Troubleshooting

### Common Issues

**Jobs Stuck in Queue**
```yaml
Checklist:
  - Verify workers are running
  - Check queue is not paused
  - Review worker capacity
  - Look for blocking jobs
```

**High Failure Rate**
```yaml
Checklist:
  - Review error messages
  - Check external dependencies
  - Verify resource availability
  - Review rate limits
```

**Memory Issues**
```yaml
Checklist:
  - Monitor job memory usage
  - Implement batch processing
  - Increase worker memory
  - Optimize job implementation
```

### Debug Mode

```yaml
Debug Options:
  - Enable verbose logging
  - Capture job arguments
  - Record timing details
  - Trace external calls
```

## Best Practices

### Job Design

1. **Keep Jobs Small**
   - Break large tasks into smaller jobs
   - Use job chaining for sequences
   - Implement checkpointing for long jobs

2. **Make Jobs Idempotent**
   - Safe to retry without side effects
   - Check for existing results
   - Use unique identifiers

3. **Handle Failures Gracefully**
   - Implement proper error handling
   - Use exponential backoff
   - Set reasonable retry limits

### Operations

1. **Monitor Continuously**
   - Watch queue depths
   - Track failure rates
   - Set up alerts

2. **Scale Appropriately**
   - Add workers for high load
   - Use queue priorities
   - Plan for peak times

## Related Articles

- [System Services Management](/kb/system-services-management)
- [Audit Logs and Monitoring](/kb/audit-logs-monitoring)
- [System Maintenance Mode](/kb/system-maintenance-mode)

---

Need help with workers? Contact ops-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "background-workers-jobs") do |article|
  article.title = "Background Workers and Jobs"
  article.category = system_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Monitor and manage background workers for asynchronous task processing, job queues, scheduled jobs, and failure handling."
  article.content = workers_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Background Workers and Jobs"

# Article 36: System Maintenance Mode
maintenance_mode_content = <<~MARKDOWN
# System Maintenance Mode

Enable maintenance mode to safely perform system updates, migrations, and maintenance tasks while informing users.

## Maintenance Overview

### What is Maintenance Mode?

Maintenance mode:
- **Restricts Access** to the platform temporarily
- **Displays Message** to inform users
- **Allows Admins** to continue working
- **Protects Data** during updates

### When to Use

| Scenario | Recommended |
|----------|-------------|
| Database migrations | Yes |
| Major version upgrades | Yes |
| Security patches | Sometimes |
| Configuration changes | No |
| Adding features | No |

## Accessing Maintenance Settings

Navigate to **Administration > Maintenance** to:
- Enable/disable maintenance mode
- Configure maintenance message
- Set allowed IP addresses
- Schedule maintenance windows

## Maintenance Dashboard

```
┌─────────────────────────────────────────────────────┐
│  System Maintenance                                  │
├─────────────────────────────────────────────────────┤
│  Current Status: ✅ Normal Operation                │
│                                                     │
│  Last Maintenance: 2024-01-10 02:00 - 02:45 UTC    │
│  Next Scheduled: 2024-01-20 02:00 UTC (tentative)  │
├─────────────────────────────────────────────────────┤
│  [Enable Maintenance]  [Schedule Maintenance]       │
└─────────────────────────────────────────────────────┘
```

## Enabling Maintenance Mode

### Quick Enable

For immediate maintenance:

1. Navigate to **Administration > Maintenance**
2. Click **Enable Maintenance**
3. Configure settings:

```yaml
Maintenance Configuration:
  Message: |
    We're performing scheduled maintenance to improve
    your experience. We'll be back shortly!

  Expected Duration: 30 minutes

  Allowed Access:
    IPs:
      - 10.0.0.0/8  # Internal network
      - 192.168.1.100  # Admin workstation
    Users:
      - admin@company.com
      - ops@company.com
```

4. Click **Activate**

### Scheduled Maintenance

Plan maintenance in advance:

```yaml
Scheduled Maintenance:
  Start: 2024-01-20 02:00 UTC
  End: 2024-01-20 04:00 UTC

  Pre-Notification:
    - 7 days before: Email all users
    - 1 day before: Dashboard banner
    - 1 hour before: Email reminder

  Message: |
    Scheduled maintenance on January 20, 2024
    from 2:00 AM - 4:00 AM UTC.

    During this time, the platform will be unavailable.

  Auto-Disable: true  # Automatically end at scheduled time
```

### Via API

```bash
# Enable maintenance mode
curl -X POST https://api.powernode.org/api/v1/admin/maintenance/enable \\
  -H "Authorization: Bearer ADMIN_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "message": "System maintenance in progress",
    "expected_duration_minutes": 60,
    "allowed_ips": ["10.0.0.0/8"]
  }'

# Disable maintenance mode
curl -X POST https://api.powernode.org/api/v1/admin/maintenance/disable \\
  -H "Authorization: Bearer ADMIN_API_KEY"
```

## Maintenance Page

### Default Page

Users see a friendly maintenance page:

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│           🔧 Under Maintenance                      │
│                                                     │
│  We're performing scheduled maintenance to improve  │
│  your experience. We'll be back shortly!            │
│                                                     │
│  Expected completion: ~30 minutes                   │
│                                                     │
│  Questions? Contact support@powernode.org          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Customization

```yaml
Page Customization:
  Title: "Maintenance in Progress"
  Logo: /assets/logo.png
  Background Color: #f8f9fa
  Text Color: #333333

  Message:
    Header: "We'll be right back!"
    Body: "We're making some improvements..."
    Footer: "Thank you for your patience."

  Contact:
    Email: support@powernode.org
    Status Page: https://status.powernode.org

  Countdown:
    Enabled: true
    End Time: 2024-01-20T04:00:00Z
```

## Admin Access During Maintenance

### Bypassing Maintenance

Authorized users can access during maintenance:

```yaml
Access Methods:
  IP Allowlist:
    - Add admin IPs to allowed list
    - Include VPN ranges
    - Document all allowed IPs

  User Allowlist:
    - Specific user accounts
    - Admin role users
    - Ops team members

  Secret URL:
    - /admin?bypass=SECRET_TOKEN
    - Use for emergency access
    - Rotate token after use
```

### Admin Indicator

When accessing during maintenance:

```
┌─────────────────────────────────────────────────────┐
│  ⚠️ MAINTENANCE MODE ACTIVE                         │
│  Users see maintenance page. You have admin access. │
│  [Disable Maintenance]                              │
└─────────────────────────────────────────────────────┘
```

## Health Checks

### During Maintenance

Configure health check behavior:

```yaml
Health Check Configuration:
  During Maintenance:
    /health: Returns 503 (maintenance)
    /health/admin: Returns 200 (for monitoring)
    /health/db: Normal response

  Load Balancer:
    - Remove from rotation during maintenance
    - Keep monitoring endpoint active
    - Restore after maintenance
```

### Status Page Integration

Update external status page:

```yaml
Status Page Updates:
  Provider: statuspage.io

  On Enable:
    - Create incident
    - Set component to maintenance
    - Post update

  On Disable:
    - Resolve incident
    - Set component to operational
    - Post completion message
```

## Notifications

### User Notifications

```yaml
Notification Settings:
  Pre-Maintenance:
    - 7 days: Email digest subscribers
    - 1 day: All active users
    - 1 hour: Dashboard banner
    - 15 min: Active sessions popup

  During:
    - Maintenance page for all visitors
    - API returns 503 with message

  Post-Maintenance:
    - Email: "We're back online"
    - Dashboard: "Maintenance completed"
```

### Internal Notifications

```yaml
Team Notifications:
  Channels:
    - Slack: #ops-maintenance
    - Email: ops@company.com
    - PagerDuty: Low priority

  Events:
    - Maintenance started
    - Maintenance extended
    - Maintenance completed
    - Issues during maintenance
```

## Maintenance Checklist

### Before Maintenance

```yaml
Pre-Maintenance Checklist:
  ✅ Notify users (7 days, 1 day, 1 hour)
  ✅ Create database backup
  ✅ Document rollback procedure
  ✅ Verify admin access works
  ✅ Update status page
  ✅ Notify support team
  ✅ Prepare maintenance scripts
  ✅ Test in staging first
```

### During Maintenance

```yaml
During Maintenance:
  ✅ Verify maintenance page is showing
  ✅ Confirm API returning 503
  ✅ Execute maintenance tasks
  ✅ Monitor for errors
  ✅ Document any issues
  ✅ Test functionality before re-enabling
```

### After Maintenance

```yaml
Post-Maintenance Checklist:
  ✅ Disable maintenance mode
  ✅ Verify all services running
  ✅ Test critical functionality
  ✅ Update status page
  ✅ Send completion notification
  ✅ Monitor for issues
  ✅ Document maintenance in log
```

## Emergency Procedures

### Extending Maintenance

```yaml
Extension Process:
  1. Update expected end time
  2. Post update to status page
  3. Notify users of extension
  4. Update maintenance message
```

### Rolling Back

```yaml
Rollback Procedure:
  1. Stop maintenance tasks
  2. Restore from backup if needed
  3. Verify data integrity
  4. Disable maintenance mode
  5. Monitor closely
  6. Document incident
```

### Emergency Maintenance

For urgent issues:

```yaml
Emergency Maintenance:
  1. Enable maintenance immediately
  2. Post incident to status page
  3. Notify key stakeholders
  4. Address critical issue
  5. Communicate frequently
  6. Disable when resolved
  7. Post-incident review
```

## Best Practices

### Planning

1. **Schedule Wisely**
   - Choose low-traffic times
   - Avoid business-critical periods
   - Consider timezone impacts

2. **Communicate Early**
   - Give adequate notice
   - Be clear about impact
   - Provide alternatives if possible

3. **Test First**
   - Rehearse in staging
   - Verify rollback works
   - Time the maintenance tasks

### Execution

1. **Be Prepared**
   - Have scripts ready
   - Document all steps
   - Assign clear roles

2. **Monitor Closely**
   - Watch for errors
   - Track progress
   - Be ready to rollback

3. **Communicate Progress**
   - Update status regularly
   - Notify of any delays
   - Confirm completion

## Related Articles

- [System Services Management](/kb/system-services-management)
- [Background Workers and Jobs](/kb/background-workers-jobs)
- [User Impersonation for Support](/kb/user-impersonation-support)

---

Need help with maintenance? Contact ops-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "system-maintenance-mode") do |article|
  article.title = "System Maintenance Mode"
  article.category = system_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Enable maintenance mode for safe system updates with customizable messages, admin bypass, scheduled windows, and user notifications."
  article.content = maintenance_mode_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ System Maintenance Mode"

# Article 37: User Impersonation for Support
impersonation_content = <<~MARKDOWN
# User Impersonation for Support

Securely impersonate users to debug issues, provide support, and understand their experience without accessing their credentials.

## Impersonation Overview

### What is User Impersonation?

User impersonation allows administrators to:
- **View the platform** as a specific user sees it
- **Debug issues** in the user's context
- **Test permissions** and access levels
- **Provide support** more effectively

### Security Considerations

Impersonation is a powerful feature requiring:
- Strict access controls
- Complete audit logging
- Clear user notification
- Time-limited sessions

## Accessing Impersonation

Navigate to **Administration > Impersonation** to:
- Search for users to impersonate
- View active impersonation sessions
- Review impersonation history

## Impersonation Dashboard

```
┌─────────────────────────────────────────────────────┐
│  User Impersonation                 [Audit Log]     │
├─────────────────────────────────────────────────────┤
│  Current Status: Not Impersonating                  │
│                                                     │
│  [Search users to impersonate...]                   │
├─────────────────────────────────────────────────────┤
│  Recent Sessions:                                   │
│  - john@company.com (Jan 15, 10:30 - 10:45)        │
│  - jane@company.com (Jan 14, 15:00 - 15:12)        │
│  - mike@company.com (Jan 14, 09:20 - 09:35)        │
└─────────────────────────────────────────────────────┘
```

## Starting Impersonation

### Via Dashboard

1. Navigate to **Administration > Impersonation**
2. Search for the user
3. Select user from results
4. Enter reason for impersonation
5. Click **Start Impersonation**

```yaml
Impersonation Request:
  User: jane@company.com
  Account: Acme Corp

  Reason: "Support ticket #12345 - User reports
          dashboard not loading correctly"

  Duration: 30 minutes (max)

  Restrictions:
    ✅ Read access only
    ⬜ Allow write actions
    ✅ Notify user
```

### Via User Management

1. Navigate to **Administration > Users**
2. Find the user
3. Click **⋮** menu
4. Select **Impersonate User**
5. Confirm and provide reason

## During Impersonation

### Visual Indicators

Clear indication you're impersonating:

```
┌─────────────────────────────────────────────────────┐
│  ⚠️ IMPERSONATING: jane@company.com                 │
│  As: admin@powernode.org | Time: 12:34 remaining    │
│  [End Impersonation]                                │
├─────────────────────────────────────────────────────┤
│                                                     │
│  (User's normal dashboard view)                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### What You Can See

```yaml
Impersonation Access:
  Dashboard: User's personalized view
  Data: User's data and settings
  Permissions: User's actual permissions
  Features: Features available to user's plan

  Not Accessible:
    - User's password
    - Payment details (masked)
    - 2FA recovery codes
    - API keys (create new only)
```

### Restrictions

```yaml
Impersonation Restrictions:
  By Default:
    - Read-only access
    - No password changes
    - No 2FA changes
    - No account deletion
    - No payment modifications

  With Approval:
    - Write actions (if enabled)
    - Settings changes
    - Support actions
```

## Ending Impersonation

### Manual End

1. Click **End Impersonation** banner
2. Or navigate to Administration > Impersonation
3. Confirm end of session

### Automatic End

```yaml
Auto-End Conditions:
  - Time limit reached (default: 30 min)
  - Admin logs out
  - Session timeout
  - Manual admin intervention
```

## Audit Logging

### What's Logged

Every impersonation action is recorded:

```yaml
Audit Log Entry:
  Event: impersonation.started
  Timestamp: 2024-01-15T10:30:45Z

  Admin:
    User: admin@powernode.org
    IP: 192.168.1.100

  Target:
    User: jane@company.com
    Account: Acme Corp

  Details:
    Reason: "Support ticket #12345"
    Duration Limit: 30 minutes
    Restrictions: read_only
```

### Actions During Impersonation

```yaml
Impersonation Actions Log:
  Session: imp_01HQ7EXAMPLE

  Actions:
    [10:30:45] Session started
    [10:31:02] Viewed /dashboard
    [10:31:15] Viewed /settings
    [10:32:00] Viewed /billing (masked data)
    [10:35:22] Viewed /support/ticket/12345
    [10:40:00] Session ended (manual)

  Summary:
    Duration: 9m 15s
    Pages Viewed: 4
    Write Actions: 0
```

### Audit Reports

Generate impersonation reports:

```yaml
Report Options:
  - All sessions in date range
  - Sessions by admin
  - Sessions by target user
  - Sessions with write actions

Report Contents:
  - Session details
  - Reason provided
  - Actions taken
  - Duration
```

## User Notification

### Notification Settings

```yaml
User Notification:
  On Start:
    - In-app notification
    - Email notification (optional)

  Content:
    Subject: "Support session started on your account"
    Body: |
      An administrator has started a support session
      on your account to assist with your request.

      Administrator: Support Team
      Started: 2024-01-15 10:30 UTC
      Reason: Support ticket #12345

      This session is logged and audited.
      If you did not request support, please contact us.
```

### Opt-Out (Enterprise)

Enterprise accounts can configure:

```yaml
Notification Preferences:
  Notify on impersonation: always | never | critical_only
  Email notifications: enabled | disabled
  Require approval: enabled | disabled
```

## Permissions and Access

### Who Can Impersonate

```yaml
Required Permissions:
  admin.impersonation.read: View impersonation feature
  admin.impersonation.start: Start impersonation
  admin.impersonation.write: Perform write actions
  admin.impersonation.manage: Manage all sessions
```

### Role Configuration

```yaml
Role: Super Admin
  Permissions:
    - admin.impersonation.* (all)

Role: Support Lead
  Permissions:
    - admin.impersonation.read
    - admin.impersonation.start

Role: Support Agent
  Permissions:
    - admin.impersonation.read
    (Must request from lead)
```

### Restrictions by User Type

```yaml
Impersonation Restrictions:
  Regular Users: Can be impersonated
  Admin Users: Requires super admin
  Super Admins: Cannot be impersonated
  Service Accounts: Cannot be impersonated
```

## Best Practices

### When to Impersonate

```yaml
Appropriate Uses:
  ✅ Debugging user-reported issues
  ✅ Verifying permission problems
  ✅ Testing user experience
  ✅ Assisting with complex tasks

Inappropriate Uses:
  ❌ Curiosity about user data
  ❌ Bypassing approval processes
  ❌ Making unauthorized changes
  ❌ Accessing without valid reason
```

### Documentation

```yaml
Always Document:
  - Support ticket or request number
  - Specific issue being investigated
  - Expected duration
  - Actions planned (if write access needed)
```

### Security Guidelines

1. **Minimize Duration**
   - End session when done
   - Don't leave sessions open
   - Use shortest needed time

2. **Minimize Access**
   - Use read-only when possible
   - Only request write when necessary
   - Don't access unrelated data

3. **Maintain Audit Trail**
   - Always provide reason
   - Document findings
   - Report any concerns

## Troubleshooting

### Common Issues

**Cannot Impersonate User**
```yaml
Causes:
  - Insufficient permissions
  - User is protected (admin/super admin)
  - Session limit reached
  - Account restrictions

Solution:
  - Verify your permissions
  - Check user type
  - End other sessions
  - Contact super admin
```

**Session Ended Unexpectedly**
```yaml
Causes:
  - Time limit reached
  - Another admin ended session
  - System timeout
  - Network issues

Solution:
  - Check audit log for reason
  - Start new session if needed
  - Extend time limit for long tasks
```

## Related Articles

- [Audit Logs and Monitoring](/kb/audit-logs-monitoring)
- [System Maintenance Mode](/kb/system-maintenance-mode)
- [Security Configuration Guide](/kb/security-configuration-guide)

---

Need help with impersonation? Contact security@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "user-impersonation-support") do |article|
  article.title = "User Impersonation for Support"
  article.category = system_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Securely impersonate users to debug issues and provide support with full audit logging, user notifications, and access controls."
  article.content = impersonation_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ User Impersonation for Support"

puts "  ✅ System Administration articles created (5 articles)"
