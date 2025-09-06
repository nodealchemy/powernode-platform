# Powernode Platform - New Grouped Migrations

This directory contains a new set of grouped migrations that replace the existing scattered migrations with a cleaner, more organized structure. All tables use proper UUID primary keys and foreign key references.

## Migration Structure

### 20250905000001_create_core_foundation.rb
**Core platform foundation - Users, Accounts, Permissions, Workers**

**Tables Created:**
- `accounts` - Organization accounts with billing integration
- `users` - User accounts within organizations  
- `password_histories` - Password history tracking for security
- `blacklisted_tokens` - JWT token blacklisting
- `permissions` - Granular permission definitions
- `roles` - Role-based access control
- `role_permissions` - Role-permission junction table
- `user_roles` - User-role assignments
- `workers` - Background job workers with permissions
- `worker_roles` - Worker-role assignments
- `account_delegations` - Cross-account access delegation
- `delegation_permissions` - Delegation permission grants
- `invitations` - User invitation system
- `impersonation_sessions` - Admin impersonation tracking

**Key Features:**
- All UUIDs with proper PostgreSQL UUID types
- Comprehensive permission-based access control
- Security-focused design with audit trails
- Multi-tenancy support via account isolation

### 20250905000002_create_billing_subscription_system.rb
**Complete billing and subscription management system**

**Tables Created:**
- `plans` - Subscription plan definitions
- `subscriptions` - Active subscriptions
- `payment_methods` - Customer payment methods
- `payments` - Payment transaction records
- `invoices` - Invoice management
- `invoice_line_items` - Detailed invoice items
- `revenue_snapshots` - Revenue analytics
- `gateway_configurations` - Payment gateway settings
- `missing_payment_logs` - Reconciliation tracking

**Key Features:**
- Multi-gateway support (Stripe, PayPal)
- Complete subscription lifecycle management
- Revenue analytics and reporting
- Payment reconciliation system

### 20250905000003_create_marketplace_infrastructure.rb
**Application marketplace and API management**

**Tables Created:**
- `marketplace_categories` - App categorization
- `apps` - Core application registry
- `app_plans` - App-specific pricing plans
- `app_features` - Feature flags and capabilities
- `marketplace_listings` - Public marketplace presence
- `app_subscriptions` - App subscription instances
- `app_endpoints` - API endpoint definitions
- `app_webhooks` - Webhook configurations
- `app_endpoint_calls` - API usage tracking
- `app_webhook_deliveries` - Webhook delivery logs
- `app_analytics` - Application metrics

**Key Features:**
- Complete app lifecycle management
- API usage tracking and analytics
- Webhook delivery system
- Marketplace review and approval workflow

### 20250905000004_create_review_system.rb
**Comprehensive review and rating system**

**Tables Created:**
- `app_reviews` - Core review functionality with multi-dimensional ratings
- `review_helpfulness_votes` - Community feedback on reviews
- `review_responses` - Developer responses to reviews
- `review_media_attachments` - Images/videos in reviews
- `review_aggregation_cache` - Performance optimization
- `review_moderation_actions` - Moderation audit trail

**Key Features:**
- Multi-dimensional rating system (usability, features, support, value)
- Quality scoring and sentiment analysis
- Media attachment support
- Comprehensive moderation tools
- Performance-optimized aggregation cache

### 20250905000005_create_notification_system.rb
**Multi-channel notification and communication system**

**Tables Created:**
- `email_deliveries` - Email tracking and delivery status
- `webhook_endpoints` - Webhook management
- `webhook_events` - Event tracking
- `webhook_deliveries` - Delivery status tracking
- `background_jobs` - Job queue management
- `reconciliation_reports` - Payment reconciliation reporting
- `reconciliation_flags` - Issue flagging system
- `reconciliation_investigations` - Investigation workflow

**Key Features:**
- Multi-channel delivery (email, webhooks, background jobs)
- Comprehensive delivery tracking
- Payment reconciliation workflow
- Retry logic and failure handling

### 20250905000006_create_admin_system_management.rb
**Administrative interface and system management**

**Tables Created:**
- `admin_settings` - System configuration
- `site_settings` - Public site configuration
- `pages` - Static content management
- `api_keys` - API access management
- `api_key_usages` - API usage tracking
- `audit_logs` - System audit trail
- `system_health_checks` - System monitoring
- `system_operations` - Operation tracking
- `database_backups` - Backup management
- `database_restores` - Restore operations
- `scheduled_tasks` - Task scheduling
- `task_executions` - Execution history
- `scheduled_reports` - Report scheduling
- `report_requests` - On-demand reports
- `worker_activities` - Worker monitoring
- `gateway_connection_jobs` - Gateway connection management

**Key Features:**
- Comprehensive system administration
- Audit logging and compliance
- Automated backup and restore
- Task scheduling and monitoring
- Report generation system

### 20250905000007_create_knowledge_base_system.rb
**Knowledge base and documentation system**

**Tables Created:**
- `knowledge_base_categories` - Article categorization
- `knowledge_base_tags` - Flexible tagging system
- `knowledge_base_articles` - Core content with full-text search
- `knowledge_base_article_tags` - Article-tag associations
- `knowledge_base_attachments` - File attachments
- `knowledge_base_comments` - Community comments
- `knowledge_base_article_views` - Analytics tracking
- `knowledge_base_workflows` - Editorial workflow

**Key Features:**
- Full-text search with PostgreSQL tsvector
- Editorial workflow management
- Analytics and engagement tracking
- Community features (comments, voting)
- File attachment support

## UUID Strategy

All tables use:
- **Primary Keys**: `t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }`
- **Foreign Keys**: `t.references :table, null: false, foreign_key: true, type: :uuid`
- **Native PostgreSQL UUID types** for optimal performance and compatibility

## Migration Usage

To use these new migrations:

1. **Backup existing data** if migrating from old schema
2. **Drop existing database** for clean setup:
   ```bash
   rails db:drop && rails db:create
   ```
3. **Copy migrations** to the main migrate directory:
   ```bash
   cp db/migrate_new/* db/migrate/
   rm -rf db/migrate_new
   ```
4. **Run migrations**:
   ```bash
   rails db:migrate
   rails db:seed
   ```

## Key Improvements

✅ **Proper UUID Types**: All tables use native PostgreSQL UUID types instead of string-based UUIDs
✅ **Logical Grouping**: Related tables are grouped in the same migration file
✅ **Comprehensive Constraints**: All tables have appropriate check constraints and validations
✅ **Performance Optimized**: Proper indexing strategy for all tables
✅ **Security Focused**: Audit trails, permission systems, and secure token handling
✅ **Scalability Ready**: Designed for multi-tenancy and high-volume operations

## Table Count by Migration

- **Core Foundation**: 13 tables
- **Billing System**: 9 tables  
- **Marketplace**: 11 tables
- **Review System**: 6 tables
- **Notifications**: 9 tables
- **Admin/System**: 17 tables
- **Knowledge Base**: 8 tables

**Total**: 73 tables (compared to 67 in original schema)

The new structure provides better organization, proper UUID handling, and comprehensive feature coverage for the Powernode platform.