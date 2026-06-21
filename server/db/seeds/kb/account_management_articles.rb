# frozen_string_literal: true

# Account Management Articles
# Documentation for account and profile management

puts "  👤 Creating Account Management articles..."

account_cat = KnowledgeBase::Category.find_by!(slug: "account-management")

# Article 5: Managing Your Profile and Settings
profile_content = <<~MARKDOWN
# Managing Your Profile and Settings

Customize your Powernode experience with profile settings, preferences, and security options.

## Profile Information

### Updating Your Profile

Navigate to **Settings > Profile**:

```yaml
Profile Fields:
  Personal:
    - First Name
    - Last Name
    - Email Address
    - Avatar (image upload)

  Contact:
    - Phone Number
    - Timezone
    - Language

  Professional:
    - Job Title
    - Department
```

### Avatar Upload

- Supported: JPEG, PNG, GIF
- Max size: 5MB
- Recommended: 200×200px minimum

## Account Settings

### Email Preferences

Configure email notifications:

| Category | Options |
|----------|---------|
| Security | Login alerts, password changes |
| Billing | Invoice, payment confirmations |
| Product | Feature updates, newsletters |
| Activity | Team changes, mentions |

### Display Settings

Customize your interface:

```yaml
Display Preferences:
  Theme: light | dark | system
  Language: English (default)
  Timezone: Auto-detect or manual
  Date Format: MM/DD/YYYY or DD/MM/YYYY
  Currency Display: Symbol or code
```

### Theme Preferences

- **Light Mode** - Clean, bright interface
- **Dark Mode** - Reduced eye strain
- **System** - Follows OS preference

## Security Settings

### Password Management

Change your password:
1. Go to **Settings > Security**
2. Click **Change Password**
3. Enter current password
4. Enter new password (twice)
5. Save changes

Requirements: minimum 12 characters, mixed case, numbers, and special characters.

### Two-Factor Authentication

Enable 2FA for enhanced security:

1. Navigate to **Settings > Security**
2. Click **Enable 2FA**
3. Scan QR code with authenticator app
4. Enter verification code
5. Save backup codes securely

Supported apps: Google Authenticator, Authy, 1Password, Microsoft Authenticator.

### Backup Codes

Generated during 2FA setup. Store them safely for when your phone is unavailable; each code works once, and you can regenerate when depleted.

### Session Management

View and manage active sessions:

```yaml
Active Sessions:
  - Device: Chrome on macOS
    Location: San Francisco, CA
    Last Active: 2 minutes ago
    Status: Current session

  - Device: Safari on iPhone
    Location: San Francisco, CA
    Last Active: 1 hour ago
    Action: [Revoke]
```

## Notification Preferences

### Notification Channels

| Channel | Description |
|---------|-------------|
| Email | Delivered to inbox |
| In-App | Dashboard notifications |
| Push | Browser notifications |

### Configuring Notifications


```yaml
Notification Settings:
  Security Alerts:
    - New login: email + in-app
    - Password change: email
    - 2FA change: email

  Billing:
    - Invoice generated: email
    - Payment successful: in-app
    - Payment failed: email + in-app

  Team:
    - New member: in-app
    - Mention: email + in-app
```

## Connected Accounts

### OAuth Connections

Connected services include Google (SSO), GitHub (DevOps), and Slack (Notifications).

### Managing Connections

Disconnect services:
1. Go to **Settings > Connections**
2. Find connected service
3. Click **Disconnect**
4. Confirm disconnection

## Data & Privacy

### Export Your Data

1. Go to **Settings > Privacy**
2. Click **Export My Data**
3. Choose format (JSON/CSV)
4. Receive download link via email

### Delete Account

Contact support to delete your account. A 30-day grace period applies; after it, deletion is irreversible and data is permanently removed.

---

For team management, see [Team Management and Invitations](/kb/team-management-invitations).
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(source_key: "managing-profile-settings", account_id: nil)
article.assign_attributes(
  title: "Managing Your Profile and Settings",
  slug: "managing-profile-settings",
  category: account_cat,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Customize your Powernode experience with profile updates, display preferences, security settings, 2FA, and notification configuration.",
  content: profile_content,
  views_count: article.views_count || 0,
  likes_count: article.likes_count || 0,
  published_at: article.published_at || Time.current
)
article.author_id = nil
article.save!

puts "    ✅ Managing Your Profile and Settings"

# Article 6: Team Management and Invitations
team_content = <<~MARKDOWN
# Team Management and Invitations

Manage your team members, send invitations, and configure access for collaborative work.

## Team Overview

### Viewing Team Members

Navigate to **Settings > Team**:

| Column | Description |
|--------|-------------|
| Name | Team member name |
| Email | Contact email |
| Role | Assigned role |
| Status | Active, pending, suspended |
| Joined | Membership date |

## Inviting Team Members

### Send Invitation

1. Navigate to **Settings > Team**
2. Click **Invite Member**
3. Enter details:

```yaml
Invitation Form:
  Email: colleague@company.com
  First Name: (optional)
  Permissions:
    - users.read
    - billing.read
    - analytics.read
  Message: "Welcome to our Powernode team!"
  Expiration: 7 days (default)
```

4. Send invitation

### Invitation Process

```
Send Invitation → Email Delivered → User Clicks Link → Creates Account → Joins Team
```

### Pending Invitations

