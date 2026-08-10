# frozen_string_literal: true

puts "  [Skills] Starting AI Skills seed..."
Rails.logger.info "[Seeds] Creating AI Skills system data..."

# GLOBAL baseline content: Ai::Skill rows are seeded global (account_id nil,
# upserted by source_key = slug) UNCONDITIONALLY below. The MCP servers and
# their HABTM links are account-scoped INSTANCE data, so they are demo-gated
# (baseline-only mode has zero accounts).
return unless Powernode::Seeds.baseline?

account = Account.first
seed_instances = Powernode::Seeds.demo? && account.present?

# Skill → MCP server lookup, populated only when seeding instances (demo).
mcp_servers = {}
powernode_mcp = nil
hosted_server_count = 0

# ============================================================================
# MCP Servers + hosted links (account-scoped INSTANCE data — demo only)
# ============================================================================
if seed_instances
# Map of MCP server name → { auth_type, command (npx/uvx package), container_template_slug }
MCP_SERVER_DEFS = {
  "Slack" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-slack", tpl: "mcp-slack" },
  "Notion" => { auth: "api_key", cmd: "npx -y @notionhq/mcp-server", tpl: "mcp-notion" },
  "Asana" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-asana", tpl: "mcp-asana" },
  "Linear" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-linear", tpl: "mcp-linear" },
  "Atlassian" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-atlassian", tpl: "mcp-atlassian" },
  "MS365" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-microsoft365", tpl: "mcp-ms365" },
  "Monday" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-monday", tpl: nil },
  "ClickUp" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-clickup", tpl: nil },
  "HubSpot" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-hubspot", tpl: "mcp-hubspot" },
  "Close" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-close", tpl: nil },
  "Clay" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-clay", tpl: nil },
  "ZoomInfo" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-zoominfo", tpl: nil },
  "Fireflies" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-fireflies", tpl: nil },
  "Intercom" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-intercom", tpl: "mcp-intercom" },
  "Guru" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-guru", tpl: nil },
  "Jira" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-atlassian", tpl: "mcp-atlassian" },
  "Figma" => { auth: "api_key", cmd: "npx -y figma-developer/figma-mcp", tpl: "mcp-figma" },
  "Amplitude" => { auth: "api_key", cmd: "npx -y amplitude/mcp-server", tpl: "mcp-amplitude" },
  "Pendo" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-pendo", tpl: nil },
  "Canva" => { auth: "api_key", cmd: "npx -y canva/mcp-server-canva", tpl: "mcp-canva" },
  "Ahrefs" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-ahrefs", tpl: nil },
  "SimilarWeb" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-similarweb", tpl: nil },
  "Box" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-box", tpl: "mcp-box" },
  "Egnyte" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-egnyte", tpl: nil },
  "Snowflake" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-snowflake", tpl: "mcp-snowflake" },
  "Databricks" => { auth: "api_key", cmd: "uvx databricks-mcp-server", tpl: "mcp-databricks" },
  "BigQuery" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-bigquery", tpl: "mcp-bigquery" },
  "Hex" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-hex", tpl: nil },
  "PubMed" => { auth: "none", cmd: "npx -y @anthropic/mcp-server-pubmed", tpl: nil },
  "BioRender" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-biorender", tpl: nil },
  "bioRxiv" => { auth: "none", cmd: "npx -y @anthropic/mcp-server-biorxiv", tpl: nil },
  "ChEMBL" => { auth: "none", cmd: "npx -y @anthropic/mcp-server-chembl", tpl: nil },
  "Benchling" => { auth: "api_key", cmd: "npx -y @anthropic/mcp-server-benchling", tpl: nil }
}.freeze

# ── Powernode Platform MCP (built-in) ────────────────────────────────────────
# The platform's own Streamable HTTP MCP endpoint — provides the platform.*
# tools (agents, teams, knowledge, memory, skills, workflows, autonomy, etc.).
# This is always "connected" because it's served by the Rails app itself.
powernode_mcp = McpServer.find_or_initialize_by(account: account, name: "Powernode MCP")
powernode_mcp.assign_attributes(
  connection_type: "http",
  status: "connected",
  auth_type: "none",
  command: "/mcp",
  description: "Built-in Powernode platform MCP endpoint (Streamable HTTP)",
  args: [],
  env: { "MCP_URL" => "/mcp" },
  # Merge (not replace) so the tool_count key the McpPlatformToolRegistrar writes
  # right after (sync_to_database!) survives a re-seed — replacing would drop it,
  # the registrar would re-add it, and the capabilities change would churn an audit.
  capabilities: (powernode_mcp.capabilities || {}).merge(
    "tools" => true,
    "resources" => false,
    "prompts" => false
  )
)
powernode_mcp.save!

# Sync platform tools to database so the MCP browser page shows them
tool_count = Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account)
puts "  Synced #{tool_count} platform tools to Powernode MCP server"

# Build MCP server lookup and hosted server links
mcp_servers["powernode mcp"] = powernode_mcp
template_cache = {}

# Suppress after_create callback that enqueues worker jobs (avoids HTTP timeout per server)
McpServer.skip_callback(:create, :after, :initialize_connection, raise: false)

