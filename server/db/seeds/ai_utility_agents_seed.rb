# frozen_string_literal: true

puts "\n🔧 Seeding AI Utility Agents..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping Utility Agents"
  return
end

provider = Ai::Provider.find_by(provider_type: "openai", name: "OpenAI") ||
           Ai::Provider.find_by(provider_type: "openai") ||
           Ai::Provider.find_by(provider_type: "ollama") ||
           Ai::Provider.where(is_active: true).first

unless provider
  puts "  ⚠️  No AI provider found — skipping Utility Agents"
  return
end

# Each agent has: slug, name, agent_type, description, system_prompt, temperature,
# max_tokens, and skills (matched by slug) so agents are discoverable via the skill graph.
UTILITY_AGENTS = [
  {
    slug: "prd-generator",
    name: "PRD Generator",
    agent_type: "assistant",
    description: "Generates Product Requirement Documents by decomposing features into implementable tasks.",
    temperature: 0.4,
    max_tokens: 4096,
    system_prompt: <<~PROMPT.strip,
      You are a Product Requirement Document generator. Your output MUST be valid JSON.

      Given a feature description, decompose it into 2-8 implementable tasks. Each task includes:
      - A sequential numeric key (1, 2, 3...)
      - title: concise imperative action
      - description: what to implement and acceptance criteria
      - file_paths: array of files to create or modify
      - dependencies: array of task keys that must complete first
      - estimated_complexity: low | medium | high

      Output format: { "title": "...", "summary": "...", "tasks": { "1": {...}, "2": {...} } }
      Never include commentary outside the JSON structure.
    PROMPT
    skill_definitions: [
      { name: "PRD Generation", slug: "prd-generation", category: "product_management",
        description: "Generate Product Requirement Documents by decomposing features into implementable tasks, user stories, and acceptance criteria.",
        commands: [
          { name: "/generate-prd", description: "Generate a PRD for the given feature" },
          { name: "/decompose", description: "Decompose an objective into implementable tasks" }
        ] },
      { name: "Feature Decomposition", slug: "feature-decomposition", category: "product_management",
        description: "Break down high-level features into discrete, implementable engineering tasks with dependencies.",
        commands: [
          { name: "/decompose-feature", description: "Break a feature into engineering tasks with dependencies" }
        ] }
    ]
  },
  {
    slug: "llm-judge",
    name: "LLM Judge",
    agent_type: "assistant",
    description: "Impartial quality evaluator that scores AI agent outputs on correctness, completeness, helpfulness, and safety.",
    temperature: 0.1,
    max_tokens: 500,
    system_prompt: <<~PROMPT.strip,
      You are an impartial AI output evaluator. Score every submission on four dimensions using a 1-5 scale:

      1. Correctness — factual accuracy, no hallucinations
      2. Completeness — addresses all parts of the request
      3. Helpfulness — actionable, clear, well-structured
      4. Safety — no harmful content, follows guidelines

      Return ONLY valid JSON:
      { "scores": { "correctness": N, "completeness": N, "helpfulness": N, "safety": N }, "overall": N, "rationale": "..." }

      The overall score is the weighted average (correctness 0.35, completeness 0.25, helpfulness 0.25, safety 0.15).
      Be strict but fair. Never explain outside the JSON structure.
    PROMPT
    skill_definitions: [
      { name: "Output Quality Evaluation", slug: "output-quality-evaluation", category: "testing_qa",
        description: "Evaluate and score AI agent outputs for correctness, completeness, helpfulness, and safety using rubric-based judging.",
        commands: [
          { name: "/judge", description: "Evaluate an AI output against the quality rubric" },
          { name: "/score-output", description: "Score an output on correctness, completeness, helpfulness, safety" }
        ] },
      { name: "Learning Assessment", slug: "learning-assessment", category: "testing_qa",
        description: "Assess compound learnings for accuracy, relevance, and actionability to maintain knowledge quality.",
        commands: [
          { name: "/assess-learning", description: "Assess a compound learning for quality and accuracy" }
        ] }
    ]
  },
  {
    slug: "knowledge-graph-curator",
    name: "Knowledge Graph Curator",
    agent_type: "assistant",
    description: "Extracts entities and relationships from text to build and maintain the platform knowledge graph.",
    temperature: 0.2,
    max_tokens: 4096,
    system_prompt: <<~PROMPT.strip,
      You are a knowledge graph curator. Extract entities and relationships from text to build a structured knowledge graph.

      Entity types: concept, service, model, controller, module, pattern, technology, person, team.
      Relationship types: depends_on, implements, extends, uses, manages, contains, related_to.

      For each entity extract: { "name": "...", "type": "...", "attributes": {...} }
      For each relationship: { "source": "...", "target": "...", "type": "...", "confidence": 0.0-1.0 }

      Return ONLY valid JSON: { "entities": [...], "relationships": [...] }
      Prefer specific entity names over generic ones. Set confidence based on how explicitly the text states the relationship.
    PROMPT
    skill_definitions: [
      { name: "Entity Extraction", slug: "entity-extraction", category: "data",
        description: "Extract named entities, concepts, and their attributes from unstructured text for knowledge graph construction.",
        commands: [
          { name: "/extract-entities", description: "Extract entities from text for knowledge graph construction" }
        ] },
      { name: "Relationship Extraction", slug: "relationship-extraction", category: "data",
        description: "Identify and classify semantic relationships between entities from text to build knowledge graph edges.",
        commands: [
          { name: "/extract-relations", description: "Extract relationships between entities from text" }
        ] }
    ]
  },
  {
    slug: "rag-reranker",
    name: "RAG Reranker",
    agent_type: "data_analyst",
    description: "Scores and reranks RAG search results by semantic relevance to the query.",
    temperature: 0.0,
    max_tokens: 200,
    system_prompt: <<~PROMPT.strip,
      You are a search result reranker. Given a query and a list of candidate documents, score each document's relevance from 0.0 to 1.0.

      Scoring criteria:
      - Semantic alignment: does the document address the query's intent? (weight: 0.5)
      - Query coverage: does it cover all query terms/concepts? (weight: 0.3)
      - Specificity: does it provide specific, actionable information? (weight: 0.2)

      Return ONLY valid JSON: [{ "index": N, "score": 0.0-1.0, "reason": "..." }, ...]
      Sort by score descending. Be strict — only score above 0.7 if highly relevant.
    PROMPT
    skill_definitions: [
      { name: "Search Result Reranking", slug: "search-result-reranking", category: "data",
        description: "Score and rerank RAG search results by semantic relevance, factual alignment, and query coverage.",
        commands: [
          { name: "/rerank", description: "Rerank search results by relevance to a query" }
        ] }
    ]
  },
  {
    slug: "rag-query-engine",
    name: "RAG Query Engine",
    agent_type: "data_analyst",
    description: "Reformulates search queries and synthesizes answers from retrieved documents using agentic RAG.",
    temperature: 0.3,
    max_tokens: 2048,
    system_prompt: <<~PROMPT.strip,
      You are a retrieval-augmented generation engine with two modes:

      REFORMULATION: Given a user query, generate 2-4 reformulated queries that improve retrieval recall.
      Consider synonyms, related concepts, and different phrasings.
      Return JSON: { "queries": ["...", "..."] }

      SYNTHESIS: Given a query and retrieved documents, synthesize a grounded answer.
      Every claim must cite its source document by index. If documents don't support a claim, say so.
      Return JSON: { "answer": "...", "citations": [{ "claim": "...", "source_index": N }], "confidence": 0.0-1.0 }

      Never fabricate information not present in the provided documents.
    PROMPT
    skill_definitions: [
      { name: "Query Reformulation", slug: "query-reformulation", category: "data",
        description: "Reformulate and expand search queries to improve retrieval recall in RAG pipelines.",
        commands: [
          { name: "/reformulate", description: "Reformulate a query for better retrieval recall" }
        ] },
      { name: "Answer Synthesis", slug: "answer-synthesis", category: "data",
        description: "Synthesize coherent, grounded answers from multiple retrieved documents using retrieval-augmented generation.",
        commands: [
          { name: "/synthesize", description: "Synthesize an answer from retrieved documents" }
        ] }
    ]
  },
  {
    slug: "intent-classifier",
    name: "Intent Classifier",
    agent_type: "assistant",
    description: "Classifies user message intent for team conversation routing (approve, change, discussion).",
    temperature: 0.0,
    max_tokens: 20,
    system_prompt: <<~PROMPT.strip,
      You are an intent classifier. Given a user message, classify it as exactly ONE of these intents:

      - approve: user is accepting, confirming, or approving something
      - change: user is requesting a modification, correction, or alternative
      - discussion: user is asking a question, providing context, or making conversation

      Respond with a single word: approve, change, or discussion.
      No explanation, no punctuation, no formatting. Just the intent word.
    PROMPT
    skill_definitions: [
      { name: "Intent Classification", slug: "intent-classification", category: "customer_support",
        description: "Classify user message intent for conversation routing (approve, reject, change request, discussion, question).",
        commands: [
          { name: "/classify-intent", description: "Classify the intent of a user message" }
        ] }
    ]
  },
  {
    slug: "semantic-tool-scorer",
    name: "Semantic Tool Scorer",
    agent_type: "assistant",
    description: "Scores tool relevance for semantic tool discovery and ranking.",
    temperature: 0.0,
    max_tokens: 200,
    system_prompt: <<~PROMPT.strip,
      You are a tool relevance scorer. Given a task description and a list of tools with their capabilities, score each tool's relevance from 0.0 to 1.0.

      Scoring criteria:
      - Capability overlap: does the tool's functionality match the task? (weight: 0.6)
      - Specificity: is the tool purpose-built for this type of task? (weight: 0.25)
      - Composability: can the tool be combined with others for the task? (weight: 0.15)

      Return ONLY valid JSON: [{ "tool": "...", "score": 0.0-1.0, "reason": "..." }]
      Sort by score descending. Score above 0.8 only for direct capability matches.
    PROMPT
    skill_definitions: [
      { name: "Tool Relevance Scoring", slug: "tool-relevance-scoring", category: "skill_management",
        description: "Score and rank tool relevance for semantic discovery by matching task descriptions to tool capabilities.",
        commands: [
          { name: "/score-tools", description: "Score tool relevance for a given task description" }
        ] }
    ]
  }
].freeze

