# frozen_string_literal: true

# Security & Compliance Articles
# Documentation for security and privacy features

puts "  🔒 Creating Security & Compliance articles..."

security_cat = KnowledgeBase::Category.find_by!(slug: "security-compliance")
author = User.find_by!(email: "admin@powernode.org")

# Article 35: Security Configuration Guide
security_config_content = <<~MARKDOWN
# Security Configuration Guide

Configure Powernode's security settings to protect your data and meet compliance requirements.

## Security Overview

### Security Layers

```
Application Security
    ├── Authentication (JWT, 2FA)
    ├── Authorization (Permissions)
    ├── Data Encryption (at rest, in transit)
    ├── Input Validation
    └── Audit Logging

Infrastructure Security
    ├── TLS/HTTPS
    ├── Firewall
    ├── DDoS Protection
    └── Network Isolation
```

## Password Policies

### Configuration

Navigate to **Settings > Security > Password Policy**:

```yaml
Password Policy:
  Minimum Length: 12 characters
  Require Uppercase: true
  Require Lowercase: true
  Require Numbers: true
  Require Special: true
  Prevent Reuse: Last 5 passwords
  Expiration: 90 days (optional)
  Lock After: 5 failed attempts
  Lock Duration: 15 minutes
```

### Enforcement

Applies to:
- New account creation
- Password changes
- Password resets

## Session Management

### Session Configuration

```yaml
Session Settings:
  Timeout: 30 minutes (inactivity)
  Maximum Duration: 24 hours
  Concurrent Sessions: 3
  Secure Cookies: true
  SameSite: Strict
```

### Session Controls

- View active sessions
- Revoke specific sessions
- Force logout all sessions
- Geographic restrictions

## API Security

### API Key Management

```yaml
API Key Settings:
  Key Prefix: pk_ (publishable) / sk_ (secret)
  Expiration: Optional
  IP Restrictions: Optional
  Permission Scopes: Required
  Rate Limiting: Per key
```

### Best Practices

- Use environment variables
- Rotate keys regularly
- Minimum required permissions
- Monitor usage

## Rate Limiting

### Configuration

```yaml
Rate Limits:
  Global:
    requests_per_minute: 1000
    requests_per_hour: 10000

  Per User:
    requests_per_minute: 100
    requests_per_hour: 1000

  Per Endpoint:
    /api/auth/login: 5 per minute
    /api/export: 10 per hour
```

### Rate Limit Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1642687200
```

## SSL/TLS Configuration

### Requirements

- TLS 1.2+ required
- Strong cipher suites
- Valid certificates
- HSTS enabled

### Security Headers

```yaml
Security Headers:
  Strict-Transport-Security: max-age=31536000
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  X-XSS-Protection: 1; mode=block
  Content-Security-Policy: default-src 'self'
```

## IP Restrictions

### Allowlisting

For enterprise accounts:
```yaml
IP Allowlist:
  - 10.0.0.0/8 (Internal)
  - 192.168.1.0/24 (Office)
  - 203.0.113.50 (VPN exit)
```

### Geographic Restrictions

Block access from specific regions:
- Country-level blocking
- Notification on blocked attempts
- Override for specific IPs

---

For privacy settings, see [Privacy and Data Protection](/kb/privacy-data-protection).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "security-configuration-guide") do |article|
  article.title = "Security Configuration Guide"
  article.category = security_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Configure security settings including password policies, session management, API security, rate limiting, and SSL/TLS."
  article.content = security_config_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Security Configuration Guide"

# Article 36: Privacy and Data Protection
privacy_content = <<~MARKDOWN
# Privacy and Data Protection

Manage privacy settings and data protection for GDPR, CCPA, and other regulatory compliance.

## Privacy Dashboard

### Overview

Navigate to **Settings > Privacy**:
- Consent management
- Data subject requests
- Retention settings
- Privacy configurations

## GDPR Compliance

### Key Requirements

| Requirement | Implementation |
|-------------|----------------|
| Lawful Basis | Consent management |
| Right to Access | Data export |
| Right to Erasure | Deletion requests |
| Data Portability | Export in standard formats |
| Consent Records | Audit trail |

### Data Processing

Document processing activities:
```yaml
Processing Record:
  Activity: Customer subscription management
  Purpose: Service delivery
  Legal Basis: Contract performance
  Data Categories:
    - Name and contact
    - Billing information
    - Usage data
  Retention: Duration of subscription + 7 years
  Recipients: Payment processor, email provider
```

## Consent Management

### Collecting Consent

```yaml
Consent Configuration:
  Categories:
    - essential (always on)
    - analytics (optional)
    - marketing (optional)

  Display:
    Banner: Bottom of page
    Detail Link: /privacy-settings
    Remember: 12 months
```

### Consent Records

Track all consents:
- User identifier
- Consent version
- Timestamp
- IP address
- Method (explicit click, form)

## Data Subject Requests

### Request Types

| Request | Action | Deadline |
|---------|--------|----------|
| Access | Provide data export | 30 days |
| Rectification | Update incorrect data | 30 days |
| Erasure | Delete personal data | 30 days |
| Portability | Export in machine format | 30 days |
| Objection | Stop processing | 30 days |

### Handling Requests

1. Request received
2. Verify identity
3. Assess request validity
4. Execute action
5. Notify requestor
6. Log completion

### Automated Export

```yaml
Data Export Contents:
  Account:
    - Profile information
    - Settings and preferences
  Activity:
    - Login history
    - Actions taken
  Billing:
    - Invoices
    - Payment history
  Communications:
    - Email preferences
    - Support tickets
```

## Data Retention

### Retention Policies

```yaml
Retention Settings:
  Active Accounts:
    Profile Data: Duration of account
    Usage Data: 2 years
    Logs: 1 year

  Deleted Accounts:
    Grace Period: 30 days
    Anonymized Data: 7 years (legal)
    Complete Deletion: After grace period

  Billing Data:
    Invoices: 7 years (legal requirement)
    Payment Methods: Until removed
```

### Automated Cleanup

Configure automatic deletion:
- Inactive account cleanup
- Old log purging
- Temporary data removal

## Cookie Management

### Cookie Categories

| Category | Purpose | Consent |
|----------|---------|---------|
| Essential | Site functionality | Not required |
| Analytics | Usage tracking | Required |
| Marketing | Advertising | Required |
| Preferences | User settings | Recommended |

### Cookie Banner

Configure consent banner:
- Display options
- Category descriptions
- Accept/reject buttons
- Detailed settings link

## Third-Party Disclosures

### Sub-Processors

Document data sharing:
```yaml
Sub-Processors:
  - Name: Stripe
    Purpose: Payment processing
    Data: Billing information
    Location: USA
    DPA: Yes

  - Name: SendGrid
    Purpose: Email delivery
    Data: Email addresses
    Location: USA
    DPA: Yes
```

### AI Provider Disclosure

Document AI data handling:
- What data is sent to AI providers
- How data is processed
- Retention by providers
- Opt-out options

---

For technical security, see [Security Configuration Guide](/kb/security-configuration-guide).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "privacy-data-protection") do |article|
  article.title = "Privacy and Data Protection"
  article.category = security_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Manage GDPR/CCPA compliance with consent management, data subject requests, retention policies, and cookie management."
  article.content = privacy_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Privacy and Data Protection"

puts "  ✅ Security & Compliance articles created (2 articles)"
