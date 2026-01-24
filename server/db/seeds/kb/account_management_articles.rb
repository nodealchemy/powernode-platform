# frozen_string_literal: true

# Account Management Articles
# Documentation for account and profile management

puts "  👤 Creating Account Management articles..."

account_cat = KnowledgeBase::Category.find_by!(slug: "account-management")
author = User.find_by!(email: "admin@powernode.org")

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

Upload a profile image:
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

Switch between themes:
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

Password requirements:
- Minimum 12 characters
- Mixed case letters
- Numbers
- Special characters

### Two-Factor Authentication

Enable 2FA for enhanced security:

1. Navigate to **Settings > Security**
2. Click **Enable 2FA**
3. Scan QR code with authenticator app
4. Enter verification code
5. Save backup codes securely

Supported apps:
- Google Authenticator
- Authy
- 1Password
- Microsoft Authenticator

### Backup Codes

Store backup codes safely:
- Generated during 2FA setup
- Use if phone unavailable
- Each code works once
- Regenerate if depleted

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

View connected services:
- Google (SSO)
- GitHub (DevOps)
- Slack (Notifications)

### Managing Connections

Disconnect services:
1. Go to **Settings > Connections**
2. Find connected service
3. Click **Disconnect**
4. Confirm disconnection

## Data & Privacy

### Export Your Data

Request data export:
1. Go to **Settings > Privacy**
2. Click **Export My Data**
3. Choose format (JSON/CSV)
4. Receive download link via email

### Delete Account

Account deletion:
- Contact support for deletion
- 30-day grace period
- Irreversible after period
- Data permanently removed

---

For team management, see [Team Management and Invitations](/kb/team-management-invitations).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "managing-profile-settings") do |article|
  article.title = "Managing Your Profile and Settings"
  article.category = account_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Customize your Powernode experience with profile updates, display preferences, security settings, 2FA, and notification configuration."
  article.content = profile_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

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

Manage outstanding invitations:
- View pending invites
- Resend if needed
- Revoke if invalid
- Track expiration

## Managing Team Members

### Editing Members

For existing members:
1. Click member name
2. Edit permissions
3. Update details
4. Save changes

### Permissions Update

Changes take effect immediately:
- User may need to refresh
- Active sessions updated
- Audit log entry created

### Suspending Members

Temporarily disable access:
1. Select member
2. Click **Suspend**
3. Confirm action
4. Member cannot access

### Removing Members

Remove team member:
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

View team actions:
- Login events
- Permission changes
- Feature usage
- Configuration changes

### Audit Trail

For compliance:
- Who did what
- When it happened
- What changed
- IP address

---

For detailed permissions, see [User Roles and Permissions](/kb/user-roles-permissions).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "team-management-invitations") do |article|
  article.title = "Team Management and Invitations"
  article.category = account_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Manage team members, send invitations, configure permissions, and perform bulk operations for team collaboration."
  article.content = team_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Team Management and Invitations"

# Article 7: Account Security Best Practices
security_content = <<~MARKDOWN
# Account Security Best Practices

Protect your Powernode account with security best practices and configuration recommendations.

## Password Security

### Strong Password Requirements

Create secure passwords:
- **Length**: 12+ characters minimum
- **Complexity**: Mix of upper, lower, numbers, symbols
- **Uniqueness**: Different from other accounts
- **No Patterns**: Avoid common words/sequences

### Password Managers

Recommended tools:
- 1Password
- LastPass
- Bitwarden
- Dashlane

Benefits:
- Generate strong passwords
- Secure storage
- Auto-fill convenience
- Cross-device sync

## Two-Factor Authentication

### Why Enable 2FA

Additional security layer:
- Protects against password theft
- Blocks unauthorized access
- Required for sensitive operations
- Industry best practice

### Setting Up 2FA

1. Navigate to **Settings > Security**
2. Click **Enable Two-Factor Authentication**
3. Choose method:
   - Authenticator app (recommended)
   - SMS (less secure)
4. Follow setup wizard
5. Store backup codes safely

### Backup Codes

Handle backup codes carefully:
- Print and store securely
- Don't store digitally
- Each code is single-use
- Regenerate when needed

## Session Security

### Session Management

Control active sessions:
- View all logged-in devices
- Revoke suspicious sessions
- Set session timeout
- Monitor login locations

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

Enable notifications for:
- New device logins
- Unusual locations
- Failed login attempts
- Password changes

### Audit Logs

Review security events:
- All login attempts
- Permission changes
- API key usage
- Configuration changes

## API Key Security

### Secure API Key Practices

1. **Separate Keys**: Different keys for different purposes
2. **Minimal Permissions**: Only needed scopes
3. **Regular Rotation**: Change keys quarterly
4. **Secure Storage**: Environment variables, not code

### Key Rotation

Rotate API keys:
1. Generate new key
2. Update applications
3. Verify functionality
4. Revoke old key

## Network Security

### IP Restrictions

For enterprise accounts:
- Whitelist allowed IPs
- Block unauthorized locations
- VPN requirements
- Geo-restrictions

### HTTPS Only

All connections secured:
- TLS 1.2+ required
- Certificate validation
- HSTS enabled
- Secure cookies

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

Immediate actions:
1. Change password immediately
2. Revoke all sessions
3. Rotate API keys
4. Enable/reset 2FA
5. Contact support

### Reporting Security Issues

Report to: security@powernode.org
- Describe the issue
- Include timestamps
- Preserve evidence
- Don't share publicly

---

For general troubleshooting, see [Troubleshooting Common Issues](/kb/troubleshooting-common-issues).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "account-security-best-practices") do |article|
  article.title = "Account Security Best Practices"
  article.category = account_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Secure your account with strong passwords, 2FA, session management, API key practices, and security monitoring."
  article.content = security_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Account Security Best Practices"

puts "  ✅ Account Management articles created (3 articles)"