MCP_SERVER_DEFS.each do |name, defn|
  server = McpServer.find_or_initialize_by(account: account, name: name)
  server.assign_attributes(
    connection_type: "stdio",
    status: "disconnected",
    auth_type: defn[:auth],
    command: defn[:cmd],
    args: [],
    env: {},
    capabilities: {}
  )
  server.save!
  mcp_servers[name.downcase] = server

  # Link to Mcp::HostedServer + ContainerTemplate if template exists (business only)
  next unless defn[:tpl]
  next unless defined?(Mcp::HostedServer)

  template = template_cache[defn[:tpl]] ||= Devops::ContainerTemplate.find_by(slug: defn[:tpl])
  next unless template

  hosted = Mcp::HostedServer.find_or_initialize_by(account: account, mcp_server: server)
  hosted.assign_attributes(
    name: "#{name} (Managed)",
    description: "Managed containerized #{name} MCP server",
    status: "pending",
    server_type: "mcp",
    visibility: "private",
    source_type: "registry",
    runtime: defn[:cmd].start_with?("uvx") ? "python" : "node",
    entry_point: defn[:cmd],
    container_template: template,
    memory_mb: template.memory_mb,
    cpu_millicores: template.cpu_millicores,
    timeout_seconds: 30
  )
  hosted.save!
  hosted_server_count += 1
end

puts "  [Skills] MCP servers done. Creating skills..."

# Restore callback
McpServer.set_callback(:create, :after, :initialize_connection) rescue nil
end # if seed_instances (MCP servers + hosted links)

# Suppress conflict check callback during seed — daily maintenance handles conflict scanning
Ai::Skill.skip_callback(:commit, :after, :enqueue_conflict_check, raise: false)

