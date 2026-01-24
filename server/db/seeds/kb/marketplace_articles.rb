# frozen_string_literal: true

# Marketplace Articles
# Documentation for marketplace features

puts "  🛒 Creating Marketplace articles..."

marketplace_cat = KnowledgeBase::Category.find_by!(slug: "marketplace")
author = User.find_by!(email: "admin@powernode.org")

# Article 31: Marketplace Overview
marketplace_overview_content = <<~MARKDOWN
# Marketplace Overview

Discover and install pre-built workflows, pipelines, integrations, and plugins from the Powernode Marketplace.

## What is the Marketplace?

The Powernode Marketplace offers:
- Pre-built AI workflows
- CI/CD pipeline templates
- Integration connectors
- Custom plugins
- Prompt libraries

## Browsing the Marketplace

### Navigation

Navigate to **Marketplace** from main menu:

```
┌─────────────────────────────────────────────┐
│  Marketplace                                 │
├─────────────────────────────────────────────┤
│  Categories  │  Featured  │  Search         │
├──────────────┼────────────┼─────────────────┤
│  Workflows   │            │                 │
│  Pipelines   │  [Items]   │  [Results]      │
│  Integrations│            │                 │
│  Plugins     │            │                 │
│  Prompts     │            │                 │
└──────────────┴────────────┴─────────────────┘
```

### Item Categories

| Category | Description |
|----------|-------------|
| **Workflows** | AI automation workflows |
| **Pipelines** | CI/CD templates |
| **Integrations** | Third-party connectors |
| **Plugins** | Platform extensions |
| **Prompts** | AI prompt templates |

## Searching and Filtering

### Search Options

- **Keyword Search**: Find by name or description
- **Category Filter**: Browse by type
- **Tag Filter**: Filter by tags
- **Rating Sort**: Top-rated items
- **Popularity**: Most installed

### Item Details

Each listing includes:
- Name and description
- Screenshots/demos
- Installation instructions
- Requirements
- Reviews and ratings
- Version history

## Installing Items

### Installation Process

1. Browse to desired item
2. Click **Install**
3. Review permissions
4. Configure settings
5. Activate

### Example: Install Workflow

```yaml
Installing: Customer Support Workflow

  Permissions Required:
    - ai.agents.use
    - ai.workflows.execute

  Configuration:
    - Select AI provider
    - Configure notifications
    - Set trigger conditions

  Status: Installed ✓
```

### Managing Installed Items

View at **Marketplace > My Items**:
- Installed items list
- Update availability
- Usage statistics
- Uninstall option

## Subscriptions and Pricing

### Pricing Models

| Model | Description |
|-------|-------------|
| Free | No cost |
| One-Time | Single purchase |
| Subscription | Monthly/annual |
| Usage-Based | Pay per use |

### Managing Subscriptions

Track marketplace spending:
- Active subscriptions
- Billing history
- Cancel/modify
- Usage reports

## Ratings and Reviews

### Leaving Reviews

After installation:
1. Use item for evaluation period
2. Go to item page
3. Click **Write Review**
4. Rate (1-5 stars)
5. Add comments
6. Submit

### Review Guidelines

- Be specific and helpful
- Describe your use case
- Mention pros and cons
- Update if issues resolved

---

For publishing your own items, see [Publishing to the Marketplace](/kb/publishing-marketplace).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "marketplace-overview") do |article|
  article.title = "Marketplace Overview"
  article.category = marketplace_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Discover and install pre-built workflows, pipelines, integrations, and plugins from the Powernode Marketplace."
  article.content = marketplace_overview_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Marketplace Overview"

# Article 32: Publishing to the Marketplace
publishing_content = <<~MARKDOWN
# Publishing to the Marketplace

Share your workflows, pipelines, and integrations with the Powernode community.

## Publisher Requirements

### Eligibility

To publish items:
- Active Powernode account
- Verified email
- Accepted publisher agreement
- Good standing (no violations)

### Becoming a Publisher

1. Navigate to **Marketplace > Become a Publisher**
2. Review publisher agreement
3. Complete profile:
   - Publisher name
   - Contact information
   - Company details (optional)
4. Submit application
5. Await approval (1-3 business days)

## Creating a Listing

### Basic Information

```yaml
Listing Details:
  Name: Descriptive name
  Category: Workflow | Pipeline | Integration | Plugin | Prompt
  Short Description: 100 characters max
  Full Description: Markdown supported
  Tags: Up to 5 tags
```

### Item Package

Include in your package:
- Main item file (workflow, pipeline YAML, etc.)
- README with instructions
- Screenshots (recommended)
- Sample configurations
- Documentation

### Version Information

```yaml
Version Settings:
  Version Number: 1.0.0 (semantic versioning)
  Release Notes: What's new
  Compatibility: Powernode version requirements
  Dependencies: Required items
```

## Documentation Requirements

### Required Sections

1. **Overview**: What it does
2. **Installation**: Setup steps
3. **Configuration**: Options and settings
4. **Usage**: How to use
5. **Troubleshooting**: Common issues

### Best Practices

- Clear, concise writing
- Step-by-step instructions
- Screenshots for complex steps
- Code examples where relevant

## Pricing Your Item

### Pricing Options

| Model | Best For |
|-------|----------|
| Free | Community building, lead generation |
| One-Time | Simple tools |
| Monthly | Ongoing services |
| Usage-Based | Variable usage patterns |

### Setting Price

Consider:
- Development time invested
- Ongoing maintenance
- Market comparison
- Value delivered

## Submission Process

### Review Process

```
Submit → Automated Checks → Manual Review → Published
   ↓           ↓                 ↓              ↓
 Package    Security &         Quality &      Live on
 Upload     Compliance        Completeness   Marketplace
```

### Automated Checks

- Security scan
- Compatibility verification
- Documentation presence
- Package integrity

### Manual Review

Reviewers check:
- Quality and functionality
- Documentation clarity
- Pricing appropriateness
- Policy compliance

## Managing Published Items

### Updates

Release new versions:
1. Navigate to **My Items**
2. Select item
3. Click **New Version**
4. Upload package
5. Add release notes
6. Submit for review

### Analytics

Track performance:
- Installations
- Active users
- Revenue (if paid)
- Ratings/reviews
- Support requests

### Support

Provide user support:
- Monitor reviews
- Respond to questions
- Fix reported issues
- Update documentation

---

For marketplace browsing, see [Marketplace Overview](/kb/marketplace-overview).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "publishing-marketplace") do |article|
  article.title = "Publishing to the Marketplace"
  article.category = marketplace_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Become a publisher and share workflows, pipelines, and integrations with the Powernode community marketplace."
  article.content = publishing_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Publishing to the Marketplace"

puts "  ✅ Marketplace articles created (2 articles)"
