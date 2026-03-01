# frozen_string_literal: true

# Troubleshooting Articles
# Documentation for common issues and support

puts "  🔧 Creating Troubleshooting articles..."

troubleshooting_cat = KnowledgeBase::Category.find_by!(slug: "troubleshooting")
author = User.find_by!(email: "admin@powernode.org")

# Article 39: Common Issues and Solutions (Featured)
common_issues_content = <<~MARKDOWN
# Common Issues and Solutions

Quick solutions to frequently encountered issues in Powernode.

## Login and Authentication

### Cannot Log In

**Forgot Password**
1. Click "Forgot Password" on login page
2. Enter your email
3. Check inbox (and spam folder)
4. Click reset link
5. Create new password

**Account Locked**
- Too many failed attempts
- Wait 15 minutes
- Or contact support for unlock

**2FA Not Working**
- Ensure authenticator time is synced
- Use backup codes if available
- Contact support for reset

### Session Expired

If frequently logged out:
- Check session timeout settings
- Verify cookies enabled
- Clear browser cache
- Try incognito mode

## Payment Issues

### Payment Declined

**Common Causes**
| Cause | Solution |
|-------|----------|
| Insufficient funds | Add funds or use different card |
| Expired card | Update card details |
| Bank block | Contact bank to authorize |
| Incorrect details | Verify card information |

**Troubleshooting Steps**
1. Verify card details are correct
2. Check expiration date
3. Confirm billing address matches bank records
4. Try different payment method
5. Contact your bank

### Invoice Issues

**Missing Invoice**
- Check spam/junk folder
- Download from dashboard: Business > Invoices
- Contact support for resend

**Incorrect Amount**
- Review line items
- Check for prorations
- Verify tax calculations
- Contact support if discrepancy

## Subscription Problems

### Subscription Not Active

1. Check payment status
2. Verify payment method is valid
3. Review billing history
4. Confirm plan is active
5. Contact support

### Features Not Available

- Verify plan includes feature
- Check user permissions
- Try logging out and back in
- Clear browser cache

## API Errors

### Authentication Errors

**401 Unauthorized**
```yaml
Checklist:
  - API key is correct
  - Key hasn't expired
  - Using correct environment (test/live)
  - Header format: "Authorization: Bearer YOUR_KEY"
```

**403 Forbidden**
- Check permission scopes
- Verify endpoint access
- Review rate limits

### Rate Limiting

**429 Too Many Requests**
```yaml
Resolution:
  - Check rate limit headers
  - Implement backoff strategy
  - Reduce request frequency
  - Request limit increase
```

### Connection Errors

**Timeout Issues**
- Check internet connection
- Verify endpoint URL
- Reduce payload size
- Retry with exponential backoff

## Webhook Failures

### Not Receiving Webhooks

1. Verify endpoint URL is correct
2. Check SSL certificate is valid
3. Confirm server is reachable
4. Review webhook logs in dashboard
5. Test with webhook.site

### Signature Verification Failed

- Ensure using raw request body
- Verify webhook secret
- Check signature algorithm
- Include timestamp validation

## Email Problems

### Not Receiving Emails

1. Check spam/junk folder
2. Verify email address
3. Add sender to contacts
4. Check email preferences
5. Contact support

### Emails Going to Spam

- Add noreply@powernode.org to contacts
- Mark emails as "not spam"
- Create inbox rule

## Performance Issues

### Dashboard Loading Slowly

**Browser Steps**
1. Clear browser cache
2. Disable extensions
3. Try different browser
4. Use incognito mode

**Account Steps**
- Reduce date ranges
- Use filters
- Check internet speed

### Reports Not Generating

- Reduce data range
- Apply filters
- Try different format
- Contact support for large exports

## Browser Compatibility

### Supported Browsers

| Browser | Version |
|---------|---------|
| Chrome | Latest 2 versions |
| Firefox | Latest 2 versions |
| Safari | Latest 2 versions |
| Edge | Latest 2 versions |

### Common Browser Issues

- Enable JavaScript
- Enable cookies
- Disable ad blockers for Powernode
- Update to latest version

---

Still stuck? See [Contacting Support](/kb/contacting-support) for help options.
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "common-issues-solutions") do |article|
  article.title = "Common Issues and Solutions"
  article.category = troubleshooting_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Quick solutions for login issues, payment problems, API errors, webhook failures, and performance troubleshooting."
  article.content = common_issues_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Common Issues and Solutions"

# Article 40: Contacting Support
contact_support_content = <<~MARKDOWN
# Contacting Support

Get help from the Powernode support team through multiple channels.

## Support Channels

### Email Support

**General Support**: support@powernode.org

Best for:
- Non-urgent issues
- Detailed questions
- Feature requests
- Bug reports

### Live Chat

Available in dashboard for paid plans:
- Click chat icon (bottom right)
- Available during business hours
- 24/7 for Enterprise plans

### Phone Support

Available for Business and Enterprise plans:
- US: +1-800-POWERNODE
- International: +1-555-0123

### Help Desk

Submit tickets through dashboard:
1. Navigate to **Help > Support Tickets**
2. Click **New Ticket**
3. Describe issue
4. Attach screenshots
5. Submit

## Response Times

| Plan | Email | Chat | Phone |
|------|-------|------|-------|
| Starter | 48 hours | - | - |
| Professional | 24 hours | Business hours | - |
| Business | 12 hours | Extended hours | Business hours |
| Enterprise | 2 hours | 24/7 | 24/7 |

## What to Include

### For Faster Resolution

Include in your request:
- **Account email** - Verify identity
- **Issue description** - Clear and specific
- **Steps to reproduce** - How to see the issue
- **Screenshots** - Visual evidence
- **Error messages** - Exact text
- **Timestamps** - When it occurred
- **Browser/device** - Technical details

### Example Good Report

```
Subject: Payment failing for customer

Account: admin@company.com

Issue: Customer unable to complete payment
- Customer email: customer@example.com
- Error: "Card declined"
- Card last 4: 4242
- Attempted: 3 times today
- Browser: Chrome 120 on Windows

Screenshot attached showing error message.
```

## Escalation Procedures

### When to Escalate

- Critical business impact
- No response within SLA
- Ongoing unresolved issue
- Security concern

### How to Escalate

1. Reference original ticket
2. Explain urgency
3. Request escalation
4. Provide business impact

## Self-Help Resources

### Before Contacting Support

Try these first:
1. **Knowledge Base** - Search for your issue
2. **Status Page** - Check for outages
3. **Community Forum** - See if others have solved it
4. **Documentation** - Review relevant guides

### Status Page

Monitor system status:
- **URL**: status.powernode.org
- Subscribe for updates
- Check incident history

## Community Resources

### Community Forum

Join discussions:
- Ask questions
- Share solutions
- Connect with users
- Feature discussions

### Developer Resources

For technical questions:
- API documentation
- GitHub discussions
- Developer Slack
- Stack Overflow tag

## Emergency Contacts

### Critical Issues

For emergencies (data breach, complete outage):

**Security**: security@powernode.org
**Emergency**: emergency@powernode.org

### What Qualifies as Emergency

- Security breach
- Complete service outage
- Data loss
- Payment system down

---

We're here to help! Contact us anytime through your preferred channel.
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "contacting-support") do |article|
  article.title = "Contacting Support"
  article.category = troubleshooting_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Get help through email, live chat, phone, or help desk with response times by plan tier and tips for faster resolution."
  article.content = contact_support_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Contacting Support"

puts "  ✅ Troubleshooting articles created (2 articles)"
