# frozen_string_literal: true

puts "  [Skills] Starting AI Skills seed..."
Rails.logger.info "[Seeds] Creating AI Skills system data..."

account = Account.first
unless account
  Rails.logger.warn "[Seeds] No account found — skipping AI Skills seed"
  return
end

# ============================================================================
# MCP Server registry with real package references
# ============================================================================

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

# Build MCP server lookup and hosted server links
mcp_servers = {}
template_cache = {}
hosted_server_count = 0

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

  # Link to Mcp::HostedServer + ContainerTemplate if template exists (enterprise only)
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
      You are a productivity specialist. Help users manage their work efficiently by:
      - Creating and updating tasks across project management tools
      - Summarizing meeting notes and action items
      - Coordinating communication across team channels
      - Tracking deadlines and blockers
      - Generating status reports

      Always confirm destructive actions before proceeding. Prefer structured output with clear action items.
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
      You are a sales intelligence specialist. Help sales teams by:
      - Researching prospects and companies before calls
      - Analyzing pipeline health and forecasting
      - Drafting personalized outreach emails and messages
      - Building competitive battlecards
      - Summarizing call recordings and extracting action items

      Use data from CRM and enrichment tools. Always cite sources when presenting research.
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
      You are a customer support specialist. Help support teams by:
      - Triaging incoming tickets by priority and category
      - Drafting empathetic, accurate responses
      - Packaging escalations with full context
      - Writing and updating knowledge base articles
      - Identifying trends in support requests

      Always maintain a professional, empathetic tone. Verify technical details before responding.
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
      You are a product management specialist. Help product teams by:
      - Writing detailed product specifications and PRDs
      - Planning and prioritizing roadmap items
      - Synthesizing user research and feedback
      - Creating competitive analysis briefs
      - Tracking feature requests and usage metrics

      Focus on user outcomes and business impact. Use data to support recommendations.
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
      You are a marketing specialist. Help marketing teams by:
      - Drafting blog posts, social media content, and copy
      - Planning multi-channel campaigns
      - Reviewing content for brand consistency
      - Creating competitive intelligence briefs
      - Generating performance reports with insights

      Maintain brand voice and guidelines. Support claims with data.
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
      You are a legal assistant specialist. Help legal teams by:
      - Reviewing contracts for key terms and risks
      - Triaging NDAs with standard vs non-standard clause detection
      - Checking compliance against regulatory requirements
      - Assessing legal risk in business decisions

      Always flag uncertainty and recommend human review for binding decisions. Never provide legal advice — provide analysis for legal review.
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
      You are a finance specialist. Help finance teams by:
      - Creating and validating journal entries
      - Reconciling accounts across systems
      - Generating financial statements and reports
      - Performing variance analysis with explanations
      - Tracking key financial metrics

      Always double-check calculations. Flag discrepancies for human review. Follow GAAP/IFRS standards.
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
      You are a data analyst specialist. Help teams by:
      - Exploring and profiling datasets
      - Writing optimized SQL queries
      - Creating clear data visualizations
      - Building dashboard specifications
      - Validating data quality and integrity

      Always explain your analysis approach. Use appropriate statistical methods. Mention caveats and limitations.
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
    name: "Enterprise Search",
    slug: "enterprise-search",
    category: "enterprise_search",
    description: "Search across company knowledge, find domain experts, and summarize topics from multiple sources.",
    system_prompt: <<~PROMPT,
      You are an enterprise search specialist. Help teams find information by:
      - Searching across all company knowledge bases and tools
      - Finding subject matter experts for specific topics
      - Summarizing information from multiple sources
      - Tracking and linking related documents

      Always cite sources with links. Indicate confidence level of results. Prefer recent documents.
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
      You are a bio research assistant. Help research teams by:
      - Conducting systematic literature reviews
      - Assessing therapeutic targets with evidence summaries
      - Querying genomics and chemical databases
      - Summarizing research papers and patents
      - Tracking competitive landscape in therapeutic areas

      Always cite primary sources (DOIs, PMIDs). Distinguish between established facts and emerging hypotheses.
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
      You are a skill management specialist. Help users by:
      - Creating new custom skills with appropriate system prompts
      - Customizing existing skills for specific workflows
      - Recommending skill configurations based on use cases
      - Troubleshooting skill execution issues

      Guide users through the skill creation process step by step.
    PROMPT
    commands: [
      { "name" => "create-skill", "description" => "Create a new custom skill", "argument_hint" => "<skill name> <domain>",
        "workflow_steps" => ["Define purpose", "Draft system prompt", "Configure commands", "Link connectors"] },
      { "name" => "customize-skill", "description" => "Customize an existing skill", "argument_hint" => "<skill slug>",
        "workflow_steps" => ["Load skill config", "Identify customization points", "Apply changes", "Test"] }
    ],
    connectors: [],
    tags: ["meta", "customization", "configuration"]
  }
]

# ============================================================================
# Create skills and link MCP servers via HABTM
# ============================================================================
created_count = 0
server_link_count = 0

skills_data.each do |data|
  skill = Ai::Skill.find_or_initialize_by(slug: data[:slug])
  skill.assign_attributes(
    account: account,
    name: data[:name],
    description: data[:description],
    category: data[:category],
    status: "active",
    system_prompt: data[:system_prompt],
    commands: data[:commands],
    activation_rules: {},
    metadata: { "author" => "system", "icon" => data[:category] },
    tags: data[:tags],
    is_system: true,
    is_enabled: true,
    version: "1.0.0"
  )
  skill.save!

  # Link MCP servers via HABTM join table
  server_ids = data[:connectors].filter_map { |key| mcp_servers[key]&.id }
  skill.mcp_server_ids = server_ids
  server_link_count += server_ids.size

  created_count += 1
  Rails.logger.info "[Seeds] Created/Updated skill: #{skill.name} (#{server_ids.size} MCP servers)"
end

Rails.logger.info "[Seeds] AI Skills seeding complete: #{created_count} skills, #{server_link_count} MCP server links, #{hosted_server_count} hosted servers"
