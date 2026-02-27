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

# Each agent has: slug, name, agent_type, description, temperature, max_tokens,
# and skills (matched by slug) so agents are discoverable via the skill graph.
UTILITY_AGENTS = [
  {
    slug: "prd-generator",
    name: "PRD Generator",
    agent_type: "assistant",
    description: "Generates Product Requirement Documents by decomposing features into implementable tasks.",
    temperature: 0.4,
    max_tokens: 4096,
    skill_definitions: [
      { name: "PRD Generation", slug: "prd-generation", category: "product_management",
        description: "Generate Product Requirement Documents by decomposing features into implementable tasks, user stories, and acceptance criteria." },
      { name: "Feature Decomposition", slug: "feature-decomposition", category: "product_management",
        description: "Break down high-level features into discrete, implementable engineering tasks with dependencies." }
    ]
  },
  {
    slug: "llm-judge",
    name: "LLM Judge",
    agent_type: "assistant",
    description: "Impartial quality evaluator that scores AI agent outputs on correctness, completeness, helpfulness, and safety.",
    temperature: 0.1,
    max_tokens: 500,
    skill_definitions: [
      { name: "Output Quality Evaluation", slug: "output-quality-evaluation", category: "testing_qa",
        description: "Evaluate and score AI agent outputs for correctness, completeness, helpfulness, and safety using rubric-based judging." },
      { name: "Learning Assessment", slug: "learning-assessment", category: "testing_qa",
        description: "Assess compound learnings for accuracy, relevance, and actionability to maintain knowledge quality." }
    ]
  },
  {
    slug: "knowledge-graph-curator",
    name: "Knowledge Graph Curator",
    agent_type: "assistant",
    description: "Extracts entities and relationships from text to build and maintain the platform knowledge graph.",
    temperature: 0.2,
    max_tokens: 4096,
    skill_definitions: [
      { name: "Entity Extraction", slug: "entity-extraction", category: "data",
        description: "Extract named entities, concepts, and their attributes from unstructured text for knowledge graph construction." },
      { name: "Relationship Extraction", slug: "relationship-extraction", category: "data",
        description: "Identify and classify semantic relationships between entities from text to build knowledge graph edges." }
    ]
  },
  {
    slug: "rag-reranker",
    name: "RAG Reranker",
    agent_type: "data_analyst",
    description: "Scores and reranks RAG search results by semantic relevance to the query.",
    temperature: 0.0,
    max_tokens: 200,
    skill_definitions: [
      { name: "Search Result Reranking", slug: "search-result-reranking", category: "data",
        description: "Score and rerank RAG search results by semantic relevance, factual alignment, and query coverage." }
    ]
  },
  {
    slug: "rag-query-engine",
    name: "RAG Query Engine",
    agent_type: "data_analyst",
    description: "Reformulates search queries and synthesizes answers from retrieved documents using agentic RAG.",
    temperature: 0.3,
    max_tokens: 2048,
    skill_definitions: [
      { name: "Query Reformulation", slug: "query-reformulation", category: "data",
        description: "Reformulate and expand search queries to improve retrieval recall in RAG pipelines." },
      { name: "Answer Synthesis", slug: "answer-synthesis", category: "data",
        description: "Synthesize coherent, grounded answers from multiple retrieved documents using retrieval-augmented generation." }
    ]
  },
  {
    slug: "intent-classifier",
    name: "Intent Classifier",
    agent_type: "assistant",
    description: "Classifies user message intent for team conversation routing (approve, change, discussion).",
    temperature: 0.0,
    max_tokens: 20,
    skill_definitions: [
      { name: "Intent Classification", slug: "intent-classification", category: "customer_support",
        description: "Classify user message intent for conversation routing (approve, reject, change request, discussion, question)." }
    ]
  },
  {
    slug: "semantic-tool-scorer",
    name: "Semantic Tool Scorer",
    agent_type: "assistant",
    description: "Scores tool relevance for semantic tool discovery and ranking.",
    temperature: 0.0,
    max_tokens: 200,
    skill_definitions: [
      { name: "Tool Relevance Scoring", slug: "tool-relevance-scoring", category: "skill_management",
        description: "Score and rank tool relevance for semantic discovery by matching task descriptions to tool capabilities." }
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
      }
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
