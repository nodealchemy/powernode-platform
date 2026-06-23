# frozen_string_literal: true

# Content Management Articles
# Documentation for pages, files, and knowledge base

puts "  📝 Creating Content Management articles..."

content_cat = KnowledgeBase::Category.find_by!(slug: "content-management")

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

Navigate to **Content > Pages** to view all pages, filter by status, search by title, and sort by date.

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

Track page changes: view revision history, compare versions, restore previous versions, and see who made changes.

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

article = KnowledgeBase::Article.find_or_initialize_by(source_key: "managing-pages-content", account_id: nil)
article.assign_attributes(
  title: "Managing Pages and Content",
  slug: "managing-pages-content",
  category: content_cat,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Create and manage public pages with Markdown content, SEO optimization, versioning, and publishing workflows.",
  content: pages_content,
  views_count: article.views_count || 0,
  likes_count: article.likes_count || 0,
  published_at: article.published_at || Time.current
)
article.author_id = nil
article.save!

puts "    ✅ Managing Pages and Content"

# Article 22: File Storage and Management
files_content = <<~MARKDOWN
# File Storage and Management

Upload, organize, and manage files with Powernode's file storage system.

## My Files Dashboard

Navigate to **Content > My Files** to view uploaded files, organize them in folders, search and filter, and manage storage.

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

1. Click **New Folder**
2. Enter folder name
3. Move files into folder
4. Nest folders as needed

### Moving Files

Drag to a folder, use the move action, or bulk-move selected files.

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

View storage usage: total used, available space, usage by folder, and large files.

---

For knowledge base articles, see [Knowledge Base Administration](/kb/knowledge-base-administration).
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(source_key: "file-storage-management", account_id: nil)
article.assign_attributes(
  title: "File Storage and Management",
  slug: "file-storage-management",
  category: content_cat,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Upload and organize files with folder structures, storage providers (S3, local), sharing options, and quota management.",
  content: files_content,
  views_count: article.views_count || 0,
  likes_count: article.likes_count || 0,
  published_at: article.published_at || Time.current
)
article.author_id = nil
article.save!

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

Navigate to **Content > Knowledge Base** for total articles, articles by status, recent views, and search analytics.

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

Drag categories to reorder. This affects the navigation display, updates sort order, and saves automatically.

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

Mark important articles to surface them on the homepage, highlight them in search, and show them in category headers.

## Search Optimization

### Tags

Relevant tags improve searchability, enable filtering, and group related content.

### SEO Settings

```yaml
Article SEO:
  Meta Title: Search-optimized title
  Meta Description: Search snippet
  URL Slug: custom-url-slug
```

### Search Analytics

Track search behavior: top search terms, no-result queries, article click-through, and search success rate.

## Article Analytics

### View Tracking

Monitor article performance: view count, unique viewers, average time on page, and exit rate.

### Feedback

Collect helpful/not-helpful ratings, comments (if enabled), and improvement suggestions.

## Best Practices

- **Content quality**: Clear, concise writing; step-by-step instructions; screenshots where helpful; regular updates.
- **Organization**: Logical category structure, consistent naming, cross-linked articles, featured important content.

---

For public page management, see [Managing Pages and Content](/kb/managing-pages-content).
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(source_key: "knowledge-base-administration", account_id: nil)
article.assign_attributes(
  title: "Knowledge Base Administration",
  slug: "knowledge-base-administration",
  category: content_cat,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Manage knowledge base categories, create articles with proper workflow, optimize search, and track analytics.",
  content: kb_admin_content,
  views_count: article.views_count || 0,
  likes_count: article.likes_count || 0,
  published_at: article.published_at || Time.current
)
article.author_id = nil
article.save!

puts "    ✅ Knowledge Base Administration"

puts "  ✅ Content Management articles created (3 articles)"