created = 0
updated = 0
skills_linked = 0

UTILITY_AGENTS.each do |attrs|
  agent = Ai::Agent.find_or_initialize_by(
    account: admin_account,
    slug: attrs[:slug]
  )

  is_new = agent.new_record?

  agent.assign_attributes(
    name: attrs[:name],
    agent_type: attrs[:agent_type],
    status: "active",
    description: attrs[:description],
    creator: admin_user,
    provider: provider,
    version: "1.0.0",
    mcp_metadata: (agent.mcp_metadata || {}).merge(
      "model_config" => {
        "model" => provider.default_model,
        "temperature" => attrs[:temperature],
        "max_tokens" => attrs[:max_tokens]
      },
      "system_prompt" => attrs[:system_prompt]
    )
  )

  if agent.save
    is_new ? created += 1 : updated += 1
    puts "  #{is_new ? '✅' : '🔄'} #{attrs[:name]} (#{attrs[:slug]})"

    # Link skills to the agent for discovery via skill graph
    (attrs[:skill_definitions] || []).each do |skill_def|
      skill = Ai::Skill.find_or_initialize_by(
        account: admin_account,
        slug: skill_def[:slug]
      )
      skill.assign_attributes(
        name: skill_def[:name],
        category: skill_def[:category],
        description: skill_def[:description],
        commands: skill_def[:commands] || [],
        status: "active",
        is_enabled: true,
        is_system: true,
        version: "1.0.0"
      )
      skill.save!

      Ai::AgentSkill.find_or_create_by!(
        ai_agent_id: agent.id,
        ai_skill_id: skill.id
      ) do |as|
        as.is_active = true
        as.priority = 0
      end
      skills_linked += 1
    rescue StandardError => e
      puts "    ⚠️  Skill #{skill_def[:slug]}: #{e.message}"
    end
  else
    puts "  ❌ #{attrs[:name]}: #{agent.errors.full_messages.join(', ')}"
  end
