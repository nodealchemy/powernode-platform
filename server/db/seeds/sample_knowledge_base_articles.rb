# frozen_string_literal: true

# Sample Knowledge Base Articles for Powernode Platform
puts "Creating sample Knowledge Base articles..."

# Find the system admin user to be the author
admin_user = User.joins(:user_roles, :roles).where(roles: { name: 'system.admin' }).first

if admin_user.nil?
  puts "⚠️  No system admin found. Using existing admin or creating one..."
  
  # Try to find any existing admin user
  admin_user = User.where(email: ['admin@powernode.org', 'kb-admin@powernode.org']).first
  
  if admin_user.nil?
    # Create a default account first
    puts "Creating default account for KB admin..."
    default_account = Account.find_or_create_by(name: 'Knowledge Base Admin Account') do |account|
      account.subdomain = 'kb-admin'
      account.status = 'active'
      account.settings = {}
    end
    
    # Create admin user with proper password and account
    puts "Creating KB admin user..."
    admin_user = User.create!(
      email: 'kb-admin@powernode.org',
      first_name: 'Knowledge',
      last_name: 'Admin',
      password: 'P0w3rN0d3Admin!KB2024@#$',
      password_confirmation: 'P0w3rN0d3Admin!KB2024@#$',
      email_verified: true,
      email_verified_at: Time.current,
      account: default_account
    )
    
    # Assign system admin role
    admin_role = Role.find_by(name: 'system.admin')
    if admin_role
      admin_user.user_roles.create!(role: admin_role)
      puts "✅ Assigned system.admin role to KB admin user"
    end
  end
end

# Create Knowledge Base Categories
categories = {
  getting_started: {
    name: 'Getting Started',
    slug: 'getting-started',
    description: 'Essential guides to help you get started with Powernode',
    sort_order: 1
  },
  knowledge_base: {
    name: 'Knowledge Base Usage',
    slug: 'knowledge-base-usage',
    description: 'Learn how to use the Knowledge Base system effectively',
    sort_order: 2
  },
  subscription_management: {
    name: 'Subscription Management',
    slug: 'subscription-management',
    description: 'Managing subscriptions, plans, and customer lifecycles',
    sort_order: 3
  },
  billing_payments: {
    name: 'Billing & Payments',
    slug: 'billing-payments',
    description: 'Payment processing, invoicing, and financial management',
    sort_order: 4
  },
  user_management: {
    name: 'User Management',
    slug: 'user-management',
    description: 'Account management, permissions, and team collaboration',
    sort_order: 5
  },
  api_integrations: {
    name: 'API & Integrations',
    slug: 'api-integrations',
    description: 'API documentation, webhooks, and third-party integrations',
    sort_order: 6
  },
  troubleshooting: {
    name: 'Troubleshooting',
    slug: 'troubleshooting',
    description: 'Common issues and their solutions',
    sort_order: 7
  },
  admin_guides: {
    name: 'Admin Guides',
    slug: 'admin-guides',
    description: 'Administrative features and system management',
    sort_order: 8
  }
}

category_records = {}
categories.each do |key, data|
  category_records[key] = KnowledgeBaseCategory.find_or_create_by(slug: data[:slug]) do |category|
    category.name = data[:name]
    category.description = data[:description]
    category.sort_order = data[:sort_order]
    category.is_public = true
  end
end

# Create Tags
tags_data = [
  'getting-started', 'basics', 'tutorial', 'knowledge-base', 'search', 'categories',
  'subscriptions', 'plans', 'billing', 'payments', 'invoices', 'stripe', 'paypal',
  'users', 'permissions', 'roles', 'teams', 'api', 'webhooks', 'integrations',
  'troubleshooting', 'admin', 'configuration', 'security', 'analytics', 'reports'
]

tag_records = {}
tags_data.each do |tag_name|
  tag_records[tag_name] = KnowledgeBaseTag.find_or_create_by(name: tag_name) do |tag|
    tag.slug = tag_name
    tag.description = "Articles about #{tag_name.humanize.downcase}"
  end
end