Manage outstanding invitations: view pending invites, resend if needed, revoke if invalid, and track expiration.

## Managing Team Members

### Editing Members

1. Click member name
2. Edit permissions
3. Update details
4. Save changes

Permission changes take effect immediately. The user may need to refresh; active sessions are updated and an audit log entry is created.

### Suspending Members

Temporarily disable access:
1. Select member
2. Click **Suspend**
3. Confirm action

### Removing Members

1. Select member
2. Click **Remove**
3. Transfer ownership (if needed)
4. Confirm removal

## Bulk Operations

### Bulk Invite

Invite multiple members:
1. Click **Bulk Invite**
2. Upload CSV with emails
3. Select default permissions
4. Send all invitations

CSV format:
```csv
email,first_name,last_name
john@company.com,John,Smith
jane@company.com,Jane,Doe
```

### Bulk Permission Update

Update multiple members:
1. Select members
2. Click **Bulk Edit**
3. Modify permissions
4. Apply changes

## Team Activity

### Activity Log

View team actions: login events, permission changes, feature usage, and configuration changes.

### Audit Trail

For compliance, the audit trail records who did what, when it happened, what changed, and the IP address.

---

For detailed permissions, see [User Roles and Permissions](/kb/user-roles-permissions).
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(source_key: "team-management-invitations", account_id: nil)
article.assign_attributes(
  title: "Team Management and Invitations",
  slug: "team-management-invitations",
  category: account_cat,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Manage team members, send invitations, configure permissions, and perform bulk operations for team collaboration.",
  content: team_content,
  views_count: article.views_count || 0,
  likes_count: article.likes_count || 0,
  published_at: article.published_at || Time.current
)
article.author_id = nil
article.save!

puts "    ✅ Team Management and Invitations"

# Article 7: Account Security Best Practices
security_content = <<~MARKDOWN
# Account Security Best Practices

Protect your Powernode account with these security practices and configuration recommendations.

## Password Security

### Strong Password Requirements

- **Length**: 12+ characters minimum
- **Complexity**: Mix of upper, lower, numbers, symbols
- **Uniqueness**: Different from other accounts
- **No Patterns**: Avoid common words/sequences

### Password Managers

Recommended tools (1Password, LastPass, Bitwarden, Dashlane) generate strong passwords, store them securely, auto-fill, and sync across devices.

## Two-Factor Authentication

### Why Enable 2FA

2FA adds a security layer that protects against password theft, blocks unauthorized access, and is required for sensitive operations.

### Setting Up 2FA

1. Navigate to **Settings > Security**
2. Click **Enable Two-Factor Authentication**
3. Choose method:
   - Authenticator app (recommended)
   - SMS (less secure)
4. Follow setup wizard
5. Store backup codes safely

### Backup Codes

Print and store backup codes securely (not digitally). Each code is single-use; regenerate when needed.

## Session Security

### Session Management

Control active sessions: view all logged-in devices, revoke suspicious sessions, set session timeout, and monitor login locations.

### Automatic Logout

Configure timeout:
```yaml
Session Settings:
  Timeout After Inactivity: 30 minutes
  Maximum Session Length: 24 hours
  Concurrent Sessions: 3 (default)
```

## Access Monitoring

### Login Alerts

Enable notifications for new device logins, unusual locations, failed login attempts, and password changes.

### Audit Logs

Review security events: all login attempts, permission changes, API key usage, and configuration changes.

## API Key Security

### Secure API Key Practices

1. **Separate Keys**: Different keys for different purposes
2. **Minimal Permissions**: Only needed scopes
3. **Regular Rotation**: Change keys quarterly
4. **Secure Storage**: Environment variables, not code

### Key Rotation

1. Generate new key
2. Update applications
3. Verify functionality
4. Revoke old key

## Network Security

### IP Restrictions

For enterprise accounts: whitelist allowed IPs, block unauthorized locations, require VPN, and apply geo-restrictions.

### HTTPS Only

All connections are secured with TLS 1.2+, certificate validation, HSTS, and secure cookies.

## Security Checklist

### Monthly Review

- [ ] Review active sessions
- [ ] Check recent login activity
- [ ] Verify team permissions
- [ ] Review API key usage
- [ ] Update passwords if needed

### Quarterly Review

- [ ] Rotate API keys
- [ ] Audit user access
- [ ] Review security logs
- [ ] Update 2FA if needed
- [ ] Test backup codes

## Incident Response

### If You Suspect Compromise

1. Change password immediately
2. Revoke all sessions
3. Rotate API keys
4. Enable/reset 2FA
5. Contact support

### Reporting Security Issues

Report to security@powernode.org. Describe the issue, include timestamps, preserve evidence, and don't share publicly.

---

For general troubleshooting, see [Troubleshooting Common Issues](/kb/troubleshooting-common-issues).
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(source_key: "account-security-best-practices", account_id: nil)
article.assign_attributes(
  title: "Account Security Best Practices",
  slug: "account-security-best-practices",
  category: account_cat,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Secure your account with strong passwords, 2FA, session management, API key practices, and security monitoring.",
  content: security_content,
  views_count: article.views_count || 0,
  likes_count: article.likes_count || 0,
  published_at: article.published_at || Time.current
)
article.author_id = nil
article.save!

puts "    ✅ Account Security Best Practices"

puts "  ✅ Account Management articles created (3 articles)"