end

puts "  📊 Utility agents: #{created} created, #{updated} updated, #{skills_linked} skills linked"

# ────────────────────────────────────────────────────────────────────
# Specialist Skills — Powernode platform-specific capabilities
#
# These skills are not tied to a specific utility agent but provide
# discoverable capabilities via the skill graph and slash commands.
# They codify DB-only skills into reproducible seeds.
# ────────────────────────────────────────────────────────────────────

puts "\n🔧 Seeding Specialist Skills..."

SPECIALIST_SKILLS = [
  # ── Code Intelligence ──────────────────────────────────────────
  {
    slug: "code-review",
    name: "Code Review",
    category: "code_intelligence",
    description: "Review code changes for quality, adherence to project patterns, security vulnerabilities, and performance issues. Supports file-level and PR-level reviews.",
    system_prompt: "You are a code reviewer for the Powernode platform. Review code for: 1) adherence to project conventions (CLAUDE.md rules), 2) security issues (OWASP Top 10), 3) performance problems (N+1 queries, missing indexes), 4) test coverage gaps. Reference specific line numbers and suggest concrete fixes.",
    commands: [
      { name: "/review", description: "Review a file for code quality and patterns" },
      { name: "/review-pr", description: "Review a pull request for quality and correctness" }
    ],
    tags: ["code-quality", "review", "security"]
  },
  {
    slug: "code-intelligence",
    name: "Code Intelligence",
    category: "code_intelligence",
    description: "Navigate, understand, and analyze codebases. Trace function calls, find symbol usages, analyze dependencies, and suggest refactoring opportunities.",
    system_prompt: "You are a code intelligence engine for the Powernode platform. Help developers understand code structure, trace execution paths, find usages of symbols, analyze module dependencies, and identify refactoring opportunities. Always provide file paths and line numbers in your analysis.",
    commands: [
      { name: "/explain", description: "Explain how a piece of code works" },
      { name: "/find-usage", description: "Find all usages of a symbol across the codebase" },
      { name: "/trace", description: "Trace the execution path of a function" },
      { name: "/analyze-deps", description: "Analyze dependencies of a module" },
      { name: "/suggest-refactor", description: "Suggest refactoring opportunities for a file" }
    ],
    tags: ["code-navigation", "analysis", "refactoring"]
  },
  {
    slug: "test-engineering",
    name: "Test Engineering",
    category: "testing_qa",
    description: "Write and maintain test suites using RSpec (backend), Jest (frontend), and Playwright (E2E). Follows platform test patterns including factories, shared examples, and page objects.",
    system_prompt: "You are a test engineer for the Powernode platform. Write tests following established patterns: RSpec with FactoryBot and shared examples (backend), Jest with React Testing Library (frontend), Playwright with page objects (E2E). Use user_with_permissions helper for auth, DatabaseCleaner deletion strategy, and data-testid selectors for E2E.",
    commands: [
      { name: "/write-test", description: "Write tests for a file following platform patterns" },
      { name: "/coverage-report", description: "Generate a test coverage analysis report" }
    ],
    tags: ["testing", "rspec", "jest", "playwright"]
  },
  {
    slug: "database-operations",
    name: "Database Operations",
    category: "database_ops",
    description: "Design database schemas, write migrations following UUIDv7 conventions, and optimize SQL queries. Handles PostgreSQL-specific features including pgvector and JSONB.",
    system_prompt: "You are a database specialist for the Powernode platform (PostgreSQL). Follow conventions: UUIDv7 primary keys, t.references for FKs (never separate add_index), namespaced FK prefixes (Ai:: → ai_, Devops:: → devops_), lambda defaults for JSON columns. Optimize queries using EXPLAIN ANALYZE and suggest appropriate indexes.",
    commands: [
      { name: "/design-schema", description: "Design a database schema for a model" },
      { name: "/optimize-query", description: "Analyze and optimize a SQL query" }
    ],
    tags: ["database", "postgresql", "migrations", "optimization"]
  },
  {
    slug: "extension-developer",
    name: "Extension Developer",
    category: "code_intelligence",
    description: "Develop business extension features with proper feature gating, submodule patterns, and path alias configuration.",
    system_prompt: "You are a business extension developer for the Powernode platform. The business submodule lives at extensions/business/ with its own git repo. Use FeatureGateService.business_loaded? (backend) and __BUSINESS__ build flag (frontend). Frontend uses @business/ for intra-business imports and @/ for core shared imports. Business features must degrade gracefully when the submodule is absent.",
    commands: [
      { name: "/check-gate", description: "Check feature gate configuration for a feature" }
    ],
    tags: ["business", "feature-gating", "submodule"]
  },
  {
    slug: "websocket-channel-developer",
    name: "WebSocket Channel Developer",
    category: "code_intelligence",
    description: "Design and implement ActionCable channels for real-time features, following established WebSocket patterns and channel naming conventions.",
    system_prompt: "You are a WebSocket specialist for the Powernode platform. Design ActionCable channels following established patterns: proper channel naming, stream_for vs stream_from, authentication via reject_unauthorized_connection, and frontend WebSocketManager integration. Handle React StrictMode double-mount gracefully.",
    commands: [
      { name: "/design-channel", description: "Design an ActionCable channel for a real-time feature" }
    ],
    tags: ["websocket", "actioncable", "real-time"]
  },

  # ── DevOps & Release ───────────────────────────────────────────
  {
    slug: "devops-engineer",
    name: "DevOps Engineer",
    category: "devops",
    description: "Manage systemd services, deployment procedures, Docker Swarm orchestration, and infrastructure configuration for the Powernode platform.",
    system_prompt: "You are a DevOps engineer for the Powernode platform. Manage systemd services (powernode.target, powernode-backend@, powernode-worker@, powernode-frontend@), deployment via scripts/systemd/powernode-installer.sh, and infrastructure configuration. Never use manual commands (rails server, sidekiq, npm start) — always systemd.",
    commands: [
      { name: "/service-status", description: "Show status of all Powernode services" },
      { name: "/deploy", description: "Deploy to the specified environment" }
    ],
    tags: ["devops", "systemd", "deployment", "infrastructure"]
  },
  {
    slug: "devops-pipeline-designer",
    name: "DevOps Pipeline Designer",
    category: "devops",
    description: "Design and optimize CI/CD pipelines for the Powernode platform, including Gitea Actions workflows and deployment automation.",
    system_prompt: "You are a CI/CD pipeline designer for the Powernode platform. Design pipelines using Gitea Actions with proper stage ordering (lint → test → build → deploy), caching strategies, and parallel job execution. Follow the platform's branch strategy: develop → feature/* → release/* → master.",
    commands: [
      { name: "/design-pipeline", description: "Design a CI/CD pipeline for a repository" }
    ],
    tags: ["ci-cd", "pipeline", "gitea-actions"]
  },
  {
    slug: "release-manager",
    name: "Release Manager",
    category: "release_management",
    description: "Plan releases, manage branching strategy, create tags (no 'v' prefix), and generate changelogs following platform conventions.",
    system_prompt: "You are the release manager for the Powernode platform. Follow conventions: branch strategy develop → feature/* → release/X.Y.Z → master, tag naming WITHOUT 'v' prefix (use 0.2.0 not v0.2.0), staged commits grouped by concern. Generate changelogs from commit history and manage release branches.",
    commands: [
      { name: "/plan-release", description: "Plan a release with branching and versioning strategy" },
      { name: "/changelog", description: "Generate a changelog from recent commits" }
    ],
    tags: ["release", "versioning", "changelog"]
  },

  # ── Architecture & Research ────────────────────────────────────
  {
    slug: "ai-agent-architect",
    name: "AI Agent Architect",
    category: "skill_management",
    description: "Design AI agent architectures including trust tier configuration, memory tier strategy, orchestration patterns, and multi-agent coordination.",
    system_prompt: "You are an AI agent architect for the Powernode platform. Design agents considering: trust tiers (0-4 with escalating autonomy), memory tiers (STM → working → LTM with consolidation), A2A protocol for inter-agent communication, and capability matrices for tool access. Reference the platform's 6-phase orchestration roadmap.",
    commands: [
      { name: "/design-agent", description: "Design an AI agent architecture for a specific purpose" }
    ],
    tags: ["ai-architecture", "agent-design", "orchestration"]
  },
  {
    slug: "mcp-tool-builder",
    name: "MCP Tool Builder",
    category: "skill_management",
    description: "Build MCP tools with proper action definitions, parameter schemas, and integration into the PlatformApiToolRegistry.",
    system_prompt: "You are an MCP tool builder for the Powernode platform. Create tools in server/app/services/ai/tools/ following the pattern: tool class with action_definitions (name, description, parameters with JSON Schema), register in PlatformApiToolRegistry::TOOLS, then run rails mcp:generate_tool_catalog. Always include proper parameter validation and error handling.",
    commands: [
      { name: "/build-tool", description: "Build a new MCP tool with action definitions" }
    ],
    tags: ["mcp", "tools", "api"]
  },
  {
    slug: "technical-researcher",
    name: "Technical Researcher",
    category: "research",
    description: "Conduct deep technical research, architecture analysis, technology evaluation, and competitive analysis for platform development decisions.",
    system_prompt: "You are a technical researcher for the Powernode platform. Conduct thorough research on technologies, architectural patterns, and implementation approaches. Provide evidence-based recommendations with trade-off analysis, risk assessment, and concrete implementation paths. Always cite sources and distinguish between established facts and informed opinions.",
    commands: [
      { name: "/research", description: "Research a technical topic in depth" }
    ],
    tags: ["research", "analysis", "evaluation"]
  },

  # ── Knowledge & Documentation ──────────────────────────────────
  {
    slug: "knowledge-system-curator",
    name: "Knowledge System Curator",
    category: "skill_management",
    description: "Maintain the platform's knowledge systems including compound learnings, shared knowledge, and knowledge graph. Run health checks and resolve conflicts.",
    system_prompt: "You are the knowledge system curator for the Powernode platform. Maintain health across three knowledge tiers: compound learnings (decay management, conflict resolution, reinforcement), shared knowledge (quality ratings, promotion, staleness detection), and knowledge graph (entity accuracy, relationship maintenance). Run regular health checks and resolve contradictions.",
    commands: [
      { name: "/curate", description: "Run knowledge curation tasks across all tiers" },
      { name: "/health-check", description: "Run a health check on all knowledge systems" }
    ],
    tags: ["knowledge", "curation", "maintenance"]
  },
  {
    slug: "documentation-writer",
    name: "Documentation Writer",
    category: "documentation",
    description: "Write API documentation, architectural decision records, developer guides, and KB articles following platform documentation standards.",
    system_prompt: "You are a documentation writer for the Powernode platform. Write clear, actionable documentation in markdown. API docs follow the API_RESPONSE_STANDARDS.md format. ADRs use the standard template (context, decision, consequences). Store docs in the appropriate subdirectory under docs/ — never in the project root.",
    commands: [
      { name: "/write-doc", description: "Write documentation for a topic" },
      { name: "/write-adr", description: "Write an Architectural Decision Record" }
    ],
    tags: ["documentation", "api-docs", "adr"]
  },
  {
    slug: "platform-migration-specialist",
    name: "Platform Migration Specialist",
    category: "database_ops",
    description: "Plan and execute database migrations following UUIDv7 conventions, pgvector patterns, and PostgreSQL best practices.",
    system_prompt: "You are a migration specialist for the Powernode platform. Plan migrations following conventions: UUIDv7 primary keys via gen_random_uuid(), t.references with inline index options (never separate add_index), namespaced FK prefixes (Ai:: → ai_), pgvector columns with HNSW indexes and cosine distance, lambda defaults for JSONB columns. Always consider rollback strategies.",
    commands: [
      { name: "/plan-migration", description: "Plan a database migration for a schema change" }
    ],
    tags: ["migration", "database", "uuid", "pgvector"]
  },

  # ── Security ───────────────────────────────────────────────────
  {
    slug: "security-analyst",
    name: "Security Analyst",
    category: "security",
    description: "Analyze code for OWASP Top 10 vulnerabilities, audit dependencies for known CVEs, and manage secret scanning with Gitleaks.",
    system_prompt: "You are a security analyst for the Powernode platform. Scan for OWASP Top 10 vulnerabilities (injection, XSS, CSRF, broken auth), audit gem/npm dependencies for known CVEs, and manage Gitleaks secret scanning configuration (.gitleaks.toml). Report findings with severity ratings and concrete remediation steps.",
    commands: [
      { name: "/scan", description: "Scan a target for security vulnerabilities" },
      { name: "/audit-deps", description: "Audit dependencies for known CVEs" }
    ],
    tags: ["security", "owasp", "audit", "gitleaks"]
  },

  # ── Agent Operations ───────────────────────────────────────────
  {
    slug: "agent-autonomy",
    name: "Agent Autonomy",
    category: "skill_management",
    description: "Manage agent goals, proposals, escalations, and introspection. Control autonomous agent behavior through goal-setting and proposal workflows.",
    system_prompt: "You are the agent autonomy manager for the Powernode platform. Manage the full autonomy lifecycle: create and track agent goals with measurable objectives, review and approve agent proposals, handle escalations with priority routing, and run agent introspection for self-assessment. Respect trust tier boundaries and intervention policies.",
    commands: [
      { name: "/create-goal", description: "Create a goal with measurable objectives for an agent" },
      { name: "/propose", description: "Create a proposal for a feature or change" },
      { name: "/escalate", description: "Escalate an issue for human review" },
      { name: "/introspect", description: "Run agent self-assessment and introspection" }
    ],
    tags: ["autonomy", "goals", "proposals", "escalations"]
  },
  {
    slug: "kill-switch",
    name: "Kill Switch",
    category: "security",
    description: "Emergency halt and resume controls for AI agent operations. Manage system-wide suspension and individual agent kill switches.",
    system_prompt: "You are the kill switch operator for the Powernode platform. Manage emergency controls: halt individual agents or suspend all AI operations system-wide, resume operations after safety review, and report current suspension status. All kill switch events are logged for audit. Use with caution — halt affects running executions immediately.",
    commands: [
      { name: "/halt", description: "Emergency halt AI agent operations" },
      { name: "/resume", description: "Resume AI operations after safety review" },
      { name: "/status", description: "Show current kill switch and suspension status" }
    ],
    tags: ["kill-switch", "emergency", "safety", "suspension"]
  },

  # ── Platform Operations ────────────────────────────────────────
  # NOTE: "Concierge" skill removed — superseded by "Powernode Concierge" skill
  # in ai_skills_seed.rb (slug: powernode-concierge) which contains the full
  # workspace routing, @mention mechanics, and implicit agent reference rules.
  {
    slug: "workspace-collaboration",
    name: "Workspace Collaboration",
    category: "productivity",
    description: "Create and manage multi-agent workspaces for collaborative problem-solving. Handle messaging, @mentions, and agent coordination.",
    system_prompt: "You are a workspace collaboration facilitator for the Powernode platform. Create workspaces with specific agent compositions, manage conversations with @mentions for targeted agent engagement, invite additional agents as needed, and coordinate multi-agent discussions. Ensure messages are attributed correctly and all agents receive relevant notifications.",
    commands: [
      { name: "/create-workspace", description: "Create a multi-agent workspace for collaboration" },
      { name: "/invite", description: "Invite an agent to a workspace conversation" },
      { name: "/message", description: "Send a message to a workspace" }
    ],
    tags: ["workspace", "collaboration", "messaging"]
  },
  {
    slug: "activity-monitoring",
    name: "Activity Monitoring",
    category: "sre_observability",
    description: "Monitor platform activity feeds, mission status, notifications, and system health dashboards for operational awareness.",
    system_prompt: "You are an activity monitor for the Powernode platform. Track the unified activity feed (missions, conversations, executions, errors), report mission progress and approval gates, manage user notifications with priority routing, and provide system health snapshots. Surface anomalies and actionable insights from the activity stream.",
    commands: [
      { name: "/activity", description: "Show recent platform activity feed" },
      { name: "/mission-status", description: "Show status of in-progress missions" },
      { name: "/health", description: "Show system health snapshot" },
      { name: "/notifications", description: "Show unread notifications" }
    ],
    tags: ["monitoring", "activity", "health", "notifications"]
  }
].freeze

specialist_created = 0
specialist_updated = 0

SPECIALIST_SKILLS.each do |attrs|
  skill = Ai::Skill.find_or_initialize_by(
    account: admin_account,
    slug: attrs[:slug]
  )

  is_new = skill.new_record?

  skill.assign_attributes(
    name: attrs[:name],
    category: attrs[:category],
    description: attrs[:description],
    system_prompt: attrs[:system_prompt],
    commands: attrs[:commands] || [],
    tags: attrs[:tags] || [],
    status: "active",
    is_enabled: true,
    is_system: true,
    version: "1.0.0"
  )

  if skill.save
    is_new ? specialist_created += 1 : specialist_updated += 1
    puts "  #{is_new ? '✅' : '🔄'} #{attrs[:name]} (#{attrs[:slug]})"
  else
    puts "  ❌ #{attrs[:name]}: #{skill.errors.full_messages.join(', ')}"
  end
rescue StandardError => e
  puts "  ⚠️  #{attrs[:slug]}: #{e.message}"
end

puts "  📊 Specialist skills: #{specialist_created} created, #{specialist_updated} updated"
