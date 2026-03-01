# frozen_string_literal: true

# Content Management Articles
# Documentation for pages, files, and knowledge base

puts "  📝 Creating Content Management articles..."

content_cat = KnowledgeBase::Category.find_by!(slug: "content-management")
author = User.find_by!(email: "admin@powernode.org")

# Article 21: Managing Pages and Content
pages_content = <<~MARKDOWN
# Managing Pages and Content

Create and manage public-facing pages for your Powernode platform.

## Page Overview

### Page Types

| Type | Purpose | Example |
|------|---------|---------|
| Public | Visible to all | Welcome, About |
| Private | Authenticated users | Dashboard help |
| System | Platform pages | Terms, Privacy |

### Page List

Navigate to **Content > Pages**:
- View all pages
- Filter by status
- Search by title
- Sort by date

## Creating Pages

### New Page

1. Navigate to **Content > Pages**
2. Click **Create Page**
3. Enter page details:

```yaml
Page Configuration:
  Title: Page title
  Slug: url-friendly-slug
  Status: draft | published | archived
  Content: Markdown content
  SEO:
    Meta Title: SEO title
    Meta Description: Search description
    Keywords: keyword1, keyword2
```

### Markdown Editor

Write content in Markdown:
- Headers (# H1, ## H2)
- Lists (- item, 1. item)
- Links ([text](url))
- Images (![alt](url))
- Code blocks
- Tables

### Page Status

| Status | Visibility |
|--------|------------|
| Draft | Not visible |
| Published | Publicly visible |
| Archived | Hidden, preserved |

## SEO Settings

### Meta Configuration

```yaml
SEO Settings:
  Meta Title: Custom title for search
  Meta Description: 155 characters max
  Keywords: Comma-separated
  Canonical URL: Primary URL
  No Index: Hide from search
```

### Best Practices

- Descriptive titles (< 60 chars)
- Compelling descriptions (< 155 chars)
- Relevant keywords
- Unique content per page

## Page Versioning

### Version History

Track page changes:
- View revision history
- Compare versions
- Restore previous versions
- See who made changes

### Restore Version

1. Open page editor
2. Click **Version History**
3. Select version
4. Click **Restore**
5. Save page

## Publishing Workflow

### Draft to Published

```
Create Draft → Review → Approve → Publish
     ↓            ↓         ↓         ↓
   Author     Reviewer   Approver   Live
```

### Schedule Publishing

Set future publish date:
1. Create page content
2. Set status to "Scheduled"
3. Choose publish date/time
4. Page goes live automatically

---

For file uploads, see [File Storage and Management](/kb/file-storage-management).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "managing-pages-content") do |article|
  article.title = "Managing Pages and Content"
  article.category = content_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Create and manage public pages with Markdown content, SEO optimization, versioning, and publishing workflows."
  article.content = pages_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Managing Pages and Content"

# Article 22: File Storage and Management
files_content = <<~MARKDOWN
# File Storage and Management

Upload, organize, and manage files with Powernode's file storage system.

## My Files Dashboard

### Overview

Navigate to **Content > My Files**:
- View uploaded files
- Organize in folders
- Search and filter
- Manage storage

### File List

| Column | Description |
|--------|-------------|
| Name | File name |
| Type | File format |
| Size | File size |
| Uploaded | Upload date |
| Actions | View, download, delete |

## Uploading Files

### Upload Methods

1. **Drag and Drop** - Drop files on upload area
2. **Click to Browse** - Select from file system
3. **API Upload** - Programmatic upload

### Supported Formats

| Category | Formats |
|----------|---------|
| Documents | PDF, DOC, DOCX, TXT |
| Images | JPEG, PNG, GIF, SVG |
| Spreadsheets | XLS, XLSX, CSV |
| Archives | ZIP, TAR, GZ |

### Upload Limits

```yaml
Upload Limits:
  Max File Size: 50MB (default)
  Max Files: 100 per upload
  Total Storage: Based on plan
```

## File Organization

### Folders

Create folder structure:
1. Click **New Folder**
2. Enter folder name
3. Move files into folder
4. Nest folders as needed

### Moving Files

- Drag to folder
- Use move action
- Bulk move selected

## Storage Configuration

### Storage Providers

