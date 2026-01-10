# frozen_string_literal: true

# Permission System V2 - Three-tier Architecture
# resource.action - Standard resource operations for regular users
# admin.action - Administrative operations for admin users
# system.action - System-level operations for workers and automation

module Permissions
  # Resource Permissions - User-facing operations
  RESOURCE_PERMISSIONS = {
    # User Management
    "user.read" => "View user profiles",
    "user.edit_self" => "Edit own profile",
    "user.delete_self" => "Delete own account",

    # Team Management
    "team.read" => "View team members",
    "team.invite" => "Invite team members",
    "team.remove" => "Remove team members",
    "team.assign_roles" => "Assign roles to team members",

    # User Impersonation
    "users.impersonate" => "Impersonate other users",

    # Billing & Subscriptions
    "billing.read" => "View billing information",
    "billing.update" => "Update payment methods",
    "billing.cancel" => "Cancel subscriptions",
    "plans.read" => "View subscription plans",
    "plans.create" => "Create subscription plans",
    "plans.manage" => "Manage subscription plans",
    "invoice.read" => "View invoices",
    "invoice.download" => "Download invoices",

    # Content Management
    "page.create" => "Create pages",
    "page.read" => "View pages",
    "page.edit" => "Edit pages",
    "page.delete" => "Delete pages",
    "page.publish" => "Publish pages",

    # Analytics & Reports
    "analytics.read" => "View analytics dashboard",
    "analytics.export" => "Export analytics data",
    "report.read" => "View reports",
    "report.generate" => "Generate reports",
    "report.export" => "Export reports",

    # API Access
    "api.read" => "Read API access",
    "api.write" => "Write API access",
    "api.manage_keys" => "Manage API keys",

    # Webhooks
    "webhook.read" => "View webhooks",
    "webhook.create" => "Create webhooks",
    "webhook.edit" => "Edit webhooks",
    "webhook.delete" => "Delete webhooks",

    # Audit Logs
    "audit.read" => "View audit logs",
    "audit.export" => "Export audit logs",
    "audit.manage" => "Manage audit logs",

    # Knowledge Base
    "kb.read" => "View published knowledge base articles",
    "kb.create" => "Create knowledge base articles",
    "kb.edit" => "Edit knowledge base articles",
    "kb.delete" => "Delete knowledge base articles",
    "kb.publish" => "Publish knowledge base articles",
    "kb.manage" => "Manage knowledge base categories and settings",
    "kb.moderate" => "Moderate knowledge base comments",

    # Marketplace - Apps
    "app.read" => "View marketplace apps",
    "app.create" => "Create marketplace apps",
    "app.edit" => "Edit own apps",
    "app.delete" => "Delete own apps",
    "app.publish" => "Publish own apps",
    "app.manage_features" => "Manage app features",
    "app.manage_plans" => "Manage app plans",
    "app.read_analytics" => "View app analytics",

    # Marketplace - App Subscriptions
    "subscription.read" => "View app subscriptions",
    "subscription.create" => "Subscribe to apps",
    "subscription.manage" => "Manage subscriptions",
    "subscription.cancel" => "Cancel subscriptions",
    "subscription.upgrade" => "Upgrade subscriptions",
    "subscription.read_usage" => "View subscription usage",

    # Marketplace - Reviews
    "review.read" => "View app reviews",
    "review.create" => "Write app reviews",
    "review.edit" => "Edit own reviews",
    "review.delete" => "Delete own reviews",
    "review.moderate" => "Moderate reviews",

    # Marketplace - Publishing (Feature Templates)
    "marketplace.publish" => "Publish feature templates to the marketplace",
    "marketplace.templates.read" => "View own published marketplace templates",
    "marketplace.templates.manage" => "Manage own marketplace templates",

    # Marketplace - Listings
    "listing.read" => "View marketplace listings",
    "listing.create" => "Create marketplace listings",
    "listing.edit" => "Edit own listings",
    "listing.delete" => "Delete own listings",

    # AI Orchestration - Providers
    "ai.providers.read" => "View available AI providers",
    "ai.providers.create" => "Create AI providers",
    "ai.providers.update" => "Update AI providers",
    "ai.providers.delete" => "Delete AI providers",
    "ai.providers.test" => "Test AI provider connections",

    # AI Orchestration - Credentials
    "ai.credentials.read" => "View AI provider credentials",
    "ai.credentials.create" => "Create AI provider credentials",
    "ai.credentials.update" => "Update AI provider credentials",
    "ai.credentials.delete" => "Delete AI provider credentials",
    "ai.credentials.test" => "Test AI provider credentials",

    # AI Orchestration - Agents
    "ai.agents.read" => "View AI agents",
    "ai.agents.create" => "Create AI agents",
    "ai.agents.update" => "Update own AI agents",
    "ai.agents.delete" => "Delete own AI agents",
    "ai.agents.execute" => "Execute AI agents",
    "ai.agents.clone" => "Clone AI agents",

    # AI Orchestration - Executions
    "ai.executions.read" => "View AI agent executions",
    "ai.executions.cancel" => "Cancel own AI executions",
    "ai.executions.retry" => "Retry failed AI executions",

    # AI Orchestration - Conversations
    "ai.conversations.read" => "View AI conversations",
    "ai.conversations.create" => "Create AI conversations",
    "ai.conversations.participate" => "Participate in AI conversations",
    "ai.conversations.manage" => "Manage own AI conversations",

    # AI Orchestration - Messages
    "ai.messages.read" => "View AI messages",
    "ai.messages.create" => "Send AI messages",
    "ai.messages.edit" => "Edit own AI messages",
    "ai.messages.delete" => "Delete own AI messages",

    # AI Orchestration - Workflows
    "ai.workflows.read" => "View AI workflows",
    "ai.workflows.create" => "Create AI workflows",
    "ai.workflows.update" => "Update own AI workflows",
    "ai.workflows.delete" => "Delete own AI workflows",
    "ai.workflows.execute" => "Execute AI workflows",
    "ai.workflows.clone" => "Clone AI workflows",
    "ai.workflows.import" => "Import AI workflows",
    "ai.workflows.export" => "Export AI workflows",

    # AI Orchestration - Workflow Executions
    "ai.workflow_executions.read" => "View AI workflow executions",
    "ai.workflow_executions.cancel" => "Cancel own workflow executions",
    "ai.workflow_executions.retry" => "Retry failed workflow executions",

    # AI Orchestration - Analytics
    "ai.analytics.read" => "View AI usage analytics",
    "ai.analytics.export" => "Export AI analytics data",

    # AI Orchestration - Templates
    "ai.templates.read" => "View AI agent templates",
    "ai.templates.install" => "Install AI agent templates",
    "ai.templates.create" => "Create AI agent templates",
    "ai.templates.publish" => "Publish AI agent templates",

    # MCP (Model Context Protocol) - Account-scoped
    "mcp.servers.read" => "View MCP servers",
    "mcp.servers.write" => "Manage MCP servers (create, update, delete, connect, disconnect)",
    "mcp.tools.read" => "View MCP tools",
    "mcp.tools.execute" => "Execute MCP tools",
    "mcp.executions.read" => "View MCP tool executions",
    "mcp.executions.write" => "Manage MCP tool executions (cancel)",

    # File Management
    "files.read" => "View files",
    "files.create" => "Upload files",
    "files.update" => "Update file metadata",
    "files.delete" => "Delete files",
    "files.download" => "Download files",
    "files.share" => "Share files externally",
    "files.version" => "Manage file versions",
    "files.tag" => "Tag and organize files",

    # Storage Configuration
    "storage.read" => "View storage configurations",
    "storage.create" => "Create storage configurations",
    "storage.update" => "Update storage configurations",
    "storage.delete" => "Delete storage configurations",
    "storage.test" => "Test storage connections",

    # Git Provider Management
    "git.providers.read" => "View Git providers",
    "git.providers.create" => "Create Git providers",
    "git.providers.update" => "Update Git providers",
    "git.providers.delete" => "Delete Git providers",

    # Git Credentials
    "git.credentials.read" => "View Git credentials",
    "git.credentials.create" => "Create Git credentials",
    "git.credentials.update" => "Update Git credentials",
    "git.credentials.delete" => "Delete Git credentials",
    "git.credentials.test" => "Test Git credentials",

    # Git Repositories
    "git.repositories.read" => "View Git repositories",
    "git.repositories.delete" => "Delete Git repositories",
    "git.repositories.sync" => "Sync Git repositories",
    "git.repositories.webhooks.manage" => "Manage repository webhooks",

    # Git CI/CD Pipelines
    "git.pipelines.read" => "View CI/CD pipelines",
    "git.pipelines.trigger" => "Trigger CI/CD pipelines",
    "git.pipelines.cancel" => "Cancel CI/CD pipelines",
    "git.pipelines.logs" => "View pipeline logs",

    # Git Webhook Events
    "git.webhooks.read" => "View Git webhook events",

    # Git CI/CD Runners
    "git.runners.read" => "View CI/CD runners",
    "git.runners.manage" => "Manage CI/CD runners (delete, labels)",
    "git.runners.token" => "Generate runner registration/removal tokens",

    # Git Pipeline Schedules
    "git.schedules.read" => "View pipeline schedules",
    "git.schedules.manage" => "Create, edit, delete pipeline schedules",

    # Git Pipeline Approvals
    "git.approvals.read" => "View pipeline approval requests",
    "git.approvals.manage" => "Approve or reject pipeline requests",

    # Integration Templates & Instances
    "integrations.read" => "View integration templates and instances",
    "integrations.create" => "Create integration instances",
    "integrations.update" => "Update integration instances",
    "integrations.delete" => "Delete integration instances",
    "integrations.execute" => "Execute integrations",
    "integrations.credentials.read" => "View integration credentials",
    "integrations.credentials.create" => "Create integration credentials",
    "integrations.credentials.update" => "Update integration credentials",
    "integrations.credentials.delete" => "Delete integration credentials",

    # AI Persistent Context
    "ai.context.read" => "View AI persistent contexts",
    "ai.context.create" => "Create AI persistent contexts",
    "ai.context.update" => "Update AI persistent contexts",
    "ai.context.delete" => "Delete AI persistent contexts",
    "ai.context.search" => "Search AI context entries",
    "ai.context.export" => "Export AI contexts",
    "ai.context.import" => "Import AI contexts",

    # AI Agent Memory
    "ai.memory.read" => "View AI agent memory",
    "ai.memory.write" => "Write to AI agent memory",
    "ai.memory.manage" => "Manage AI agent memory (clear, archive)"
  }.freeze

  # Admin Permissions - Administrative operations
  ADMIN_PERMISSIONS = {
    # General Admin Access
    "admin.access" => "Access admin panel and features",

    # User Administration
    "admin.user.read" => "View all users",
    "admin.user.create" => "Create users",
    "admin.user.edit" => "Edit any user",
    "admin.user.delete" => "Delete users",
    "admin.user.impersonate" => "Impersonate users",
    "admin.user.suspend" => "Suspend users",

    # Account Administration
    "admin.account.read" => "View all accounts",
    "admin.account.create" => "Create accounts",
    "admin.account.edit" => "Edit accounts",
    "admin.account.delete" => "Delete accounts",
    "admin.account.suspend" => "Suspend accounts",

    # Role & Permission Management
    "admin.role.read" => "View roles",
    "admin.role.create" => "Create roles",
    "admin.role.edit" => "Edit roles",
    "admin.role.delete" => "Delete roles",
    "admin.role.assign" => "Assign roles",

    # Billing Administration
    "admin.billing.read" => "View all billing",
    "admin.billing.override" => "Override billing",
    "admin.billing.refund" => "Process refunds",
    "admin.billing.credit" => "Issue credits",
    "admin.billing.manage_gateways" => "Manage payment gateways",

    # System Settings
    "admin.settings.read" => "View settings",
    "admin.settings.edit" => "Edit settings",
    "admin.settings.security" => "Security settings",
    "admin.settings.email" => "Email settings",
    "admin.settings.payment" => "Payment gateway settings",

    # Audit & Compliance
    "admin.audit.read" => "View all audit logs",
    "admin.audit.export" => "Export audit logs",
    "admin.audit.delete" => "Delete audit logs",
    "admin.audit.manage" => "Manage audit system",
    "admin.compliance.read" => "View compliance",
    "admin.compliance.report" => "Generate compliance reports",

    # Maintenance Operations
    "admin.maintenance.mode" => "Toggle maintenance mode",
    "admin.maintenance.backup" => "Manage backups",
    "admin.maintenance.restore" => "Restore from backup",
    "admin.maintenance.cleanup" => "Run cleanup operations",
    "admin.maintenance.tasks" => "Manage scheduled tasks",

    # Knowledge Base Administration
    "admin.kb.read" => "View all knowledge base content",
    "admin.kb.manage" => "Manage knowledge base system",
    "admin.kb.moderate" => "Moderate all content and comments",
    "admin.kb.analytics" => "Access knowledge base analytics",
    "admin.kb.settings" => "Configure knowledge base settings",

    # Worker Management - consolidated under system.workers namespace

    # Marketplace Administration
    "admin.marketplace.read" => "View marketplace management",
    "admin.marketplace.manage" => "Manage marketplace settings",
    "admin.marketplace.export" => "Export marketplace data",
    "admin.marketplace.templates.review" => "Review and approve marketplace template submissions",
    "admin.marketplace.templates.feature" => "Feature marketplace templates",
    "admin.app.read" => "View all apps",
    "admin.app.edit" => "Edit any app",
    "admin.app.delete" => "Delete any app",
    "admin.app.approve" => "Approve apps for publication",
    "admin.app.suspend" => "Suspend apps",
    "admin.listing.read" => "View all listings",
    "admin.listing.edit" => "Edit any listing",
    "admin.listing.delete" => "Delete any listing",
    "admin.listing.approve" => "Approve listings",
    "admin.listing.feature" => "Feature listings",
    "admin.review.read" => "View all reviews",
    "admin.review.moderate" => "Moderate reviews",
    "admin.review.delete" => "Delete reviews",
    "admin.subscription.read" => "View all subscriptions",
    "admin.subscription.manage" => "Manage any subscription",

    # Circuit Breaker Administration
    "admin.circuit_breakers.read" => "View circuit breakers",
    "admin.circuit_breakers.write" => "Manage circuit breakers (create, update, delete, reset)",

    # Validation Rules Administration
    "admin.validation_rules.read" => "View validation rules",
    "admin.validation_rules.write" => "Manage validation rules (create, update, delete, enable/disable)",

    # AI Orchestration Administration
    "admin.ai.read" => "View all AI system data",
    "admin.ai.manage" => "Manage AI system settings",
    "admin.ai.providers.read" => "View all AI providers",
    "admin.ai.providers.create" => "Create AI providers",
    "admin.ai.providers.edit" => "Edit any AI provider",
    "admin.ai.providers.delete" => "Delete AI providers",
    "admin.ai.providers.sync" => "Sync AI provider models",
    "admin.ai.credentials.read" => "View all AI credentials",
    "admin.ai.credentials.manage" => "Manage any AI credentials",
    "admin.ai.credentials.rotate" => "Rotate encryption keys",
    "admin.ai.agents.read" => "View all AI agents",
    "admin.ai.agents.edit" => "Edit any AI agent",
    "admin.ai.agents.delete" => "Delete any AI agent",
    "admin.ai.executions.read" => "View all AI executions",
    "admin.ai.executions.manage" => "Manage any AI execution",
    "admin.ai.conversations.read" => "View all AI conversations",
    "admin.ai.conversations.moderate" => "Moderate AI conversations",
    "admin.ai.workflows.read" => "View all AI workflows",
    "admin.ai.workflows.edit" => "Edit any AI workflow",
    "admin.ai.workflows.delete" => "Delete any AI workflow",
    "admin.ai.workflow_executions.read" => "View all workflow executions",
    "admin.ai.workflow_executions.manage" => "Manage any workflow execution",
    "admin.ai.analytics.read" => "View AI system analytics",
    "admin.ai.monitoring.read" => "View AI system monitoring",
    "admin.ai.templates.approve" => "Approve AI templates for marketplace",
    "admin.ai.marketplace.manage" => "Manage AI marketplace",

    # File Management Administration
    "admin.files.read" => "View all files across accounts",
    "admin.files.manage" => "Manage any file",
    "admin.files.delete" => "Delete any file",
    "admin.files.recover" => "Recover deleted files",
    "admin.files.audit" => "View file access audit logs",
    "admin.storage.read" => "View all storage configurations",
    "admin.storage.create" => "Create system storage configurations",
    "admin.storage.edit" => "Edit any storage configuration",
    "admin.storage.delete" => "Delete storage configurations",
    "admin.storage.manage" => "Full storage provider management",
    "admin.storage.manage_quota" => "Manage storage quotas",
    "admin.storage.health" => "Monitor storage health",

    # Git Administration
    "admin.git.providers.read" => "View all Git providers",
    "admin.git.providers.manage" => "Manage all Git providers",
    "admin.git.credentials.read" => "View all Git credentials",
    "admin.git.credentials.manage" => "Manage all Git credentials",
    "admin.git.repositories.read" => "View all Git repositories",
    "admin.git.repositories.manage" => "Manage all Git repositories",
    "admin.git.webhooks.read" => "View all Git webhook events",
    "admin.git.webhooks.manage" => "Manage Git webhook events",
    "admin.git.pipelines.read" => "View all CI/CD pipelines",
    "admin.git.pipelines.manage" => "Manage all CI/CD pipelines",
    "admin.git.runners.read" => "View all CI/CD runners",
    "admin.git.runners.manage" => "Manage all CI/CD runners",
    "admin.git.schedules.read" => "View all pipeline schedules",
    "admin.git.schedules.manage" => "Manage all pipeline schedules",
    "admin.git.approvals.read" => "View all pipeline approvals",
    "admin.git.approvals.manage" => "Manage all pipeline approvals",

    # Integration Administration
    "admin.integrations.read" => "View all integration instances",
    "admin.integrations.manage" => "Manage all integration instances",
    "admin.integrations.templates.read" => "View all integration templates",
    "admin.integrations.templates.create" => "Create integration templates",
    "admin.integrations.templates.edit" => "Edit integration templates",
    "admin.integrations.templates.delete" => "Delete integration templates",
    "admin.integrations.templates.publish" => "Publish/unpublish integration templates",
    "admin.integrations.credentials.read" => "View all integration credentials",
    "admin.integrations.credentials.manage" => "Manage all integration credentials",
    "admin.integrations.executions.read" => "View all integration executions",
    "admin.integrations.executions.manage" => "Manage all integration executions",

    # AI Context Administration
    "admin.ai.context.read" => "View all AI persistent contexts",
    "admin.ai.context.manage" => "Manage all AI persistent contexts",
    "admin.ai.context.delete" => "Delete any AI context",
    "admin.ai.context.export" => "Export all AI contexts",
    "admin.ai.memory.read" => "View all AI agent memory",
    "admin.ai.memory.manage" => "Manage all AI agent memory"
  }.freeze

  # System Permissions - Worker & automation operations
  SYSTEM_PERMISSIONS = {
    # System Administration
    "system.admin" => "Full system administrator access (grants all permissions)",

    # Worker Operations
    "system.worker.register" => "Register as worker",
    "system.worker.heartbeat" => "Send heartbeats",
    "system.worker.report" => "Report status",
    "system.worker.execute" => "Execute jobs",

    # Worker Management (for frontend admin interface)
    "system.workers.read" => "View worker management interface",
    "system.workers.create" => "Create new workers",
    "system.workers.edit" => "Edit worker configurations",
    "system.workers.delete" => "Delete workers",
    "system.workers.suspend" => "Suspend workers",
    "system.workers.activate" => "Activate workers",
    "system.workers.regenerate" => "Regenerate worker tokens",

    # Database Operations
    "system.database.read" => "Direct database read",
    "system.database.write" => "Direct database write",
    "system.database.backup" => "Perform backups",
    "system.database.restore" => "Perform restores",
    "system.database.optimize" => "Optimize database",

    # Job Processing
    "system.jobs.process" => "Process background jobs",
    "system.jobs.retry" => "Retry failed jobs",
    "system.jobs.cancel" => "Cancel jobs",
    "system.jobs.schedule" => "Schedule jobs",

    # System Monitoring
    "system.health.check" => "Perform health checks",
    "system.health.report" => "Report health status",
    "system.metrics.collect" => "Collect metrics",
    "system.metrics.report" => "Report metrics",

    # Cache & Storage
    "system.cache.read" => "Read from cache",
    "system.cache.write" => "Write to cache",
    "system.cache.clear" => "Clear cache",
    "system.storage.read" => "Read from storage",
    "system.storage.write" => "Write to storage",
    "system.storage.clean" => "Clean storage",

    # Service Control
    "system.service.restart" => "Restart services",
    "system.service.reload" => "Reload configurations",
    "system.service.status" => "Check service status",

    # Integration Operations
    "system.webhook.process" => "Process webhooks",
    "system.webhook.retry" => "Retry webhooks",
    "system.email.send" => "Send emails",
    "system.notification.send" => "Send notifications",

    # Internal API Access
    "system.api.internal" => "Access internal APIs",
    "system.api.service" => "Service-to-service communication",

    # AI System Operations
    "system.ai.execute" => "Execute AI operations",
    "system.ai.process" => "Process AI jobs",
    "system.ai.monitor" => "Monitor AI systems",
    "system.ai.collect_metrics" => "Collect AI metrics",
    "system.ai.cleanup" => "Clean up AI resources",
    "system.ai.manage_connections" => "Manage AI provider connections",
    "system.ai.rotate_keys" => "Rotate AI encryption keys",
    "system.ai.backup" => "Backup AI data",
    "system.ai.sync" => "Sync AI provider data",

    # Integration System Operations
    "system.integrations.execute" => "Execute integration instances",
    "system.integrations.health_check" => "Perform integration health checks",
    "system.integrations.sync" => "Sync integration data",
    "system.integrations.rotate_credentials" => "Rotate integration credentials",

    # AI Context System Operations
    "system.ai.context.cleanup" => "Clean up expired AI contexts",
    "system.ai.context.archive" => "Archive old AI contexts",
    "system.ai.context.sync" => "Sync AI context data",
    "system.ai.context.generate_embeddings" => "Generate embeddings for context entries",

    # Git System Operations
    "system.git.process_webhooks" => "Process Git webhook events",
    "system.git.sync_repositories" => "Sync Git repositories",
    "system.git.sync_pipelines" => "Sync CI/CD pipelines",
    "system.git.access_credentials" => "Access Git credentials for operations"
  }.freeze

  # All permissions combined
  ALL_PERMISSIONS = {
    **RESOURCE_PERMISSIONS,
    **ADMIN_PERMISSIONS,
    **SYSTEM_PERMISSIONS
  }.freeze

  # Role Definitions
  ROLES = {
    # Regular user with basic access
    "member" => {
      display_name: "Member",
      description: "Basic account member with standard access",
      role_type: "user",
      permissions: [
        "user.read", "user.edit_self",
        "team.read",
        "billing.read",
        "page.read",
        "analytics.read",
        "report.read",
        "api.read",
        "webhook.read",
        "invoice.read",
        "audit.read",
        "kb.read",
        # Marketplace permissions
        "app.read",
        "listing.read",
        "subscription.read", "subscription.create", "subscription.manage", "subscription.cancel",
        "subscription.read_usage",
        "review.read",
        # Basic AI permissions
        "ai.providers.read", "ai.agents.read", "ai.executions.read",
        "ai.workflows.read", "ai.workflow_executions.read",
        "ai.conversations.read", "ai.conversations.create", "ai.conversations.participate",
        "ai.messages.read", "ai.messages.create", "ai.templates.read", "ai.templates.install",
        # File management permissions
        "files.read", "files.create", "files.download", "files.update", "files.delete",
        "storage.read"
      ]
    },

    # Team manager with extended permissions
    "manager" => {
      display_name: "Manager",
      description: "Team manager with content and team management capabilities",
      role_type: "user",
      permissions: [
        # All member permissions
        "user.read", "user.edit_self",
        "team.read", "team.invite", "team.remove", "team.assign_roles",
        "billing.read", "billing.update",
        "plans.read", "plans.manage",
        "page.read", "page.create", "page.edit", "page.delete", "page.publish",
        "analytics.read", "analytics.export",
        "report.read", "report.generate", "report.export",
        "api.read", "api.write", "api.manage_keys",
        "webhook.read", "webhook.create", "webhook.edit", "webhook.delete",
        "invoice.read", "invoice.download",
        "audit.read", "audit.export", "audit.manage",
        # Knowledge base permissions
        "kb.read", "kb.create", "kb.edit", "kb.publish", "kb.manage",
        # Marketplace permissions
        "app.read", "app.create", "app.edit", "app.delete", "app.publish",
        "app.manage_features", "app.manage_plans", "app.read_analytics",
        "listing.read", "listing.create", "listing.edit", "listing.delete",
        "subscription.read", "subscription.create", "subscription.manage",
        "subscription.cancel", "subscription.upgrade", "subscription.read_usage",
        "review.read", "review.create", "review.edit", "review.delete", "review.moderate",
        # Full AI permissions for managers
        "ai.providers.read", "ai.providers.create", "ai.providers.update", "ai.providers.delete", "ai.providers.test",
        "ai.credentials.read", "ai.credentials.create", "ai.credentials.update",
        "ai.credentials.delete", "ai.credentials.test",
        "ai.agents.read", "ai.agents.create", "ai.agents.update", "ai.agents.delete",
        "ai.agents.execute", "ai.agents.clone",
        "ai.executions.read", "ai.executions.cancel", "ai.executions.retry",
        "ai.workflows.read", "ai.workflows.create", "ai.workflows.update", "ai.workflows.delete",
        "ai.workflows.execute", "ai.workflows.clone", "ai.workflows.import", "ai.workflows.export",
        "ai.workflow_executions.read", "ai.workflow_executions.cancel", "ai.workflow_executions.retry",
        "ai.conversations.read", "ai.conversations.create", "ai.conversations.participate", "ai.conversations.manage",
        "ai.messages.read", "ai.messages.create", "ai.messages.edit", "ai.messages.delete",
        "ai.analytics.read", "ai.analytics.export",
        "ai.templates.read", "ai.templates.install", "ai.templates.create", "ai.templates.publish",
        # MCP permissions
        "mcp.servers.read", "mcp.servers.write",
        "mcp.tools.read", "mcp.tools.execute",
        "mcp.executions.read", "mcp.executions.write",
        # File management permissions
        "files.read", "files.create", "files.update", "files.delete", "files.download",
        "files.share", "files.version", "files.tag",
        "storage.read", "storage.create", "storage.update", "storage.delete", "storage.test",
        # Git provider permissions
        "git.providers.read", "git.providers.create", "git.providers.update", "git.providers.delete",
        "git.credentials.read", "git.credentials.create", "git.credentials.update",
        "git.credentials.delete", "git.credentials.test",
        "git.repositories.read", "git.repositories.delete", "git.repositories.sync",
        "git.repositories.webhooks.manage",
        "git.pipelines.read", "git.pipelines.trigger", "git.pipelines.cancel", "git.pipelines.logs",
        "git.webhooks.read",
        "git.runners.read", "git.runners.manage", "git.runners.token",
        "git.schedules.read", "git.schedules.manage",
        "git.approvals.read", "git.approvals.manage",
        # Integration permissions
        "integrations.read", "integrations.create", "integrations.update", "integrations.delete", "integrations.execute",
        "integrations.credentials.read", "integrations.credentials.create",
        "integrations.credentials.update", "integrations.credentials.delete",
        # AI Context permissions
        "ai.context.read", "ai.context.create", "ai.context.update", "ai.context.delete",
        "ai.context.search", "ai.context.export", "ai.context.import",
        "ai.memory.read", "ai.memory.write", "ai.memory.manage"
      ]
    },

    # Billing administrator
    "billing_admin" => {
      display_name: "Billing Administrator",
      description: "Manages billing, subscriptions, and financial operations",
      role_type: "user",
      permissions: [
        "user.read", "user.edit_self",
        "team.read",
        "billing.read", "billing.update", "billing.cancel",
        "plans.read", "plans.create", "plans.manage",
        "invoice.read", "invoice.download",
        "analytics.read",
        "report.read", "report.generate",
        "admin.billing.read", "admin.billing.override",
        "admin.billing.refund", "admin.billing.credit",
        "audit.read"
      ]
    },

    # App developer with marketplace focus
    "developer" => {
      display_name: "App Developer",
      description: "App developer with marketplace publishing capabilities",
      role_type: "user",
      permissions: [
        "user.read", "user.edit_self",
        "team.read",
        "billing.read", "billing.update",
        "plans.read",
        "page.read",
        "analytics.read", "analytics.export",
        "report.read", "report.generate",
        "api.read", "api.write", "api.manage_keys",
        "webhook.read", "webhook.create", "webhook.edit", "webhook.delete",
        # Knowledge base permissions
        "kb.read", "kb.create", "kb.edit", "kb.publish", "kb.manage",
        "invoice.read", "invoice.download",
        "audit.read",
        # Full marketplace permissions
        "app.read", "app.create", "app.edit", "app.delete", "app.publish",
        "app.manage_features", "app.manage_plans", "app.read_analytics",
        "listing.read", "listing.create", "listing.edit", "listing.delete",
        "subscription.read", "subscription.create", "subscription.manage",
        "subscription.cancel", "subscription.upgrade", "subscription.read_usage",
        "review.read", "review.create", "review.edit", "review.delete", "review.moderate"
      ]
    },

    # Content manager with knowledge base focus
    "content_manager" => {
      display_name: "Content Manager",
      description: "Manages knowledge base content and documentation",
      role_type: "user",
      permissions: [
        "user.read", "user.edit_self",
        "team.read",
        "billing.read",
        "page.read", "page.create", "page.edit", "page.publish",
        "analytics.read",
        "report.read",
        "api.read",
        "audit.read",
        # Full knowledge base permissions
        "kb.read", "kb.create", "kb.edit", "kb.delete", "kb.publish",
        "kb.manage", "kb.moderate"
      ]
    },

    # Account owner with full account access
    "owner" => {
      display_name: "Account Owner",
      description: "Account owner with full account management capabilities",
      role_type: "user",
      permissions: [
        # All resource permissions
        *RESOURCE_PERMISSIONS.keys,
        # Selected admin permissions for account management
        "admin.user.read", "admin.user.create", "admin.user.edit", "admin.user.suspend",
        "users.impersonate",
        "admin.role.read", "admin.role.assign",
        "admin.billing.read", "admin.billing.override",
        "admin.settings.read", "admin.settings.edit",
        "admin.audit.read", "admin.audit.export", "admin.audit.manage",
        "admin.kb.read", "admin.kb.manage", "admin.kb.analytics",
        # Admin permissions for circuit breakers and validation
        "admin.circuit_breakers.read", "admin.circuit_breakers.write",
        "admin.validation_rules.read", "admin.validation_rules.write"
      ]
    },

    # System administrator
    "admin" => {
      display_name: "Administrator",
      description: "System administrator with full administrative access",
      role_type: "admin",
      permissions: [
        # All resource permissions
        *RESOURCE_PERMISSIONS.keys,
        # All admin permissions except super admin operations
        *ADMIN_PERMISSIONS.keys.reject { |p| p.start_with?("admin.maintenance.") }
      ]
    },

    # Super administrator - special system role with programmatic access to all permissions
    "super_admin" => {
      display_name: "Super Administrator",
      description: "Special system role with system.admin permission granting access to ALL permissions. Cannot be edited or deleted.",
      role_type: "admin",
      permissions: [ "system.admin" ], # system.admin permission grants all permissions programmatically
      is_system: true,
      immutable: true # Cannot be edited or deleted
    },

    # System worker role
    "system_worker" => {
      display_name: "System Worker",
      description: "Automated worker with system-level access",
      role_type: "system",
      permissions: [
        *SYSTEM_PERMISSIONS.keys,
        # AI workflow permissions for executing workflows
        "ai.workflows.read", "ai.workflows.update", "ai.workflows.execute",
        "ai.workflow_executions.read", "ai.workflow_executions.update",
        "ai.agents.read", "ai.agents.execute",
        "ai.providers.read", "ai.providers.test",
        "ai.conversations.read", "ai.conversations.create",
        "ai.messages.read", "ai.messages.create",
        # Git system permissions
        "system.git.process_webhooks", "system.git.sync_repositories",
        "system.git.sync_pipelines", "system.git.access_credentials",
        # Integration permissions for worker jobs
        "integrations.read", "integrations.execute",
        "integrations.credentials.read",
        # AI Context permissions for worker jobs
        "ai.context.read", "ai.context.update",
        "ai.memory.read", "ai.memory.write"
      ]
    },

    # Limited worker role for specific tasks
    "task_worker" => {
      display_name: "Task Worker",
      description: "Worker limited to specific task execution",
      role_type: "system",
      permissions: [
        "system.worker.register",
        "system.worker.heartbeat",
        "system.worker.report",
        "system.worker.execute",
        "system.jobs.process",
        "system.health.report",
        "system.api.internal"
      ]
    },

    # AI specialist role for power users
    "ai_specialist" => {
      display_name: "AI Specialist",
      description: "AI power user with full AI system access and template publishing rights",
      role_type: "user",
      permissions: [
        # Basic user permissions
        "user.read", "user.edit_self",
        "team.read",
        "billing.read",
        "analytics.read", "analytics.export",
        "report.read", "report.generate",
        "api.read", "api.write", "api.manage_keys",
        "audit.read",
        # Full AI permissions
        "ai.providers.read", "ai.providers.create", "ai.providers.update", "ai.providers.delete", "ai.providers.test",
        "ai.credentials.read", "ai.credentials.create", "ai.credentials.update",
        "ai.credentials.delete", "ai.credentials.test",
        "ai.agents.read", "ai.agents.create", "ai.agents.update", "ai.agents.delete",
        "ai.agents.execute", "ai.agents.clone",
        "ai.executions.read", "ai.executions.cancel", "ai.executions.retry",
        "ai.workflows.read", "ai.workflows.create", "ai.workflows.update", "ai.workflows.delete",
        "ai.workflows.execute", "ai.workflows.clone", "ai.workflows.import", "ai.workflows.export",
        "ai.workflow_executions.read", "ai.workflow_executions.cancel", "ai.workflow_executions.retry",
        "ai.conversations.read", "ai.conversations.create", "ai.conversations.participate",
        "ai.conversations.manage",
        "ai.messages.read", "ai.messages.create", "ai.messages.edit", "ai.messages.delete",
        "ai.analytics.read", "ai.analytics.export",
        "ai.templates.read", "ai.templates.install", "ai.templates.create", "ai.templates.publish",
        # MCP permissions
        "mcp.servers.read", "mcp.servers.write",
        "mcp.tools.read", "mcp.tools.execute",
        "mcp.executions.read", "mcp.executions.write",
        # File management permissions
        "files.read", "files.create", "files.update", "files.delete", "files.download",
        "files.share", "files.version", "files.tag",
        "storage.read", "storage.create", "storage.update", "storage.delete", "storage.test",
        # Git provider permissions
        "git.providers.read", "git.providers.create", "git.providers.update", "git.providers.delete",
        "git.credentials.read", "git.credentials.create", "git.credentials.update",
        "git.credentials.delete", "git.credentials.test",
        "git.repositories.read", "git.repositories.delete", "git.repositories.sync",
        "git.repositories.webhooks.manage",
        "git.pipelines.read", "git.pipelines.trigger", "git.pipelines.cancel", "git.pipelines.logs",
        "git.webhooks.read",
        # Integration permissions
        "integrations.read", "integrations.create", "integrations.update", "integrations.delete", "integrations.execute",
        "integrations.credentials.read", "integrations.credentials.create",
        "integrations.credentials.update", "integrations.credentials.delete",
        # AI Context permissions
        "ai.context.read", "ai.context.create", "ai.context.update", "ai.context.delete",
        "ai.context.search", "ai.context.export", "ai.context.import",
        "ai.memory.read", "ai.memory.write", "ai.memory.manage"
      ]
    }
  }.freeze

  # Helper methods
  class << self
    def permission_exists?(permission)
      ALL_PERMISSIONS.key?(permission)
    end

    def permission_description(permission)
      ALL_PERMISSIONS[permission]
    end

    def permissions_for_role(role_name)
      ROLES.dig(role_name, :permissions) || []
    end

    def role_exists?(role_name)
      ROLES.key?(role_name)
    end

    def role_info(role_name)
      ROLES[role_name]
    end

    def permissions_by_category
      {
        "Resource Permissions" => RESOURCE_PERMISSIONS,
        "Admin Permissions" => ADMIN_PERMISSIONS,
        "System Permissions" => SYSTEM_PERMISSIONS
      }
    end

    def resource_permissions
      RESOURCE_PERMISSIONS.keys
    end

    def admin_permissions
      ADMIN_PERMISSIONS.keys
    end

    def system_permissions
      SYSTEM_PERMISSIONS.keys
    end

    def user_roles
      ROLES.select { |_, info| info[:role_type] == "user" }.keys
    end

    def admin_roles
      ROLES.select { |_, info| info[:role_type] == "admin" }.keys
    end

    def system_roles
      ROLES.select { |_, info| info[:role_type] == "system" }.keys
    end
  end
end
