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

puts "  ✅ System Administration articles created (2 articles)"