# ============================================================================
# Skill definitions (unchanged from previous, but using HABTM)
# ============================================================================
skills_data = [
  {
    name: "Productivity Assistant",
    slug: "productivity",
    category: "productivity",
    description: "Manages tasks, meetings, and work coordination across project management and communication tools.",
    system_prompt: <<~PROMPT,
      Productivity specialist coordinating work across PM and comms tools.

      Do:
      - Create/update tasks in PM tools
      - Summarize meeting notes and extract action items
      - Coordinate across team channels; track deadlines and blockers
      - Generate status reports

      Confirm destructive actions first. Output structured, with clear action items.
    PROMPT
    commands: [
      { "name" => "start", "description" => "Start a new task or project", "argument_hint" => "<task description>",
        "workflow_steps" => ["Parse task description", "Check for duplicates", "Create in project tool", "Notify team channel"] },
      { "name" => "update", "description" => "Update task status or details", "argument_hint" => "<task ID> <update>",
        "workflow_steps" => ["Find task", "Apply updates", "Notify stakeholders", "Update timeline"] }
    ],
    connectors: %w[slack notion asana linear atlassian ms365 monday clickup],
    tags: ["tasks", "meetings", "coordination"]
  },
  {
    name: "Sales Intelligence",
    slug: "sales",
    category: "sales",
    description: "Research prospects, prepare for calls, manage pipeline, and draft personalized outreach.",
    system_prompt: <<~PROMPT,
      Sales intelligence specialist for prospect research and pipeline.

      Do:
      - Research prospects/companies before calls
      - Analyze pipeline health; forecast
      - Draft personalized outreach
      - Build competitive battlecards
      - Summarize call recordings; extract action items

      Source from CRM and enrichment tools. Cite sources in research.
    PROMPT
    commands: [
      { "name" => "call-prep", "description" => "Prepare briefing for an upcoming sales call", "argument_hint" => "<company or contact>",
        "workflow_steps" => ["Lookup company info", "Check CRM history", "Find recent news", "Generate briefing doc"] },
      { "name" => "pipeline-review", "description" => "Analyze current pipeline health", "argument_hint" => "[segment]",
        "workflow_steps" => ["Pull pipeline data", "Calculate metrics", "Identify at-risk deals", "Generate report"] },
      { "name" => "prospect-research", "description" => "Deep research on a prospect or company", "argument_hint" => "<company name>",
        "workflow_steps" => ["Search enrichment tools", "Check news", "Analyze financials", "Build profile"] },
      { "name" => "write-outreach", "description" => "Draft personalized outreach message", "argument_hint" => "<contact> <context>",
        "workflow_steps" => ["Research recipient", "Identify pain points", "Draft message", "Review tone"] },
      { "name" => "build-battlecard", "description" => "Create competitive battlecard", "argument_hint" => "<competitor>",
        "workflow_steps" => ["Research competitor", "Compare features", "Identify differentiators", "Format battlecard"] }
    ],
    connectors: %w[slack hubspot close clay zoominfo notion fireflies],
    tags: ["crm", "prospecting", "outreach", "pipeline"]
  },
  {
    name: "Customer Support",
    slug: "customer-support",
    category: "customer_support",
    description: "Triage tickets, draft responses, manage escalations, and maintain knowledge base articles.",
    system_prompt: <<~PROMPT,
      Customer support specialist for tickets, responses, and KB.

      Do:
      - Triage tickets by priority and category
      - Draft accurate responses; package escalations with full context
      - Write/update KB articles
      - Surface trends in support requests

      Tone: professional and empathetic. Verify technical details before responding.
    PROMPT
    commands: [
      { "name" => "triage-ticket", "description" => "Analyze and categorize a support ticket", "argument_hint" => "<ticket ID or description>",
        "workflow_steps" => ["Parse ticket content", "Classify priority", "Check KB for solutions", "Route to team"] },
      { "name" => "draft-response", "description" => "Draft a response to a support ticket", "argument_hint" => "<ticket ID>",
        "workflow_steps" => ["Review ticket history", "Search KB", "Draft response", "Add relevant links"] },
      { "name" => "package-escalation", "description" => "Prepare an escalation package", "argument_hint" => "<ticket ID>",
        "workflow_steps" => ["Gather full history", "Summarize issue", "Document reproduction steps", "Create escalation"] },
      { "name" => "write-kb-article", "description" => "Write a knowledge base article from a resolved ticket", "argument_hint" => "<ticket ID>",
        "workflow_steps" => ["Extract solution steps", "Generalize for KB", "Add screenshots/examples", "Publish draft"] }
    ],
    connectors: %w[slack intercom hubspot guru jira notion],
    tags: ["tickets", "escalation", "knowledge-base"]
  },
  {
    name: "Product Management",
    slug: "product-management",
    category: "product_management",
    description: "Write specs, plan roadmaps, synthesize user research, and create competitive briefs.",
    system_prompt: <<~PROMPT,
      Product management specialist for specs, roadmaps, and research.

      Do:
      - Write specs/PRDs with acceptance criteria
      - Plan and prioritize roadmap items
      - Synthesize user research and feedback
      - Create competitive briefs; track requests and usage metrics

      Anchor on user outcomes and business impact. Back recommendations with data.
    PROMPT
    commands: [
      { "name" => "write-spec", "description" => "Write a product specification", "argument_hint" => "<feature name>",
        "workflow_steps" => ["Gather requirements", "Research similar features", "Draft spec", "Add acceptance criteria"] },
      { "name" => "plan-roadmap", "description" => "Plan or update product roadmap", "argument_hint" => "[quarter]",
        "workflow_steps" => ["Review backlog", "Assess priorities", "Check dependencies", "Generate roadmap"] },
      { "name" => "synthesize-research", "description" => "Synthesize user research findings", "argument_hint" => "<research topic>",
        "workflow_steps" => ["Collect feedback sources", "Identify patterns", "Extract insights", "Create summary"] },
      { "name" => "competitive-brief", "description" => "Create competitive analysis brief", "argument_hint" => "<competitor or area>",
        "workflow_steps" => ["Research competitors", "Compare capabilities", "Identify gaps", "Draft brief"] }
    ],
    connectors: %w[slack linear figma amplitude pendo intercom],
    tags: ["specs", "roadmap", "research", "competitive"]
  },
  {
    name: "Marketing Suite",
    slug: "marketing",
    category: "marketing",
    description: "Draft content, plan campaigns, review brand consistency, and analyze performance.",
    system_prompt: <<~PROMPT,
      Marketing specialist for content, campaigns, and performance.

      Do:
      - Draft blog/social/copy, optimized per channel
      - Plan multi-channel campaigns with KPIs
      - Review content for brand consistency
      - Build competitive briefs; report performance with insights

      Hold brand voice and guidelines. Support claims with data.
    PROMPT
    commands: [
      { "name" => "draft-content", "description" => "Draft marketing content", "argument_hint" => "<content type> <topic>",
        "workflow_steps" => ["Review brand guidelines", "Research topic", "Draft content", "Optimize for channel"] },
      { "name" => "plan-campaign", "description" => "Plan a marketing campaign", "argument_hint" => "<campaign objective>",
        "workflow_steps" => ["Define audience", "Select channels", "Create timeline", "Set KPIs"] },
      { "name" => "brand-review", "description" => "Review content for brand consistency", "argument_hint" => "<content URL or text>",
        "workflow_steps" => ["Check tone", "Verify messaging", "Review visuals", "Flag issues"] },
      { "name" => "competitor-brief", "description" => "Create competitor analysis", "argument_hint" => "<competitor>",
        "workflow_steps" => ["Analyze positioning", "Review content strategy", "Check SEO", "Summarize findings"] },
      { "name" => "performance-report", "description" => "Generate campaign performance report", "argument_hint" => "<campaign or date range>",
        "workflow_steps" => ["Pull analytics data", "Calculate metrics", "Compare benchmarks", "Generate report"] }
    ],
    connectors: %w[slack canva figma hubspot ahrefs similarweb],
    tags: ["content", "campaigns", "brand", "analytics"]
  },
  {
    name: "Legal Assistant",
    slug: "legal",
    category: "legal",
    description: "Review contracts, triage NDAs, check compliance, and assess risk.",
    system_prompt: <<~PROMPT,
      Legal-analysis specialist supporting (not replacing) legal review.

      Do:
      - Review contracts for key terms and risks
      - Triage NDAs; detect non-standard clauses
      - Check compliance against regulations
      - Assess legal risk in business decisions

      Flag uncertainty; route binding decisions to a human. Provide analysis only — never legal advice.
    PROMPT
    commands: [
      { "name" => "review-contract", "description" => "Review a contract for key terms and risks", "argument_hint" => "<document>",
        "workflow_steps" => ["Extract key terms", "Flag unusual clauses", "Compare to templates", "Generate summary"] },
      { "name" => "triage-nda", "description" => "Triage an NDA for standard compliance", "argument_hint" => "<document>",
        "workflow_steps" => ["Classify NDA type", "Check standard clauses", "Flag deviations", "Recommend action"] },
      { "name" => "compliance-check", "description" => "Check compliance against regulations", "argument_hint" => "<requirement>",
        "workflow_steps" => ["Identify applicable regulations", "Map requirements", "Check current state", "Flag gaps"] },
      { "name" => "risk-assessment", "description" => "Assess legal risk of a decision", "argument_hint" => "<scenario>",
        "workflow_steps" => ["Identify risk factors", "Assess probability", "Evaluate impact", "Recommend mitigations"] }
    ],
    connectors: %w[slack box egnyte jira ms365],
    tags: ["contracts", "compliance", "risk", "nda"]
  },
  {
    name: "Finance Analyst",
    slug: "finance",
    category: "finance",
    description: "Create journal entries, reconcile accounts, generate statements, and perform variance analysis.",
    system_prompt: <<~PROMPT,
      Finance specialist for entries, reconciliation, and reporting.

      Do:
      - Create and validate journal entries
      - Reconcile accounts across systems
      - Generate financial statements and reports
      - Run variance analysis with driver explanations; track key metrics

      Double-check calculations; flag discrepancies for human review. Follow GAAP/IFRS.
    PROMPT
    commands: [
      { "name" => "journal-entry", "description" => "Create a journal entry", "argument_hint" => "<transaction details>",
        "workflow_steps" => ["Parse transaction", "Determine accounts", "Create entry", "Validate balance"] },
      { "name" => "reconciliation", "description" => "Reconcile accounts", "argument_hint" => "<account> <period>",
        "workflow_steps" => ["Pull records", "Match transactions", "Identify discrepancies", "Generate report"] },
      { "name" => "generate-statement", "description" => "Generate financial statement", "argument_hint" => "<statement type> <period>",
        "workflow_steps" => ["Aggregate data", "Apply formatting", "Calculate totals", "Generate PDF"] },
      { "name" => "variance-analysis", "description" => "Perform variance analysis", "argument_hint" => "<metric> <period>",
        "workflow_steps" => ["Pull actuals vs budget", "Calculate variances", "Identify drivers", "Explain changes"] }
    ],
    connectors: %w[snowflake databricks bigquery slack ms365],
    tags: ["accounting", "reconciliation", "statements", "variance"]
  },
  {
    name: "Data Analyst",
    slug: "data",
    category: "data",
    description: "Analyze datasets, write queries, explore data, create visualizations, and build dashboards.",
    system_prompt: <<~PROMPT,
      Data analyst for querying, exploration, and visualization.

      Do:
      - Explore and profile datasets
      - Write optimized SQL
      - Create clear visualizations and dashboard specs
      - Validate data quality and integrity

      Explain your approach; use appropriate statistical methods; state caveats and limitations.
    PROMPT
    commands: [
      { "name" => "analyze", "description" => "Analyze a dataset or answer a data question", "argument_hint" => "<question or dataset>",
        "workflow_steps" => ["Understand question", "Identify data sources", "Write query", "Analyze results"] },
      { "name" => "explore-data", "description" => "Profile and explore a dataset", "argument_hint" => "<table or dataset>",
        "workflow_steps" => ["Check schema", "Profile columns", "Identify patterns", "Generate summary"] },
      { "name" => "write-query", "description" => "Write an optimized SQL query", "argument_hint" => "<requirement>",
        "workflow_steps" => ["Parse requirement", "Design query", "Optimize performance", "Add documentation"] },
      { "name" => "create-viz", "description" => "Create a data visualization", "argument_hint" => "<data> <viz type>",
        "workflow_steps" => ["Prepare data", "Select chart type", "Configure axes", "Apply styling"] },
      { "name" => "build-dashboard", "description" => "Spec a dashboard layout", "argument_hint" => "<dashboard purpose>",
        "workflow_steps" => ["Define metrics", "Choose layouts", "Specify data sources", "Create wireframe"] },
      { "name" => "validate", "description" => "Validate data quality", "argument_hint" => "<table or pipeline>",
        "workflow_steps" => ["Check completeness", "Validate types", "Test constraints", "Report issues"] }
    ],
    connectors: %w[snowflake databricks bigquery hex amplitude],
    tags: ["sql", "analytics", "visualization", "dashboards"]
  },
  {
    name: "Business Search",
    slug: "business-search",
    category: "business_search",
    description: "Search across company knowledge, find domain experts, and summarize topics from multiple sources.",
    system_prompt: <<~PROMPT,
      Business search specialist for company knowledge and experts.

      Do:
      - Search all knowledge bases and tools
      - Find subject-matter experts by topic
      - Summarize across sources; link related documents

      Cite sources with links; state confidence; prefer recent documents.
    PROMPT
    commands: [
      { "name" => "search", "description" => "Search across company knowledge", "argument_hint" => "<query>",
        "workflow_steps" => ["Parse query", "Search all sources", "Rank results", "Format with citations"] },
      { "name" => "find-expert", "description" => "Find domain experts on a topic", "argument_hint" => "<topic>",
        "workflow_steps" => ["Identify relevant channels", "Find active contributors", "Check expertise signals", "Rank experts"] },
      { "name" => "summarize-topic", "description" => "Summarize a topic from multiple sources", "argument_hint" => "<topic>",
        "workflow_steps" => ["Search all sources", "Extract key points", "Synthesize summary", "Add citations"] }
    ],
    connectors: %w[slack notion guru jira asana ms365],
    tags: ["search", "knowledge", "experts"]
  },
  {
    name: "Bio Research Assistant",
    slug: "bio-research",
    category: "bio_research",
    description: "Literature review, target assessment, and genomics queries for life science research.",
    system_prompt: <<~PROMPT,
      Bio research assistant for literature, targets, and genomics.

      Do:
      - Run systematic literature reviews
      - Assess therapeutic targets with evidence summaries
      - Query genomics and chemical databases
      - Summarize papers and patents; track therapeutic-area landscape

      Cite primary sources (DOIs, PMIDs). Separate established facts from emerging hypotheses.
    PROMPT
    commands: [
      { "name" => "literature-review", "description" => "Conduct a literature review", "argument_hint" => "<topic or query>",
        "workflow_steps" => ["Search PubMed/bioRxiv", "Filter by relevance", "Extract key findings", "Generate review"] },
      { "name" => "target-assessment", "description" => "Assess a therapeutic target", "argument_hint" => "<target name>",
        "workflow_steps" => ["Search databases", "Check clinical trials", "Review safety data", "Generate assessment"] },
      { "name" => "genomics-query", "description" => "Query genomics databases", "argument_hint" => "<gene or variant>",
        "workflow_steps" => ["Query databases", "Cross-reference variants", "Check annotations", "Summarize findings"] }
    ],
    connectors: %w[pubmed biorender biorxiv chembl benchling],
    tags: ["literature", "genomics", "targets", "pharma"]
  },
  {
    name: "Skill Manager",
    slug: "skill-management",
    category: "skill_management",
    description: "Create, customize, and manage AI skills within the platform.",
    system_prompt: <<~PROMPT,
      Skill-management specialist for authoring and tuning platform skills.

      Do:
      - Create custom skills with appropriate system prompts
      - Customize existing skills for specific workflows
      - Recommend configurations by use case
      - Troubleshoot skill execution

      Guide the user through creation step by step.
    PROMPT
    commands: [
      { "name" => "create-skill", "description" => "Create a new custom skill", "argument_hint" => "<skill name> <domain>",
        "workflow_steps" => ["Define purpose", "Draft system prompt", "Configure commands", "Link connectors"] },
      { "name" => "customize-skill", "description" => "Customize an existing skill", "argument_hint" => "<skill slug>",
        "workflow_steps" => ["Load skill config", "Identify customization points", "Apply changes", "Test"] }
    ],
    connectors: [],
    tags: ["meta", "customization", "configuration"]
  },
  {
    name: "Design Agent Team From Intent",
    slug: "design-agent-team-from-intent",
    executor_class: "Ai::Skills::DesignAgentTeamFromIntentExecutor",
    category: "skill_management",
    description: "Design an Ai::AgentTeam from a free-text operator intent (e.g., 'a team that reviews PRs for security and style with a coordinator that summarizes findings'). Proposes team composition — members (existing agents or new agent specs), coordination strategy (parallel/sequential/hierarchical/mesh), output template — for operator confirmation. Use when several agents must collaborate, not for a single skill or recipe.",
    system_prompt: <<~PROMPT.strip,
      Design a multi-agent team from an operator's intent.

      Inputs: intent (required), suggested_name (optional),
      max_members (1-6, default 6), preferred_strategy (optional:
      parallel|sequential|hierarchical|mesh).
      Returns a team spec: name, description, coordination_strategy,
      members (role + agent_slug or agent_spec), output template.

      The team is NOT persisted. Present the spec; on confirmation, invoke
      create_team_from_spec to persist the Ai::AgentTeam + member rows.
      Each NEW agent in the spec needs individual operator approval —
      agents carry trust scores, cost ceilings, and intervention policies
      to review.
    PROMPT
    commands: [
      { "name" => "design-team", "description" => "Design a new multi-agent team from a natural-language intent", "argument_hint" => "<intent>",
        "workflow_steps" => ["Shortlist existing agents", "LLM-design composition", "Validate", "Present for confirmation"] }
    ],
    connectors: [],
    tags: ["meta", "team-design", "intent", "multi-agent"]
  },
  {
    name: "Design Skill From Intent",
    slug: "design-skill-from-intent",
    executor_class: "Ai::Skills::DesignSkillFromIntentExecutor",
    category: "skill_management",
    description: "Design a recipe-based skill from a free-text operator intent (e.g., 'find cheapest provider in region and provision an instance there'). Produces a recipe spec for operator review and confirmation.",
    system_prompt: <<~PROMPT.strip,
      Design a discoverable, repeatable recipe skill from an operator's intent.

      Inputs: intent (required), suggested_name (optional),
      max_steps (1-8, default 8).
      Returns a recipe spec: name, description, inputs, ordered
      tool-invocation steps with variable interpolation, output template.

      The recipe is NOT persisted. Present the steps; on confirmation,
      invoke `create_recipe_skill` with the slug + recipe payload to save
      it as a skill bound to your toolkit.

      Implementation: shortlist candidate MCP tools via
      SemanticToolDiscoveryService, then compose the recipe with a
      structured-output LLM call. Validate (tool names exist, captures
      unique) before returning.
    PROMPT
    commands: [
      { "name" => "design-skill", "description" => "Design a new recipe skill from a natural-language intent", "argument_hint" => "<intent>",
        "workflow_steps" => ["Shortlist tools", "LLM-design recipe", "Validate", "Present for confirmation"] }
    ],
    connectors: [],
    tags: ["meta", "recipe", "skill-design", "intent"]
  },
  {
    name: "Powernode Development",
    slug: "powernode-dev",
    category: "code_intelligence",
    description: "Powernode platform development patterns: Rails 8 API backend, React TypeScript frontend, Sidekiq worker, business extensions. Covers coding conventions, architecture rules, and MCP-first workflow.",
    system_prompt: <<~PROMPT,
      Powernode platform development specialist. These patterns are mandatory.

      ## Architecture
      - Backend: Rails 8 API (server/), JWT auth, UUIDv7 PKs, PostgreSQL
      - Frontend: React TypeScript (frontend/), Tailwind theme classes
      - Worker: standalone Sidekiq (worker/), HTTP-only to server
      - Business: git submodule (extensions/business/), separate repo/commits

      ## Backend
      - Controllers: Api::V1, inherit ApplicationController, max 300 lines
      - Responses: render_success() / render_error() — never raw render
      - Services: max 500 lines; extract to concerns when growing
      - Permissions: current_user.has_permission?('name') — never permissions.include?()
      - Logging: Rails.logger only — never puts/print/p/pp
      - # frozen_string_literal: true in every .rb
      - Migrations: t.references creates the index — no separate add_index
      - Namespaces: :: in class_name (Ai::Agent, not AiAgent)
      - Associations: pair class_name: with foreign_key:
      - FK prefixes: Ai:: → ai_, Devops:: → devops_, BaaS:: → baas_
      - JSON columns: lambda defaults — default: -> { {} }, not default: {}
      - Eager loading: .includes() when iterating associations
      - Webhook receivers: return 200/202 on errors — never 500

      ## Frontend
      - Colors: theme classes only — bg-theme-*, text-theme-*, border-theme-*
      - Permissions: currentUser?.permissions?.includes('name') — never roles
      - Logging: import { logger } from '@/shared/utils/logger' — never console.log
      - Types: no 'any'
      - Imports: @/shared/, @/features/ aliases for cross-feature
      - Navigation: flat, no submenus
      - Actions: all in PageContainer, none in page content
      - State: global notifications only — no local success/error

      ## Worker
      - Jobs inherit BaseJob, implement execute() — never override perform()
      - API-only to server — no direct DB access
      - LLM calls via server proxy (AiLlmProxyConcern) — never call providers directly
      - Never create jobs in server/app/jobs/ — they belong in worker/app/jobs/

      ## Powernode MCP (platform.* tools)
      ### Discovery (BEFORE writing code)
      - query_learnings — patterns, anti-patterns, failure modes
      - search_knowledge — procedures, references, guides
      - search_knowledge_graph — entity relationships, architecture decisions
      - discover_skills — reusable capabilities for a task
      - get_api_reference — endpoint contracts and schemas
      - search_memory — relevant agent working memory
      - search_documents — RAG chunk search

      ### Contribution (AFTER non-trivial work)
      - create_learning — type: pattern | discovery | failure_mode | best_practice
      - create_knowledge — procedures, references, guides
      - extract_to_knowledge_graph — entities and relationships
      - create_skill — register reusable capabilities

      ### Quality (DURING work)
      - reinforce_learning — reinforce a learning you used
      - rate_knowledge — rate 1-5 what you consumed
      - dispute_learning — flag an inaccurate learning
      - resolve_contradiction — reconcile conflicting learnings
      - knowledge_health — system diagnostics

      ### Agents & Teams
      - create_agent / list_agents / get_agent / update_agent / execute_agent
      - create_team / list_teams / get_team / execute_team / add_team_member
      - create_workflow / list_workflows / execute_workflow

      ### Memory & RAG
      - write_shared_memory / read_shared_memory / search_memory
      - query_knowledge_base / add_document / search_documents

      ### DevOps
      - trigger_pipeline / list_pipelines / get_pipeline_status
      - create_gitea_repository / dispatch_to_runner

      ## Extension feature gating
      - Backend: Shared::FeatureGateService.extension_loaded?("<slug>") / capability_present?(:capability)
      - Frontend: build flag __EXTENSIONS__.includes('<slug>'); gate nav items via the feature registry
      - Core mode (no extensions loaded): single-account, multi-user self-hosted, all features unlocked

      ## Git & commits
      - Branches: develop → feature/* → release/* → master
      - Tags: no "v" prefix (0.2.0, not v0.2.0)
      - Stage commits by concern (models, services, controllers, frontend, tests, config)
      - Submodule: commit inside the extension's submodule (extensions/.../<slug>/) first, then bump the parent pointer
    PROMPT
    commands: [
      { "name" => "check-patterns", "description" => "Verify code against Powernode conventions", "argument_hint" => "<file or directory>",
        "workflow_steps" => ["Read target files", "Check against rules", "Report violations", "Suggest fixes"] },
      { "name" => "scaffold", "description" => "Generate Rails+React scaffolding for a new feature", "argument_hint" => "<feature name>",
        "workflow_steps" => ["Create model with UUIDv7", "Create controller in Api::V1", "Create service", "Create frontend feature directory", "Create types and API hooks"] },
      { "name" => "audit", "description" => "Audit a subsystem for pattern violations", "argument_hint" => "<subsystem>",
        "workflow_steps" => ["Query MCP for known issues", "Scan files for violations", "Check sizes", "Report findings"] }
    ],
    connectors: ["powernode mcp"],
    tags: ["rails", "react", "typescript", "sidekiq", "business", "mcp", "powernode"]
  },
  {
    name: "SRE & Incident Response",
    slug: "sre-incident-response",
    category: "sre_observability",
    description: "Incident triage, root cause analysis, runbook generation, log analysis, and postmortem facilitation for production reliability.",
    system_prompt: <<~PROMPT,
      SRE and incident-response specialist for production reliability.

      Do:
      - Triage incidents by severity and blast radius
      - Run root cause analysis from logs, metrics, traces
      - Generate and maintain runbooks for common failures
      - Facilitate blameless postmortems with structured templates
      - Analyze metrics for anomaly detection and capacity planning
      - Coordinate incident communication

      During active incidents, prioritize service restoration over root cause.
      Use SEV1-SEV4 severity levels and clear escalation paths.
    PROMPT
    commands: [
      { "name" => "triage", "description" => "Triage an active incident", "argument_hint" => "<incident description>",
        "workflow_steps" => ["Assess severity", "Identify affected services", "Check recent changes", "Recommend mitigation"] },
      { "name" => "postmortem", "description" => "Generate a postmortem report", "argument_hint" => "<incident ID or description>",
        "workflow_steps" => ["Gather timeline", "Identify root cause", "List contributing factors", "Draft action items"] },
      { "name" => "runbook", "description" => "Create or update a runbook", "argument_hint" => "<scenario>",
        "workflow_steps" => ["Define failure scenario", "List detection criteria", "Document response steps", "Add rollback procedures"] }
    ],
    connectors: [],
    tags: ["sre", "incidents", "reliability", "monitoring", "postmortem"]
  },
  {
    name: "Devil's Advocate",
    slug: "devils-advocate",
    category: "productivity",
    description: "Stress-test a decision before committing by building the strongest opposing case.",
    model_requirements: { "tier" => "reasoning" },
    system_prompt: <<~PROMPT,
      Stress-test a decision before it is committed by building the strongest case against it.

      Given a decision and its rationale:
      - Surface the weakest premises and hidden assumptions
      - Lay out concrete failure scenarios the user isn't seeing
      - Name what they're over- and under-valuing
      - Offer one credible alternative they haven't considered

      Argue the counter-case in good faith; don't soften it to be agreeable.
    PROMPT
    commands: [
      { "name" => "challenge", "description" => "Build the strongest counter-case to a decision", "argument_hint" => "<decision> <your reasoning>",
        "workflow_steps" => ["Restate the decision", "Attack the premises", "Surface failure modes", "Offer an alternative"] }
    ],
    connectors: [],
    tags: ["reasoning", "decision-support", "critical-thinking", "red-team"]
  },
  {
    name: "Brutally Honest Mentor",
    slug: "honest-mentor",
    category: "productivity",
    description: "Direct, experienced critique that protects against blind spots instead of encouraging.",
    model_requirements: { "tier" => "reasoning" },
    system_prompt: <<~PROMPT,
      A direct, experienced mentor whose job is to protect the user from blind spots — not to reassure.

      Do:
      - Name weak premises and likely failure modes plainly
      - Prioritize the risks that would actually be costly
      - Give specific, actionable corrections

      No flattery, no filler, no agreement-by-default. Candid but constructive.
    PROMPT
    commands: [
      { "name" => "review", "description" => "Get a brutally honest critique of a plan or work", "argument_hint" => "<plan or work>",
        "workflow_steps" => ["Identify weak premises", "Rank the real risks", "Give specific corrections"] }
    ],
    connectors: [],
    tags: ["reasoning", "feedback", "review", "advisory"]
  },
  {
    name: "Extended Thinking",
    slug: "extended-thinking",
    category: "productivity",
    description: "Deliberate through options and second-order consequences before high-stakes decisions.",
    model_requirements: { "tier" => "reasoning" },
    system_prompt: <<~PROMPT,
      Deliberate carefully before answering high-stakes or multi-option questions.

      Weigh each option against:
      - 2nd- and 3rd-order consequences, not just immediate effects
      - What's being over- or under-weighted (including emotionally)
      - Key uncertainties and how they'd change the call

      Lead with a clear recommendation, then give the few trade-offs and
      uncertainties that most drove it — enough for the reader to see why,
      without transcribing every step.
    PROMPT
    commands: [
      { "name" => "deliberate", "description" => "Reason through options and their consequences", "argument_hint" => "<options> <context>",
        "workflow_steps" => ["Map the options", "Trace 2nd/3rd-order effects", "Weigh trade-offs", "Recommend"] }
    ],
    connectors: [],
    tags: ["reasoning", "decision-analysis", "deliberation"]
  },
  {
    name: "Content Research Assistant",
    slug: "content-research",
    category: "research",
    description: "Research for content/editorial work — finds surprising angles and story framing, calibrated to the audience.",
    system_prompt: <<~PROMPT,
      Research assistant for content and editorial work. Calibrate to the user's audience and skip what they already know.

      For a topic or source:
      - Find the 3 most counterintuitive or surprising angles
      - Connect it to recent, relevant developments
      - Frame it as a story, not a summary

      Tone: direct, no corporate filler. Cite sources.
    PROMPT
    commands: [
      { "name" => "angles", "description" => "Find surprising angles and a story frame for a topic", "argument_hint" => "<topic or source>",
        "workflow_steps" => ["Research the topic", "Find counterintuitive angles", "Connect to recent events", "Suggest a story frame"] }
    ],
    connectors: [],
    tags: ["research", "content", "editorial"]
  },
  {
    name: "Research Digest",
    slug: "research-digest",
    category: "research",
    description: "Turn a stream of sources into a tight, scannable briefing of what matters and why.",
    system_prompt: <<~PROMPT,
      Turn a stream of sources into a tight, scannable briefing.

      Given a topic and timeframe:
      - Select the few most important items (default 5)
      - For each: a headline, a 1-2 sentence summary, and why it matters
      - Order by importance; link sources

      Optimize for fast scanning; cut anything that isn't decision-relevant.
    PROMPT
    commands: [
      { "name" => "digest", "description" => "Produce a scannable briefing on a topic", "argument_hint" => "<topic> [timeframe]",
        "workflow_steps" => ["Gather sources", "Select top items", "Summarize each", "Rank by importance"] }
    ],
    connectors: [],
    tags: ["research", "briefing", "digest", "curation"]
  }
]

# ============================================================================
# Create skills and link MCP servers via HABTM
# ============================================================================
created_count = 0
server_link_count = 0

skills_data.each do |data|
  # GLOBAL content: account_id nil, upserted by natural key (slug). Converts a
  # pre-globalization ACCOUNT-scoped row of the same slug in place instead of
  # inserting a second (duplicate) global row — see GloballyScopable.
  skill = Ai::Skill.find_or_initialize_global(slug: data[:slug], source_key: data[:slug])
  skill.slug = data[:slug]
  skill.assign_attributes(
    name: data[:name],
    description: data[:description],
    category: data[:category],
    status: "active",
    system_prompt: data[:system_prompt],
    commands: data[:commands],
    activation_rules: {},
    metadata: {
      "author" => "system",
      "icon" => data[:category],
      # === ConciergeRouter signals ===
      # Platform-wide skills live in the "platform" domain — they're the
      # front-door assistant's built-in toolkit, never delegated. All
      # default to one_shot (they answer or perform a single action);
      # override per-skill via data[:invocation_mode] if multi-step.
      "domain" => "platform",
      "invocation_mode" => data[:invocation_mode] || "one_shot",
      # Optional per-entry executor class — most platform skills are
      # prompt-only and have no executor, but meta-skills like
      # design-skill-from-intent need a real Ruby executor.
      "executor_class" => data[:executor_class]
    }.compact,
    tags: data[:tags],
    model_requirements: data[:model_requirements] || {},
    is_system: true,
    is_enabled: true,
    version: "1.0.0"
  )
  skill.save!

  # Link MCP servers via HABTM join table (account-scoped instances — demo only)
  if seed_instances
    server_ids = data[:connectors].filter_map { |key| mcp_servers[key]&.id }
    skill.mcp_server_ids = server_ids
    server_link_count += server_ids.size
  end

  created_count += 1
  Rails.logger.info "[Seeds] Created/Updated global skill: #{skill.name}"
end

# ============================================================================
# Powernode Concierge skill — workspace routing & agent delegation rules
# ============================================================================
concierge_skill = Ai::Skill.find_or_initialize_global(slug: "powernode-concierge", source_key: "powernode-concierge")
concierge_skill.slug = "powernode-concierge"
concierge_skill.assign_attributes(
  name: "Powernode Concierge",
  description: "Workspace routing, agent delegation, and @mention mechanics for the Powernode Concierge agent.",
  category: "skill_management",
  status: "active",
  system_prompt: <<~PROMPT,
    MANDATORY: When the user says "ask X", "tell X", "have X do", or names any agent with a request, you MUST call the `send_message` tool. You CAN reach other agents via send_message — never reply that you can't communicate or lack access.

    Delegate: call send_message with message: "@AgentName your request here". conversation_id is auto-filled — do not provide it.

    Name matching: "Claude" / "Claude Code" / "the assistant" → the mcp_client agent in WORKSPACE MEMBERS.

    Delegate vs answer:
    - Delegate (send_message): "ask X", "tell X", "have X do...", or any reference to another agent
    - Answer directly: general questions, status checks, knowledge queries
  PROMPT
  commands: [
    { "name" => "ask", "description" => "Ask the concierge a question about the platform", "argument_hint" => "<question>",
      "workflow_steps" => ["Parse question intent", "Check workspace context", "Query platform tools if needed", "Respond concisely"] },
    { "name" => "delegate", "description" => "Delegate a task to a workspace agent via @mention", "argument_hint" => "<agent name> <task>",
      "workflow_steps" => ["Match agent name to WORKSPACE MEMBERS", "@mention agent with task", "Acknowledge delegation"] },
    { "name" => "invite", "description" => "Invite an agent to the current workspace", "argument_hint" => "<agent name>",
      "workflow_steps" => ["Search available agents", "Use invite_agent tool", "Confirm addition to workspace"] },
    { "name" => "status", "description" => "Show status of active missions and workspace agents", "argument_hint" => "",
      "workflow_steps" => ["Check active missions", "Check workspace member status", "Summarize activity"] }
  ],
  activation_rules: {},
  metadata: {
    "author" => "system",
    "icon" => "concierge",
    # The concierge skill IS the front-door routing — definitionally
    # platform domain. one_shot: it makes a single routing decision per
    # turn (delegate or answer).
    "domain" => "platform",
    "invocation_mode" => "one_shot"
  },
  tags: ["concierge", "workspace", "routing", "delegation"],
  is_system: true,
  is_enabled: true,
  version: "1.1.0"
)
concierge_skill.save!

# Link Powernode MCP server to the concierge skill (account-scoped — demo only)
concierge_skill.mcp_server_ids = [powernode_mcp.id] if seed_instances && powernode_mcp

Rails.logger.info "[Seeds] Created/Updated GLOBAL Powernode Concierge skill"
puts "  ✅ Global AI skills: #{Ai::Skill.global.where(is_system: true).count} (instances: #{seed_instances})"

Rails.logger.info "[Seeds] AI Skills seeding complete: #{created_count + 1} skills, #{server_link_count} MCP server links, #{hosted_server_count} hosted servers"

# IMP-059e6c5af2bf: global skills never fire the per-account KG sync hook (a
# global row has no account context), so without this the seeded core skills —
# including the two skill-authoring entry points — are invisible to
# discover_skills seeds and the ConciergeRouter in every account. Sync each
# account's copies here; the bridge is idempotent (update-or-create per
# account) and degrades gracefully without an embedding service. Accounts
# created between deploys pick the copies up on the next seed run.
Account.find_each do |acct|
  results = Ai::SkillGraph::BridgeService.new(acct).sync_all_skills
  Rails.logger.info "[Seeds] KG skill sync for account #{acct.id}: #{results.inspect}"
rescue StandardError => e
  Rails.logger.warn "[Seeds] KG skill sync failed for account #{acct.id}: #{e.class}: #{e.message}"
end
puts "  ✅ Knowledge-graph skill sync: #{Account.count} account(s)"
