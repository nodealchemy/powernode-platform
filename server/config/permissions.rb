# frozen_string_literal: true

require_relative "permissions/catalog"

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

    # Content Management
    "page.create" => "Create pages",
    "page.read" => "View pages",
    "page.update" => "Update pages",
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
    "webhook.update" => "Update webhooks",
    "webhook.delete" => "Delete webhooks",

    # Audit Logs
    "audit.read" => "View audit logs",
    "audit.export" => "Export audit logs",
    "audit.manage" => "Manage audit logs",

    # Knowledge Base
    "kb.read" => "View published knowledge base articles",
    "kb.create" => "Create knowledge base articles",
    "kb.update" => "Update knowledge base articles",
    "kb.delete" => "Delete knowledge base articles",
    "kb.publish" => "Publish knowledge base articles",
    "kb.manage" => "Manage knowledge base categories and settings",
    "kb.moderate" => "Moderate knowledge base comments",

    # AI Orchestration - Providers
    "ai.providers.read" => "View available AI providers",
    "ai.providers.create" => "Create AI providers",
    "ai.providers.update" => "Update AI providers",
    "ai.providers.delete" => "Delete AI providers",
    "ai.providers.test" => "Test AI provider connections",

    # AI Orchestration - Data Sources
    "ai.data_sources.read" => "View AI data sources",
    "ai.data_sources.create" => "Create AI data sources",
    "ai.data_sources.update" => "Update AI data sources",
    "ai.data_sources.delete" => "Delete AI data sources",
    "ai.data_sources.manage" => "Manage AI data sources (create, update, delete)",
    "ai.data_sources.query" => "Query AI data sources",
    "ai.data_sources.stream" => "Subscribe to AI data source endpoints (pull-based monitoring)",

    # AI Orchestration - Growth Content Drafts (D1/D2)
    "ai.content_drafts.read" => "View AI content drafts",
    "ai.content_drafts.manage" => "Manage AI content drafts (create, approve, reject, publish)",

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
    "ai.messages.update" => "Update own AI messages",
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

    # AI Orchestration - FinOps / ROI / Execution Traces
    # (these back the Cost + Developer nav sections; previously referenced by
    # controllers but never registered, which 403'd the features for everyone)
    "ai.finops.view" => "View AI FinOps cost management",
    "ai.roi.read" => "View AI ROI analytics",
    "ai.roi.manage" => "Manage AI ROI configuration",
    "ai_monitoring.read" => "View AI execution traces and monitoring",

    # AI Orchestration - Templates
    "ai.templates.read" => "View AI agent templates",
    "ai.templates.install" => "Install AI agent templates",
    "ai.templates.create" => "Create AI agent templates",
    "ai.templates.publish" => "Publish AI agent templates",

    # AI Orchestration - Prompt Templates
    "ai.prompt_templates.read" => "View AI prompt templates",
    "ai.prompt_templates.write" => "Create, update, and delete AI prompt templates",

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
    "git.pipelines.manage" => "Manage CI/CD pipeline deliveries and rollbacks",

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

    # AI Skills
    "ai.skills.read" => "View AI skills",
    "ai.skills.create" => "Create AI skills",
    "ai.skills.update" => "Update AI skills",
    "ai.skills.delete" => "Delete AI skills",

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
    "ai.memory.manage" => "Manage AI agent memory (clear, archive)",


    # AI Discovery
    "ai.discovery.read" => "View AI discovery scan results",
    "ai.discovery.manage" => "Run AI discovery scans",

    # AI Memory Pools
    "ai.memory_pools.read" => "View AI memory pools",
    "ai.memory_pools.manage" => "Create and manage AI memory pools",

    # AI Code Reviews
    "ai.code_reviews.read" => "View AI code review comments",
    "ai.code_reviews.manage" => "Manage AI code review comments",

    # AI Agent Teams
    "ai.teams.manage" => "Manage AI agent teams",
    "ai.teams.execute" => "Execute AI agent teams",

    # AI Autonomy
    "ai.autonomy.configure" => "Configure AI agent autonomy settings",
    "ai.autonomy.manage" => "Manage AI agent trust scores, budgets, and autonomy write operations",
    "ai.autonomy.approve" => "Approve or reject AI agent autonomy actions",

    # AI Code Factory
    "ai.code_factory.read" => "View Code Factory risk contracts and review states",
    "ai.code_factory.manage" => "Manage Code Factory contracts, run preflight gates, and remediation",

    # AI Missions
    "ai.missions.read" => "View missions and mission details",
    "ai.missions.manage" => "Create, manage, and approve missions",

    # AI Knowledge Graph
    "ai.knowledge_graph.read" => "View knowledge graph nodes and relationships",
    "ai.knowledge_graph.manage" => "Create and manage knowledge graph nodes and edges",

    # AI RAG (retrieval-augmented-generation vector stores: knowledge bases,
    # documents, embeddings, queries, connectors). Distinct from the kb.* article
    # knowledge base — these scopes manage RAG vector infrastructure, not help articles.
    "ai.rag.read" => "View RAG knowledge bases, documents, queries, connectors, and analytics",
    "ai.rag.create" => "Create RAG knowledge bases, documents, and connectors",
    "ai.rag.update" => "Update RAG knowledge bases, embeddings, and sync connectors",
    "ai.rag.delete" => "Delete RAG knowledge bases and documents",

    # DevOps Pipeline Management
    "devops.pipelines.read" => "View DevOps pipelines",
    "devops.pipelines.write" => "Create, update, and delete DevOps pipelines",
    "devops.pipeline_runs.read" => "View DevOps pipeline runs",
    "devops.pipeline_runs.write" => "Manage DevOps pipeline runs (cancel, retry)",
    "devops.providers.read" => "View DevOps providers",
    "devops.providers.write" => "Create, update, and delete DevOps providers",
    "devops.repositories.read" => "View DevOps repositories",
    "devops.repositories.write" => "Manage DevOps repositories",
    "devops.schedules.read" => "View DevOps pipeline schedules",
    "devops.schedules.write" => "Manage DevOps pipeline schedules",
    "devops.prompt_templates.read" => "View DevOps prompt templates",
    "devops.prompt_templates.write" => "Manage DevOps prompt templates",

    # DevOps Integrations
    "devops.integrations.read" => "View DevOps integration templates and instances",
    "devops.integrations.create" => "Create DevOps integration instances",
    "devops.integrations.update" => "Update DevOps integration instances",
    "devops.integrations.delete" => "Delete DevOps integration instances",
    "devops.integrations.execute" => "Execute DevOps integrations",
    "devops.integrations.credentials.read" => "View DevOps integration credentials",
    "devops.integrations.credentials.create" => "Create DevOps integration credentials",
    "devops.integrations.credentials.update" => "Update DevOps integration credentials",
    "devops.integrations.credentials.delete" => "Delete DevOps integration credentials",

    # DevOps AI Configuration
    "devops.ai.manage" => "Manage DevOps AI configurations (models, prompts, settings)",

    # DevOps Container Orchestration
    "devops.containers.read" => "View container executions",
    "devops.containers.execute" => "Execute containers from templates",
    "devops.containers.cancel" => "Cancel running containers",
    "devops.container_templates.read" => "View container templates",
    "devops.container_templates.write" => "Create, update, and delete container templates",
    "devops.container_quotas.read" => "View resource quotas",
    "devops.container_quotas.manage" => "Manage resource quotas",

    # DevOps Docker Engine (hosts / containers / images / networks / volumes)
    "devops.docker.read" => "View Docker hosts, containers, images, networks, and volumes",
    "devops.docker.manage" => "Manage Docker hosts, containers, images, networks, and volumes",

    # DevOps Docker Swarm orchestration (services / stacks / clusters / nodes / configs / networks / volumes)
    "devops.swarm.read" => "View Docker Swarm services, stacks, clusters, nodes, configs, networks, and volumes",
    "devops.swarm.manage" => "Manage Docker Swarm services, stacks, clusters, nodes, configs, networks, and volumes",

    # DevOps Kubernetes (clusters / nodes)
    "devops.kubernetes.read" => "View Kubernetes clusters and nodes",
    "devops.kubernetes.manage" => "Manage Kubernetes clusters and nodes",

    # Chat channels & sessions (external messaging-platform integrations: Slack, Discord, Telegram, WhatsApp, etc.)
    "chat.channels.read" => "View chat channels and their sessions/metrics",
    "chat.channels.manage" => "Connect, configure, and manage chat channels (incl. credential rotation)",
    "chat.sessions.read" => "View chat sessions and their messages",
    "chat.sessions.manage" => "Manage chat sessions (transfer, close, send messages)"
  }.freeze

  # Admin Permissions - Administrative operations
  ADMIN_PERMISSIONS = {
    # General Admin Access
    "admin.access" => "Access admin panel and features",

    # User Administration
    "admin.user.read" => "View all users",
    "admin.user.create" => "Create users",
    "admin.user.update" => "Update any user",
    "admin.user.delete" => "Delete users",
    "admin.user.impersonate" => "Impersonate users",
    "admin.user.suspend" => "Suspend users",

    # Account Administration
    "admin.account.read" => "View all accounts",
    "admin.account.create" => "Create accounts",
    "admin.account.update" => "Update accounts",
    "admin.account.delete" => "Delete accounts",
    "admin.account.suspend" => "Suspend accounts",

    # Role & Permission Management
    "admin.role.read" => "View roles",
    "admin.role.create" => "Create roles",
    "admin.role.update" => "Update roles",
    "admin.role.delete" => "Delete roles",
    "admin.role.assign" => "Assign roles",

    # System Settings
    "admin.settings.read" => "View settings",
    "admin.settings.update" => "Update settings",
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
    "admin.ai.providers.update" => "Update any AI provider",
    "admin.ai.providers.delete" => "Delete AI providers",
    "admin.ai.providers.sync" => "Sync AI provider models",
    "admin.ai.credentials.read" => "View all AI credentials",
    "admin.ai.credentials.manage" => "Manage any AI credentials",
    "admin.ai.credentials.rotate" => "Rotate encryption keys",
    "admin.ai.agents.read" => "View all AI agents",
    "admin.ai.agents.update" => "Update any AI agent",
    "admin.ai.agents.delete" => "Delete any AI agent",
    "admin.ai.executions.read" => "View all AI executions",
    "admin.ai.executions.manage" => "Manage any AI execution",
    "admin.ai.conversations.read" => "View all AI conversations",
    "admin.ai.conversations.moderate" => "Moderate AI conversations",
    "admin.ai.workflows.read" => "View all AI workflows",
    "admin.ai.workflows.update" => "Update any AI workflow",
    "admin.ai.workflows.delete" => "Delete any AI workflow",
    "admin.ai.workflow_executions.read" => "View all workflow executions",
    "admin.ai.workflow_executions.manage" => "Manage any workflow execution",
    "admin.ai.analytics.read" => "View AI system analytics",
    "admin.ai.monitoring.read" => "View AI system monitoring",

    # File Management Administration
    "admin.files.read" => "View all files across accounts",
    "admin.files.manage" => "Manage any file",
    "admin.files.delete" => "Delete any file",
    "admin.files.recover" => "Recover deleted files",
    "admin.files.audit" => "View file access audit logs",
    "admin.storage.read" => "View all storage configurations",
    "admin.storage.create" => "Create system storage configurations",
    "admin.storage.update" => "Update any storage configuration",
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
    "admin.integrations.templates.update" => "Update integration templates",
    "admin.integrations.templates.delete" => "Delete integration templates",
    "admin.integrations.templates.publish" => "Publish/unpublish integration templates",
    "admin.integrations.credentials.read" => "View all integration credentials",
    "admin.integrations.credentials.manage" => "Manage all integration credentials",
    "admin.integrations.executions.read" => "View all integration executions",
    "admin.integrations.executions.manage" => "Manage all integration executions",

    # DevOps Administration
    "admin.devops.pipelines.read" => "View all DevOps pipelines",
    "admin.devops.pipelines.manage" => "Manage all DevOps pipelines",
    "admin.devops.providers.read" => "View all DevOps providers",
    "admin.devops.providers.manage" => "Manage all DevOps providers",
    "admin.devops.repositories.read" => "View all DevOps repositories",
    "admin.devops.repositories.manage" => "Manage all DevOps repositories",
    "admin.devops.integration_templates.create" => "Create DevOps integration templates",
    "admin.devops.integration_templates.update" => "Update DevOps integration templates",
    "admin.devops.integration_templates.delete" => "Delete DevOps integration templates",

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

    # Database Operations
    "system.database.read" => "Direct database read",
    "system.database.write" => "Direct database write",

    # Job Processing
    "system.jobs.process" => "Process background jobs",
    "system.jobs.retry" => "Retry failed jobs",
    "system.jobs.cancel" => "Cancel jobs",
    "system.jobs.schedule" => "Schedule jobs",

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
    "system.git.access_credentials" => "Access Git credentials for operations",

    # Disk-image publication (system extension)
    # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — Chunk 1).
    # `publish_disk_image` is the worker-only permission CI runners hold —
    # the controller authorizes against this and additionally enforces
    # worker.account_id == platform.account_id for cross-tenant safety.
    "system.platforms.publish_disk_image"        => "CI worker can register a disk-image build against a NodePlatform",
    "system.platforms.rollback_disk_image"       => "Operator can re-activate a prior disk-image publication",
    "system.platforms.manage_disk_image_policy"  => "Operator can edit cosign trust regexps + retention count on a NodePlatform",
    "system.disk_image_webhooks.read"            => "List disk-image webhook secrets for the current account",
    "system.disk_image_webhooks.create"          => "Create a new disk-image webhook secret",
    "system.disk_image_webhooks.delete"          => "Revoke a disk-image webhook secret",
    "system.disk_image_webhooks.rotate_secret"   => "Rotate a disk-image webhook's HMAC secret",
    "system.ci_workers.read"                     => "List CI workers for the current account",
    "system.ci_workers.create"                   => "Provision a new CI worker (returns plaintext token once)",
    "system.ci_workers.delete"                   => "Revoke a CI worker",
    "system.ci_workers.rotate_token"             => "Rotate a CI worker's authentication token",
    # Campaign 019f5885 inc3 — ephemeral CI runner leases.
    "system.ci_runner_leases.read"               => "List CI runner leases for the current account",
    "system.ci_runner_leases.create"             => "Lease an ephemeral Gitea Act runner from a builder pool",
    "system.ci_runner_leases.update"             => "Release a CI runner lease (deregister + recycle the instance)",
    # Campaign 019f5885 inc9 — native module-build batch orchestration.
    "system.module_builds.dispatch"              => "Plan + dispatch a native module-build batch (lease builders, create ci.module_build tasks)",
    # Separate from .dispatch on purpose: .dispatch reaches only the
    # system_worker role (leaked-token blast-radius bound), and gating the
    # kill switch on it would leave a human operator unable to stop a batch
    # they can see running. Granted to admin/manager by the system extension.
    "system.module_builds.cancel"                => "Stop a running native module-build batch (cancel member tasks, release builder leases, halt further dispatch)",
    # Campaign 019f6084 inc2 — agent-pollable build-completion barrier
    # (ModuleBuildBatch read API). Adjacent to .dispatch because that's the
    # existing precedent for this permission name; the admin/manager grant
    # is registered from the extension side (see PowernodeSystem::Engine) —
    # .dispatch itself gets no such registration and is worker/webhook-only
    # by design (SYSTEM_PERMISSIONS entries default to system_worker only;
    # nothing here should be read as implying the admin/manager ROLES also
    # get an explicit .dispatch grant). That's a statement about role grants,
    # not effective access: User#has_permission? short-circuits on
    # system.admin, so the super_admin role still passes a .dispatch check
    # without ever being registered here. Plain admin/manager aren't
    # affected by that short-circuit — neither role's permissions array
    # includes system.admin.
    "system.module_builds.read"                  => "View module-build batches (status, per-module build/lease/artifact state)"
  }.freeze

  # All permissions combined
  # ---------------------------------------------------------------------------
  # Programmatic catalog additions (audit-reconciled permission gaps), declared
  # via the Permissions.catalog DSL. Merged into CORE_PERMISSIONS below and into
  # every role by permissions_for_role. Grouped by tier/namespace.
  # ---------------------------------------------------------------------------
  define do
    # File ownership overrides (irregular non-CRUD names → escape hatch)
    permission "files.view_all",     "View any file regardless of ownership",     grant: { admin: true }
    permission "files.download_all", "Download any file regardless of ownership", grant: { admin: true }
    permission "files.edit_all",     "Edit any file regardless of ownership",     grant: { admin: true }
    permission "files.delete_all",   "Delete any file regardless of ownership",   grant: { admin: true }
    # Account-scoped user management (distinct from cross-account admin.user.*)
    resource :users, actions: :crud,
             grant: { manager: %i[read create update], owner: :all, admin: :all }
  end

  # AI domain (core). owner/admin receive all resource-tier perms (mirroring the
  # historical *RESOURCE_PERMISSIONS splat invariant); manager/ai_specialist/
  # member/system_worker per enforcement. Cross-account super-scopes are admin-only.
  define(namespace: "ai") do
    permission "ai.manage", "Coarse manage-all-AI gate",
               grant: { owner: true, admin: true, manager: true, ai_specialist: true }
    resource :agents, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :conversations, actions: %i[update delete],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all,
                      member: %i[update], system_worker: %i[update] }
    resource :messages, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :workflows, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :knowledge, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :image, actions: %i[generate], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :credentials, actions: %i[decrypt], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :analytics, actions: %i[create manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    permission "ai.analytics.global", "Cross-account AI analytics scope (admin-only)", grant: { admin: true }
    resource :monitoring, actions: %i[read manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :routing, actions: %i[read manage optimize], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :aiops, actions: %i[read write], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :devops, actions: %i[read manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :sandboxes, actions: %i[read create update delete manage test benchmark],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :federation, actions: %i[read create update delete verify sync],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :community_agents, actions: %i[read create update delete manage rate report],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all, member: %i[read rate report] }
    resource :kill_switch, actions: %i[manage], grant: { owner: :all, admin: :all }
    resource :goals, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :campaigns, actions: %i[read manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :intervention_policies, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    resource :proposals, actions: %i[view review],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all, member: %i[view] }
    resource :escalations, actions: %i[view resolve],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all, member: %i[view] }
    resource :feedback, actions: %i[submit view],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all, member: %i[submit view] }
    resource :approval_chains, actions: %i[manage], grant: { owner: :all, admin: :all }
    resource :security, actions: %i[manage], grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all }
    # FE-enforced AI surfaces lacking a backend gate (audit/governance/teams views).
    resource :audits, actions: %i[view manage], grant: { owner: :all, admin: :all, manager: %i[view], ai_specialist: :all }
    resource :governance, actions: %i[read manage],
             grant: { owner: :all, admin: :all, manager: :all, ai_specialist: :all, member: %i[read] }
    resource :teams, actions: %i[read], grant: { owner: :all, admin: :all, manager: :all, member: :all, ai_specialist: :all }
  end

  # Core platform gaps (audit-reconciled). Resource-tier: owner/admin = all
  # (splat invariant) + manager subset; cross-account super-scopes admin-only.
  define do
    resource :accounts, actions: %i[read manage], grant: { owner: :all, admin: :all }
    resource :"oauth.applications", actions: :crud, grant: { manager: %i[read], owner: :all, admin: :all }
    resource :team, actions: %i[manage], grant: { manager: :all, owner: :all, admin: :all }
    resource :settings, actions: %i[manage], grant: { owner: :all, admin: :all }
    # Inbound webhook EVENT management — distinct from the outbound webhook.* config set
    resource :webhooks, actions: %i[manage], grant: { manager: :all, owner: :all, admin: :all }
    resource :"git.account_webhooks", actions: %i[manage], grant: { manager: :all, owner: :all, admin: :all }
    permission "analytics.global", "Cross-account analytics scope (admin-only)", grant: { admin: true }
  end

  define(tier: :admin) do
    resource :user, actions: %i[manage], grant: { admin: :all }   # admin.user.manage (suspend/reset/unlock)
    resource :oauth, actions: %i[manage], grant: { admin: :all }  # admin.oauth.manage (cross-account OAuth admin)
    # Worker management (operator action → admin tier, core; renamed from system.workers.*)
    resource :workers, actions: %i[read create update delete], grant: { admin: :all }
  end

  # Core permission set (this app + its DSL catalog additions). The full runtime
  # set INCLUDING enabled extensions is Permissions.all_permissions (a dynamic
  # union computed at call time — see the Lookups section). Nothing here, or in
  # any consumer, names an extension.
  CORE_PERMISSIONS = {
    **RESOURCE_PERMISSIONS,
    **ADMIN_PERMISSIONS,
    **SYSTEM_PERMISSIONS,
    **@catalog_permissions
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
        "page.read",
        "analytics.read",
        "report.read",
        "api.read",
        "webhook.read",
        "audit.read",
        "kb.read",
        # Basic AI permissions
        "ai.providers.read", "ai.data_sources.read", "ai.data_sources.query", "ai.data_sources.stream", "ai.agents.read", "ai.executions.read",
        "ai.content_drafts.read",
        "ai.workflows.read", "ai.workflow_executions.read",
        "ai.conversations.read", "ai.conversations.create", "ai.conversations.participate",
        "ai.messages.read", "ai.messages.create", "ai.templates.read", "ai.templates.install",
        "ai.prompt_templates.read",
        # AI Skills permissions
        "ai.skills.read",
        # AI Teams (read-only)
        "ai.teams.manage",
        # AI Discovery, Memory Pools, Code Reviews (read-only)
        "ai.discovery.read", "ai.memory_pools.read", "ai.code_reviews.read",
        # AI Missions (read-only)
        "ai.missions.read",
        # AI Knowledge Graph (read-only)
        "ai.knowledge_graph.read",
        # File management permissions
        "files.read", "files.create", "files.download", "files.update", "files.delete",
        "storage.read",
        # Chat channels & sessions (read-only)
        "chat.channels.read", "chat.sessions.read",
        # AI RAG (read-only) — distinct from kb.* article knowledge base
        "ai.rag.read"
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
        "page.read", "page.create", "page.update", "page.delete", "page.publish",
        "analytics.read", "analytics.export",
        "report.read", "report.generate", "report.export",
        "api.read", "api.write", "api.manage_keys",
        "webhook.read", "webhook.create", "webhook.update", "webhook.delete",
        "audit.read", "audit.export", "audit.manage",
        # Knowledge base permissions
        "kb.read", "kb.create", "kb.update", "kb.publish", "kb.manage",
        # Full AI permissions for managers
        "ai.providers.read", "ai.providers.create", "ai.providers.update", "ai.providers.delete", "ai.providers.test",
        "ai.credentials.read", "ai.credentials.create", "ai.credentials.update",
        "ai.credentials.delete", "ai.credentials.test",
        "ai.data_sources.read", "ai.data_sources.create", "ai.data_sources.update", "ai.data_sources.delete",
        "ai.data_sources.manage", "ai.data_sources.query", "ai.data_sources.stream",
        "ai.content_drafts.read", "ai.content_drafts.manage",
        "ai.agents.read", "ai.agents.create", "ai.agents.update", "ai.agents.delete",
        "ai.agents.execute", "ai.agents.clone",
        "ai.executions.read", "ai.executions.cancel", "ai.executions.retry",
        "ai.workflows.read", "ai.workflows.create", "ai.workflows.update", "ai.workflows.delete",
        "ai.workflows.execute", "ai.workflows.clone", "ai.workflows.import", "ai.workflows.export",
        "ai.workflow_executions.read", "ai.workflow_executions.cancel", "ai.workflow_executions.retry",
        "ai.conversations.read", "ai.conversations.create", "ai.conversations.participate", "ai.conversations.manage",
        "ai.messages.read", "ai.messages.create", "ai.messages.update", "ai.messages.delete",
        "ai.analytics.read", "ai.analytics.export",
        "ai.finops.view", "ai.roi.read", "ai.roi.manage", "ai_monitoring.read",
        "ai.templates.read", "ai.templates.install", "ai.templates.create", "ai.templates.publish",
        "ai.prompt_templates.read", "ai.prompt_templates.write",
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
        # DevOps permissions
        "devops.pipelines.read", "devops.pipelines.write",
        "devops.pipeline_runs.read", "devops.pipeline_runs.write",
        "devops.providers.read", "devops.providers.write",
        "devops.repositories.read", "devops.repositories.write",
        "devops.schedules.read", "devops.schedules.write",
        "devops.prompt_templates.read", "devops.prompt_templates.write",
        "devops.integrations.read", "devops.integrations.create", "devops.integrations.update",
        "devops.integrations.delete", "devops.integrations.execute",
        "devops.integrations.credentials.read", "devops.integrations.credentials.create",
        "devops.integrations.credentials.update", "devops.integrations.credentials.delete",
        "devops.ai.manage",
        # DevOps Container permissions
        "devops.containers.read", "devops.containers.execute", "devops.containers.cancel",
        "devops.container_templates.read", "devops.container_templates.write",
        "devops.container_quotas.read", "devops.container_quotas.manage",
        "devops.docker.read", "devops.docker.manage",
        "devops.swarm.read", "devops.swarm.manage",
        "devops.kubernetes.read", "devops.kubernetes.manage",
        # AI Skills permissions
        "ai.skills.read", "ai.skills.create", "ai.skills.update", "ai.skills.delete",
        # AI Context permissions
        "ai.context.read", "ai.context.create", "ai.context.update", "ai.context.delete",
        "ai.context.search", "ai.context.export", "ai.context.import",
        "ai.memory.read", "ai.memory.write", "ai.memory.manage",
        # AI Teams
        "ai.teams.manage", "ai.teams.execute",
        # AI Discovery, Memory Pools, Code Reviews, Autonomy
        "ai.discovery.read", "ai.discovery.manage",
        "ai.memory_pools.read", "ai.memory_pools.manage",
        "ai.code_reviews.read", "ai.code_reviews.manage",
        "ai.autonomy.configure", "ai.autonomy.manage", "ai.autonomy.approve",
        # Chat channels & sessions
        "chat.channels.read", "chat.channels.manage",
        "chat.sessions.read", "chat.sessions.manage",
        # AI RAG (vector stores) — distinct from kb.* article knowledge base
        "ai.rag.read", "ai.rag.create", "ai.rag.update", "ai.rag.delete",
        # AI Missions
        "ai.missions.read", "ai.missions.manage",
        # AI Knowledge Graph
        "ai.knowledge_graph.read", "ai.knowledge_graph.manage"
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
        "page.read",
        "analytics.read", "analytics.export",
        "report.read", "report.generate",
        "api.read", "api.write", "api.manage_keys",
        "webhook.read", "webhook.create", "webhook.update", "webhook.delete",
        # Knowledge base permissions
        "kb.read", "kb.create", "kb.update", "kb.publish", "kb.manage",
        "audit.read"
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
        "page.read", "page.create", "page.update", "page.publish",
        "analytics.read",
        "report.read",
        "api.read",
        "audit.read",
        # Full knowledge base permissions
        "kb.read", "kb.create", "kb.update", "kb.delete", "kb.publish",
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
        "admin.user.read", "admin.user.create", "admin.user.update", "admin.user.suspend",
        "users.impersonate",
        "admin.role.read", "admin.role.assign",
        "admin.settings.read", "admin.settings.update",
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
        "system.api.internal"
      ]
    },

    # CI worker role — narrowly scoped for Gitea/GitHub Actions runners
    # that publish disk images. Operators provision one of these per
    # CI pipeline via the /app/system/ci-workers UI; the returned token
    # is stored as a secret in the operator's CI configuration.
    #
    # Scope is deliberately minimal — `system.platforms.publish_disk_image`
    # only. A leaked CI token can register disk images but cannot read
    # other resources, escalate to other workers, or touch billing/AI.
    #
    # role_type: "user" so it's assignable to per-account workers
    # (the platform's only one-system-worker constraint applies to
    # role_type=system roles). The name is allow-listed in
    # Worker.assignable_roles_for_account.
    # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — Chunk 1).
    "ci_worker" => {
      display_name: "CI Worker",
      description: "External CI runner authorized only to register disk-image builds against this account's NodePlatforms",
      role_type: "user",
      permissions: [
        "system.platforms.publish_disk_image",
        # Worker auth basics — needed for token validation + activity tracking.
        "system.worker.heartbeat",
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
        "analytics.read", "analytics.export",
        "report.read", "report.generate",
        "api.read", "api.write", "api.manage_keys",
        "audit.read",
        # Full AI permissions
        "ai.providers.read", "ai.providers.create", "ai.providers.update", "ai.providers.delete", "ai.providers.test",
        "ai.credentials.read", "ai.credentials.create", "ai.credentials.update",
        "ai.credentials.delete", "ai.credentials.test",
        "ai.data_sources.read", "ai.data_sources.create", "ai.data_sources.update", "ai.data_sources.delete",
        "ai.data_sources.manage", "ai.data_sources.query", "ai.data_sources.stream",
        "ai.content_drafts.read", "ai.content_drafts.manage",
        "ai.agents.read", "ai.agents.create", "ai.agents.update", "ai.agents.delete",
        "ai.agents.execute", "ai.agents.clone",
        "ai.executions.read", "ai.executions.cancel", "ai.executions.retry",
        "ai.workflows.read", "ai.workflows.create", "ai.workflows.update", "ai.workflows.delete",
        "ai.workflows.execute", "ai.workflows.clone", "ai.workflows.import", "ai.workflows.export",
        "ai.workflow_executions.read", "ai.workflow_executions.cancel", "ai.workflow_executions.retry",
        "ai.conversations.read", "ai.conversations.create", "ai.conversations.participate",
        "ai.conversations.manage",
        "ai.messages.read", "ai.messages.create", "ai.messages.update", "ai.messages.delete",
        "ai.analytics.read", "ai.analytics.export",
        "ai.finops.view", "ai.roi.read", "ai.roi.manage", "ai_monitoring.read",
        "ai.templates.read", "ai.templates.install", "ai.templates.create", "ai.templates.publish",
        "ai.prompt_templates.read", "ai.prompt_templates.write",
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
        # DevOps permissions
        "devops.pipelines.read", "devops.pipelines.write",
        "devops.pipeline_runs.read", "devops.pipeline_runs.write",
        "devops.providers.read", "devops.providers.write",
        "devops.repositories.read", "devops.repositories.write",
        "devops.schedules.read", "devops.schedules.write",
        "devops.prompt_templates.read", "devops.prompt_templates.write",
        "devops.integrations.read", "devops.integrations.create", "devops.integrations.update",
        "devops.integrations.delete", "devops.integrations.execute",
        "devops.integrations.credentials.read", "devops.integrations.credentials.create",
        "devops.integrations.credentials.update", "devops.integrations.credentials.delete",
        "devops.ai.manage",
        # DevOps Container permissions
        "devops.containers.read", "devops.containers.execute", "devops.containers.cancel",
        "devops.container_templates.read", "devops.container_templates.write",
        "devops.container_quotas.read", "devops.container_quotas.manage",
        "devops.docker.read", "devops.docker.manage",
        "devops.swarm.read", "devops.swarm.manage",
        "devops.kubernetes.read", "devops.kubernetes.manage",
        # AI Skills permissions
        "ai.skills.read", "ai.skills.create", "ai.skills.update", "ai.skills.delete",
        # AI Context permissions
        "ai.context.read", "ai.context.create", "ai.context.update", "ai.context.delete",
        "ai.context.search", "ai.context.export", "ai.context.import",
        "ai.memory.read", "ai.memory.write", "ai.memory.manage",
        # AI Teams
        "ai.teams.manage", "ai.teams.execute",
        # AI Discovery, Memory Pools, Code Reviews, Autonomy
        "ai.discovery.read", "ai.discovery.manage",
        "ai.memory_pools.read", "ai.memory_pools.manage",
        "ai.code_reviews.read", "ai.code_reviews.manage",
        "ai.autonomy.configure", "ai.autonomy.manage", "ai.autonomy.approve",
        # Chat channels & sessions
        "chat.channels.read", "chat.channels.manage",
        "chat.sessions.read", "chat.sessions.manage",
        # AI RAG (vector stores) — distinct from kb.* article knowledge base
        "ai.rag.read", "ai.rag.create", "ai.rag.update", "ai.rag.delete",
        # AI Knowledge Graph
        "ai.knowledge_graph.read", "ai.knowledge_graph.manage"
      ]
    }
  }.freeze

  # Extension registry — mutable hash that lets extensions register
  # permissions + role grants without modifying this file. Populated by
  # extension engine initializers (e.g. PowernodeSystem::Engine).
  # Consumed by Role.sync_from_config! so db:seed preserves grants that
  # would otherwise be wiped by sync_permissions!'s destructive replace.
  #
  # Shape:
  #   @extension_permissions = { "perm.name" => "description", ... }
  #   @extension_role_permissions = { "role_name" => Set["perm.a", "perm.b"], ... }
  @extension_permissions       = {}
  @extension_role_permissions  = Hash.new { |h, k| h[k] = [] }

  # Helper methods
  class << self
    # === Extension registration API ===
    #
    # Call from an extension's engine.rb initializer (after :load_config_initializers)
    # so the registrations are in place before Role.sync_from_config! runs during
    # db:seed. Idempotent — re-registering the same name+description is a no-op.
    #
    # Example (extensions/system/server/lib/powernode_system/engine.rb):
    #   ::Permissions.register_permissions(
    #     "system.packages.embed"   => "Worker can write package embeddings",
    #     "system.packages.reembed" => "Operator can manually trigger re-embedding"
    #   )
    #   ::Permissions.register_role_permissions("system_worker", %w[system.packages.embed])
    def register_permissions(definitions)
      definitions.each do |name, description|
        @extension_permissions[name.to_s] = description.to_s
      end
    end

    def register_role_permissions(role_name, permission_names)
      list = @extension_role_permissions[role_name.to_s]
      Array(permission_names).each do |name|
        list << name.to_s unless list.include?(name.to_s)
      end
    end

    def extension_permissions
      @extension_permissions
    end

    def extension_role_permissions
      @extension_role_permissions
    end

    # === Lookups ===
    # The full runtime permission set: core + every registered extension's
    # permissions. Extensions register via the seam at engine-init; a DISABLED
    # extension never runs its initializer, so it's naturally excluded. The union
    # is computed dynamically and names no extension — it is simply whatever is
    # loaded. Consumers (sync, role enumeration, lookups, UI) use this, never the
    # core-only CORE_PERMISSIONS constant.
    def all_permissions
      CORE_PERMISSIONS.merge(@extension_permissions)
    end

    def permission_exists?(permission)
      all_permissions.key?(permission)
    end

    def permission_description(permission)
      all_permissions[permission]
    end

    # The full runtime role set: core (ROLES) + every enabled extension's
    # registered roles (@extension_roles, populated via register_roles at
    # engine-init). A DISABLED extension never runs its initializer, so it's
    # naturally excluded — the union is computed dynamically and names no
    # extension, mirroring all_permissions. String keys throughout. Consumers
    # (role sync, role enumeration, lookups) use this, never the core-only ROLES.
    def all_roles
      ROLES.merge(@extension_roles.transform_keys(&:to_s))
    end

    # Returns the effective permission set for a role, merging the static
    # config with extension-registered additions. Used by Role.sync_from_config!
    # so extension grants survive db:seed.
    def permissions_for_role(role_name)
      base = all_roles.dig(role_name.to_s, :permissions) || []
      extras = @extension_role_permissions[role_name.to_s] || []
      catalog = @catalog_grants[role_name.to_s] || []
      (base + extras + catalog).uniq
    end

    def role_exists?(role_name)
      all_roles.key?(role_name.to_s)
    end

    def role_info(role_name)
      all_roles[role_name.to_s]
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
      all_roles.select { |_, info| info[:role_type] == "user" }.keys
    end

    def admin_roles
      all_roles.select { |_, info| info[:role_type] == "admin" }.keys
    end

    def system_roles
      all_roles.select { |_, info| info[:role_type] == "system" }.keys
    end
  end
end