# Knowledge Base Usage Articles
articles_data = [
  # Knowledge Base Usage Guide
  {
    category: :knowledge_base,
    title: 'Complete Guide to Using the Knowledge Base',
    slug: 'complete-guide-knowledge-base',
    content: %{
# Complete Guide to Using the Knowledge Base

Welcome to the Powernode Knowledge Base! This comprehensive guide will help you navigate, search, and make the most of our documentation system.

## What is the Knowledge Base?

The Knowledge Base is your central hub for:
- Product documentation and guides
- Step-by-step tutorials
- Troubleshooting information
- Best practices and tips
- API documentation
- Frequently asked questions

## Getting Started

### Accessing the Knowledge Base

1. **From the Dashboard**: Click "Knowledge Base" in the main navigation
2. **Direct URL**: Visit `/knowledge-base` in your browser
3. **Search**: Use the global search to find articles quickly

### Navigation Overview

The Knowledge Base is organized into several main sections:

- **Categories**: Topics grouped by functionality
- **Featured Articles**: Most important and popular content
- **Recent Articles**: Latest additions and updates
- **Popular Articles**: Most viewed content

## Searching for Information

### Quick Search
Use the search bar at the top of any Knowledge Base page:
1. Enter keywords related to your question
2. Press Enter or click the search icon
3. Browse results ranked by relevance

### Advanced Search Tips
- **Exact phrases**: Use quotes around phrases ("subscription management")
- **Multiple terms**: Use AND, OR operators (billing AND invoices)
- **Category filtering**: Select specific categories to narrow results
- **Tag filtering**: Use tags to find related articles

### Search Categories

#### By Topic
- **Getting Started**: Basic setup and orientation
- **Feature Guides**: Detailed functionality explanations  
- **Troubleshooting**: Problem-solving and error resolution
- **API Documentation**: Technical integration guides

#### By User Type
- **End Users**: Customer-facing features and workflows
- **Administrators**: System management and configuration
- **Developers**: Technical implementation and APIs
- **Billing Teams**: Financial operations and reporting

## Article Features

### Reading Experience
- **Table of Contents**: Navigate long articles easily
- **Print/Export**: Save articles as PDF or print
- **Reading Time**: Estimated time to complete each article
- **Last Updated**: See when content was last revised

### Interactive Elements
- **Code Examples**: Copy-paste ready code snippets
- **Screenshots**: Visual guides with annotations
- **Video Tutorials**: Embedded instructional videos
- **External Links**: References to additional resources

### Feedback and Engagement
- **Article Rating**: Rate articles as helpful or not helpful
- **Comments**: Leave questions or suggestions (coming soon)
- **Share**: Send article links to team members
- **Bookmarks**: Save articles for quick access (coming soon)

## Mobile Usage

The Knowledge Base is fully optimized for mobile devices:
- **Responsive Design**: Works on phones and tablets
- **Touch Navigation**: Easy browsing on touch screens
- **Offline Reading**: Some articles cached for offline access
- **Quick Actions**: Share, bookmark, and search optimized for mobile

## Tips for Effective Usage

### Before You Search
1. **Think about keywords**: What terms describe your issue?
2. **Check recent updates**: New features may have dedicated articles
3. **Consider your role**: Look for content tailored to your user type

### When Reading Articles
1. **Follow step-by-step**: Don't skip steps in tutorials
2. **Check prerequisites**: Ensure you have required permissions/access
3. **Note version information**: Some features may be version-specific
4. **Try examples**: Test code examples in a safe environment

### If You Can't Find What You Need
1. **Try different keywords**: Rephrase your search terms
2. **Browse categories**: Sometimes browsing reveals related topics
3. **Check troubleshooting**: Common issues may be documented
4. **Contact support**: Use the help chat for personalized assistance

## Content Types Explained

### Tutorials
Step-by-step guides for completing specific tasks:
- **Prerequisites**: What you need before starting
- **Steps**: Numbered instructions with screenshots
- **Verification**: How to confirm you completed the task successfully
- **Next Steps**: Related tasks or advanced configurations

### Reference Guides
Comprehensive information about features and functions:
- **Overview**: Purpose and capabilities
- **Configuration Options**: All available settings explained
- **Examples**: Common use cases and implementations
- **API Reference**: Technical specifications for developers

### Troubleshooting Articles
Solutions for common problems:
- **Symptoms**: How to identify the issue
- **Causes**: Why the problem occurs
- **Solutions**: Step-by-step resolution process
- **Prevention**: How to avoid the issue in the future

### FAQ Articles
Quick answers to frequently asked questions:
- **Question**: Clear, specific question
- **Answer**: Concise, actionable response
- **Related Topics**: Links to more detailed information
- **Last Updated**: When the answer was last verified

## Getting Help

### Within Articles
- **Was this helpful?** buttons provide quick feedback
- **Related Articles** suggest additional relevant content
- **Tags** help you find similar topics
- **Last Updated** dates ensure you have current information

### Beyond the Knowledge Base
- **Live Chat Support**: Real-time assistance for urgent issues
- **Email Support**: Detailed questions and complex scenarios
- **Community Forum**: Peer-to-peer help and discussions (coming soon)
- **Feature Requests**: Suggest improvements and new features

## Staying Updated

### New Content Notifications
- **Email Digest**: Weekly roundup of new and updated articles
- **RSS Feed**: Subscribe to updates in your feed reader
- **Category Subscriptions**: Get notified about specific topics
- **Dashboard Updates**: See new content when you log in

### Version Changes
- **Release Notes**: Detailed change logs for each update
- **Migration Guides**: Help transitioning between versions
- **Deprecation Notices**: Advance warning about feature changes
- **API Changes**: Technical updates for developers

---

**Need more help?** Contact our support team at support@powernode.org or use the chat widget in the bottom-right corner of any page.

**Last Updated**: #{Time.current.strftime('%B %d, %Y')}
},
    excerpt: 'Learn how to effectively navigate, search, and use the Powernode Knowledge Base system.',
    tags: %w[knowledge-base basics tutorial getting-started],
    is_featured: true,
    sort_order: 1
  },

  {
    category: :knowledge_base,
    title: 'How to Search the Knowledge Base Effectively',
    slug: 'how-to-search-knowledge-base',
    content: %{
# How to Search the Knowledge Base Effectively

Finding the right information quickly is essential for productivity. This guide will help you master the Knowledge Base search functionality.

## Search Interface Overview

### Search Bar Location
- **Main Navigation**: Available on every page
- **Knowledge Base Home**: Prominent search box
- **Article Pages**: Persistent search in header
- **Mobile**: Accessible via search icon

### Search Results Page
Results are displayed with:
- **Article Title**: Clickable link to full article
- **Excerpt**: Preview of relevant content
- **Category**: Where the article is located
- **Tags**: Topic classifications
- **Relevance Score**: How well it matches your query
- **Last Updated**: Freshness indicator

## Basic Search Techniques

### Simple Keyword Search
Just type your main keywords:
- ✅ `subscription billing`
- ✅ `user permissions`
- ✅ `API integration`
- ✅ `payment failure`

### Phrase Search
Use quotes for exact phrases:
- ✅ `"cancel subscription"`
- ✅ `"two factor authentication"`
- ✅ `"webhook endpoint"`

### Multiple Terms
Combine related terms:
- ✅ `billing invoice payment` (finds articles about any of these)
- ✅ `subscription AND billing` (finds articles about both)
- ✅ `stripe OR paypal` (finds articles about either payment processor)

## Advanced Search Features

### Boolean Operators

#### AND Operator
Find articles containing all terms:
```
subscription AND cancellation AND refund
```

#### OR Operator  
Find articles containing any term:
```
webhook OR API OR integration
```

#### NOT Operator
Exclude unwanted terms:
```
billing NOT subscription
```

### Category Filtering
Limit search to specific categories:
1. Use the category dropdown in search results
2. Or include category in search: `category:billing payment`

### Tag Filtering
Search by specific tags:
1. Click on any article tag to see related articles
2. Or use tag syntax: `tag:troubleshooting error`

### Date Filtering
Find recently updated content:
- **This Week**: `updated:7d`
- **This Month**: `updated:30d`
- **This Year**: `updated:365d`

## Search Best Practices

### Start Broad, Then Narrow
1. **First Search**: `billing`
2. **Refine**: `billing subscription`  
3. **Specific**: `billing subscription cancellation`

### Use Synonyms
If you don't find what you need, try different terms:
- Invoice → Bill, Receipt, Charge
- User → Customer, Account, Member
- Error → Problem, Issue, Failure

### Think Like the Documentation
Use terms that would appear in official documentation:
- Instead of "broken", try "error" or "troubleshooting"
- Instead of "setting up", try "configuration" or "installation"
- Instead of "how much", try "pricing" or "cost"

### Check Spelling and Variations
- ✅ `cancellation` not `cancelation`
- ✅ `occurred` not `occured`
- ✅ Try both US and UK spellings when relevant

## Common Search Scenarios

### Getting Started with a Feature
**Search**: `getting started [feature name]`
**Example**: `getting started webhooks`

### Troubleshooting Problems
**Search**: `troubleshooting [symptom]`
**Example**: `troubleshooting payment failure`

### Configuration Help
**Search**: `configure [feature]` or `setup [feature]`
**Example**: `configure stripe payments`

### API Documentation
**Search**: `API [function]` or `endpoint [action]`
**Example**: `API create subscription`

### Understanding Error Messages
**Search**: `error [specific error text]`
**Example**: `error insufficient funds`

## Mobile Search Tips

### Voice Search (iOS/Android)
- Tap the microphone icon in the search bar
- Speak clearly and naturally
- Works best with specific phrases

### Quick Filters
- **Recent**: Swipe right for recent articles
- **Popular**: Swipe left for most viewed
- **Bookmarked**: Access saved articles quickly

### Offline Search
- Previously viewed articles are cached
- Basic search works without internet
- Sync when connection is restored

## Troubleshooting Search Issues

### No Results Found
1. **Check spelling**: Verify keywords are correct
2. **Use fewer terms**: Start with 1-2 main keywords
3. **Try synonyms**: Use alternative terminology
4. **Browse categories**: Look in related sections manually

### Too Many Results
1. **Add more terms**: Be more specific
2. **Use quotes**: Search for exact phrases
3. **Filter by category**: Narrow down the topic area
4. **Sort by relevance**: Use the most relevant results first

### Results Not Relevant
1. **Use different keywords**: Try technical vs. common terms
2. **Check categories**: Make sure you're in the right section
3. **Read excerpts**: Scan previews before clicking
4. **Use negative terms**: Exclude irrelevant topics with NOT

## Search Analytics and Improvements

### We Track (Anonymous)
- Popular search terms
- Articles that aren't found
- User search patterns
- Click-through rates

### We Use This To
- Create missing documentation
- Improve article titles and content
- Enhance search algorithms
- Add suggested searches

### You Can Help By
- **Rating articles**: Mark helpful/unhelpful content
- **Providing feedback**: Use the feedback forms
- **Reporting issues**: Let us know about search problems
- **Requesting content**: Tell us what's missing

## Quick Reference

### Search Syntax
- `"exact phrase"` - Exact match
- `term1 AND term2` - Both terms required
- `term1 OR term2` - Either term acceptable
- `term1 NOT term2` - First term, excluding second
- `category:name` - Limit to specific category
- `tag:name` - Find articles with specific tag

### Keyboard Shortcuts
- `Ctrl/Cmd + K` - Focus search bar from anywhere
- `Enter` - Execute search
- `Esc` - Clear search or close results
- `↑/↓ arrows` - Navigate search suggestions

### Search Operators
- `*` - Wildcard (payment* finds payment, payments, paying)
- `?` - Single character wildcard (colo?r finds color, colour)
- `~` - Fuzzy search (handles typos automatically)

---

**Pro Tip**: Bookmark this article for quick reference, or print it as a desk reference for your team!

**Need help with search?** Contact support at support@powernode.org
},
    excerpt: 'Master the Knowledge Base search functionality with advanced techniques and best practices.',
    tags: %w[knowledge-base search tutorial tips],
    sort_order: 2
  },

  {
    category: :knowledge_base,
    title: 'Creating and Managing Knowledge Base Content',
    slug: 'creating-managing-kb-content',
    content: %{
# Creating and Managing Knowledge Base Content

Learn how to create, edit, and manage articles in the Powernode Knowledge Base system.

## Content Management Overview

The Knowledge Base uses a role-based content management system:

- **Authors**: Can create and edit their own articles
- **Content Managers**: Can manage all content and categories
- **Administrators**: Full access to all KB features and settings

## Required Permissions

To work with Knowledge Base content, you need these permissions:

- `kb.view` - View published articles
- `kb.edit` - Create and edit articles  
- `kb.manage` - Full content management access
- `kb.admin` - System administration features

## Creating New Articles

### Step 1: Access the Editor
1. Navigate to **Knowledge Base** > **Admin**
2. Click **Create New Article**
3. Choose the appropriate **Category**

### Step 2: Article Information
Fill in the basic details:

#### Title
- Keep it descriptive and specific
- Use keywords users might search for
- Maximum 255 characters
- Example: "How to Configure Stripe Payment Settings"

#### Category
- Choose the most appropriate category
- Categories help users browse and find content
- You can change this later if needed

#### Tags
- Add 3-5 relevant tags
- Use existing tags when possible
- Tags help with search and related articles
- Examples: `billing`, `stripe`, `configuration`, `payments`

#### Excerpt (Optional)
- Brief summary of the article (30-50 words)
- Appears in search results and article lists
- Auto-generated from content if left blank

### Step 3: Content Creation

#### Content Editor
The editor supports:
- **Markdown formatting**: Headers, lists, links, etc.
- **Rich text editing**: WYSIWYG interface
- **Code blocks**: Syntax highlighting for multiple languages
- **Images**: Upload and embed screenshots
- **Tables**: Data presentation
- **Callout boxes**: Important notes and warnings

#### Content Structure Best Practices

**Start with an Overview**
```markdown
# Article Title

Brief introduction explaining what this article covers and who it's for.

## What You'll Learn
- Key point 1
- Key point 2
- Key point 3

## Prerequisites
- Required permissions
- Previous steps completed
- Technical requirements
```

**Use Clear Headers**
```markdown
# Main Title (H1)
## Major Sections (H2)
### Subsections (H3)
#### Details (H4)
```

**Include Code Examples**
```markdown
```javascript
// Example API call
const response = await fetch('/api/v1/subscriptions', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer your-token',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(subscriptionData)
});
```
```

**Add Screenshots**
- Upload images to illustrate steps
- Use annotations to highlight important areas
- Keep file sizes reasonable (under 1MB)
- Alt text for accessibility

### Step 4: Article Settings

#### Visibility Options
- **Public**: Available to all users
- **Internal**: Only visible to team members
- **Draft**: Only visible to author and managers

#### Publishing Status
- **Draft**: Work in progress, not published
- **Review**: Ready for content review
- **Published**: Live and searchable
- **Archived**: Hidden but preserved

#### Advanced Options
- **Featured**: Show on KB home page
- **Sort Order**: Position within category
- **SEO Settings**: Meta description and keywords

## Editing Existing Articles

### Finding Articles to Edit
1. **Your Articles**: View all articles you've created
2. **All Articles**: Browse or search all content (if permitted)
3. **Categories**: Browse by topic area
4. **Status Filter**: Find drafts, published, etc.

### Edit Process
1. Click **Edit** button on any article
2. Make your changes in the editor
3. **Save Draft** to preserve changes
4. **Submit for Review** when ready
5. **Publish** to make changes live

### Version Control
- All changes are tracked automatically
- View previous versions and change history
- Restore earlier versions if needed
- Compare changes between versions

## Content Organization

### Categories

#### Creating Categories
1. Go to **Knowledge Base** > **Categories**
2. Click **Add Category**
3. Fill in details:
   - **Name**: Clear, descriptive category name
   - **Slug**: URL-friendly identifier
   - **Description**: Purpose and scope
   - **Parent Category**: For hierarchical organization
   - **Sort Order**: Display position

#### Category Best Practices
- Keep categories focused and distinct
- Avoid too many subcategories (max 3 levels deep)
- Use consistent naming conventions
- Regular review and consolidation

### Tags

#### Tag Strategy
- Create tags for common topics that cross categories
- Use consistent spelling and formatting
- Merge duplicate or similar tags regularly
- Popular tags: `getting-started`, `troubleshooting`, `api`, `billing`

#### Managing Tags
1. Go to **Knowledge Base** > **Tags**
2. View usage statistics
3. Merge duplicate tags
4. Update tag descriptions
5. Set tag colors for visual organization

## Content Workflow

### Draft → Review → Publish

#### Draft Stage
- Author creates and refines content
- Internal collaboration and feedback
- Content not visible to end users
- Can be saved and returned to later

#### Review Stage
- Content managers review for:
  - Accuracy and completeness
  - Writing quality and clarity
  - Formatting and style consistency
  - Technical correctness
- Feedback provided to authors
- Revisions made as needed

#### Published Stage
- Article goes live immediately
- Available in search results
- Notifications sent to subscribers
- Analytics tracking begins

### Content Approval Process

#### Who Can Approve
- Content managers with `kb.manage` permission
- System administrators
- Category owners (if assigned)

#### Review Criteria
✅ **Content Quality**
- Information is accurate and up-to-date
- Writing is clear and well-organized
- All links work correctly
- Screenshots are current and helpful

✅ **Style Consistency**
- Follows style guide conventions
- Consistent formatting and structure
- Appropriate tone for audience
- Proper use of headings and lists

✅ **Technical Accuracy**
- Code examples work as written
- API documentation is current
- Version numbers are correct
- Prerequisites are clearly stated

## Content Maintenance

### Regular Updates
- **Monthly Review**: Check high-traffic articles for accuracy
- **Quarterly Audit**: Review all published content
- **After Product Updates**: Update affected documentation
- **User Feedback**: Address reported issues promptly

### Analytics and Optimization
- **View Counts**: Identify popular content needing updates
- **Search Terms**: Find gaps in documentation
- **User Feedback**: Improve based on ratings and comments
- **Low Performance**: Update or consolidate underperforming articles

### Content Lifecycle
1. **Creation**: New article written and published
2. **Growth**: Article gains views and feedback
3. **Maintenance**: Regular updates and improvements
4. **Decline**: Article becomes outdated or less relevant
5. **Archive/Redirect**: Remove or redirect to current information

## Collaboration Features

### Comments and Feedback
- Users can rate articles as helpful/unhelpful
- Comments for questions and suggestions (coming soon)
- Internal notes for content team collaboration
- Feedback summary for authors and managers

### Team Coordination
- **Assignment**: Assign articles to specific authors
- **Due Dates**: Set deadlines for content creation/updates
- **Status Tracking**: Monitor progress across all content
- **Notifications**: Alert team members of changes and assignments

## Best Practices Summary

### Writing Tips
1. **Write for your audience**: Consider user knowledge level
2. **Be specific**: Avoid vague instructions
3. **Use active voice**: "Click the button" not "the button should be clicked"
4. **Test your steps**: Verify instructions actually work
5. **Keep it updated**: Review content regularly for accuracy

### Organization Tips
1. **Logical structure**: Order information from basic to advanced
2. **Cross-reference**: Link to related articles
3. **Consistent formatting**: Use standard patterns throughout
4. **Mobile-friendly**: Ensure content works on all devices
5. **Search optimization**: Include keywords users might search for

### Maintenance Tips
1. **Regular audits**: Schedule content review sessions
2. **User feedback**: Monitor and respond to article ratings
3. **Analytics review**: Use data to guide content improvements
4. **Version control**: Keep track of significant changes
5. **Backup strategy**: Ensure content is properly backed up

---

**Ready to start creating?** Begin with our [Article Template](link-to-template) or contact the content team at content@powernode.org for assistance.
},
    excerpt: 'Complete guide to creating, editing, and managing Knowledge Base articles and content.',
    tags: %w[knowledge-base content management tutorial admin],
    sort_order: 3
  }
]