| Provider | Use Case |
|----------|----------|
| Local | Development |
| Amazon S3 | Production |
| MinIO | Self-hosted |
| Azure Blob | Microsoft stack |

### S3 Configuration

```yaml
S3 Settings:
  Bucket: your-bucket-name
  Region: us-east-1
  Access Key: (configured securely)
  Secret Key: (configured securely)
  Path Prefix: uploads/
```

## File Sharing

### Share Links

Generate shareable links:
1. Select file
2. Click **Share**
3. Configure options:
   - Expiration date
   - Password protection
   - Download limit
4. Copy link

### Permissions

| Permission | Access |
|------------|--------|
| Public | Anyone with link |
| Authenticated | Logged-in users |
| Private | Specific users |

## Storage Quotas

### Plan Limits

| Plan | Storage |
|------|---------|
| Starter | 5 GB |
| Professional | 50 GB |
| Enterprise | Unlimited |

### Monitoring Usage

View storage usage:
- Total used
- Available space
- Usage by folder
- Large files

---

For knowledge base articles, see [Knowledge Base Administration](/kb/knowledge-base-administration).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "file-storage-management") do |article|
  article.title = "File Storage and Management"
  article.category = content_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Upload and organize files with folder structures, storage providers (S3, local), sharing options, and quota management."
  article.content = files_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ File Storage and Management"

# Article 23: Knowledge Base Administration
kb_admin_content = <<~MARKDOWN
# Knowledge Base Administration

Manage your knowledge base with categories, articles, and search optimization.

## Knowledge Base Overview

### Structure

```
Knowledge Base
├── Category 1
│   ├── Article 1.1
│   └── Article 1.2
├── Category 2
│   ├── Article 2.1
│   └── Article 2.2
└── Category 3
    └── Article 3.1
```

### Dashboard

Navigate to **Content > Knowledge Base**:
- Total articles
- Articles by status
- Recent views
- Search analytics

## Category Management

### Creating Categories

1. Navigate to **Knowledge Base > Categories**
2. Click **Add Category**
3. Configure:

```yaml
Category Settings:
  Name: Category name
  Slug: url-slug
  Description: Category description
  Icon: Optional icon
  Order: Display order
  Visibility: public | private
```

### Reordering

Drag categories to reorder:
- Affects navigation display
- Updates sort order
- Saves automatically

## Article Management

### Creating Articles

1. Navigate to **Knowledge Base > Articles**
2. Click **New Article**
3. Enter details:

```yaml
Article Configuration:
  Title: Article title
  Category: Select category
  Status: draft | review | published | archived
  Featured: true | false
  Content: Markdown content
  Tags: tag1, tag2, tag3
  Excerpt: Brief summary (auto-generated if blank)
```

### Article Status Workflow

```
Draft → Review → Published
  ↓        ↓         ↓
Author   Editor   Public
                    ↓
               Archived
```

### Featured Articles

Mark important articles:
- Appear on homepage
- Highlighted in search
- Shown in category headers

## Search Optimization

### Tags

Add relevant tags:
- Improve searchability
- Enable filtering
- Group related content

### SEO Settings

```yaml
Article SEO:
  Meta Title: Search-optimized title
  Meta Description: Search snippet
  URL Slug: custom-url-slug
```

### Search Analytics

Track search behavior:
- Top search terms
- No-result queries
- Article click-through
- Search success rate

## Article Analytics

### View Tracking

Monitor article performance:
- View count
- Unique viewers
- Average time on page
- Exit rate

### Feedback

Collect article feedback:
- Helpful/not helpful ratings
- Comments (if enabled)
- Improvement suggestions

## Best Practices

### Content Quality

- Clear, concise writing
- Step-by-step instructions
- Screenshots where helpful
- Regular updates

### Organization

- Logical category structure
- Consistent naming
- Cross-linking articles
- Featured important content

---

For public page management, see [Managing Pages and Content](/kb/managing-pages-content).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "knowledge-base-administration") do |article|
  article.title = "Knowledge Base Administration"
  article.category = content_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Manage knowledge base categories, create articles with proper workflow, optimize search, and track analytics."
  article.content = kb_admin_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Knowledge Base Administration"

puts "  ✅ Content Management articles created (3 articles)"