# Create the Knowledge Base Usage articles
articles_data.each do |article_data|
  category = category_records[article_data[:category]]
  
  article = KnowledgeBaseArticle.find_or_create_by(slug: article_data[:slug]) do |article|
    article.title = article_data[:title]
    article.content = article_data[:content].strip
    article.excerpt = article_data[:excerpt]
    article.category = category
    article.author = admin_user
    article.status = 'published'
    article.is_public = true
    article.is_featured = article_data[:is_featured] || false
    article.sort_order = article_data[:sort_order] || 0
    article.published_at = Time.current
  end

  # Add tags
  if article_data[:tags]
    article.tags = article_data[:tags].map do |tag_name|
      tag_records[tag_name] || KnowledgeBaseTag.find_or_create_by(name: tag_name) do |tag|
        tag.slug = tag_name
      end
    end
  end
end

puts "✅ Created #{articles_data.length} Knowledge Base usage articles"

# Output summary
total_categories = KnowledgeBaseCategory.count
total_articles = KnowledgeBaseArticle.count
total_tags = KnowledgeBaseTag.count

puts "\n📊 Knowledge Base Summary:"
puts "   Categories: #{total_categories}"
puts "   Articles: #{total_articles}"
puts "   Tags: #{total_tags}"
puts "   Author: #{admin_user.email}"
puts "\n✅ Knowledge Base articles seeded successfully!"