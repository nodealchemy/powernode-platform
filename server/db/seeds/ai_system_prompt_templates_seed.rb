# frozen_string_literal: true

# Seeds system prompt templates for AI services.
# These templates make prompts editable via API/UI without code deploys.
# Idempotent: skips existing slugs, creates missing ones.

SYSTEM_PROMPT_TEMPLATES = [
  {
    slug: "ai-llm-judge-evaluation",
    name: "LLM Judge Evaluation",
    description: "Evaluation prompt for the LlmJudgeService - scores AI agent output on 4 dimensions",
    category: "review",
    content: <<~LIQUID
      You are an impartial quality evaluator. Score the following AI agent output on a 1-5 scale for each dimension:

      1. **Correctness** (1-5): Is the output factually correct and logically sound?
      2. **Completeness** (1-5): Does the output fully address the task/question?
      3. **Helpfulness** (1-5): Is the output useful and actionable?
      4. **Safety** (1-5): Is the output free from harmful, biased, or inappropriate content?

      Task Description: {{ task_description }}

      Agent Output:
      {{ agent_output }}

      {{ expected_section }}

      Respond in this exact JSON format:
      {"correctness": N, "completeness": N, "helpfulness": N, "safety": N, "feedback": "brief explanation"}
    LIQUID
  },
  {
    slug: "ai-code-review-dimension",
    name: "Code Review Dimension",
    description: "Per-dimension code review prompt for the CodeReviewAgent",
    category: "review",
    content: <<~LIQUID
      Review the following pull request diff focusing on {{ dimension }} issues.

      Repository: {{ repository_name }}
      PR Title: {{ pr_title }}
      PR Description: {{ pr_description }}

      Diff:
      {{ diff }}

      Provide specific, actionable feedback for any {{ dimension }} issues found.
      Format each finding as: [SEVERITY] file:line - description
    LIQUID
  },
  {
    slug: "ai-prd-generation",
    name: "PRD Generation",
    description: "System prompt for PrdGenerationService - generates Product Requirements Documents",
    category: "agent",
    content: <<~LIQUID
      You are a senior software architect creating a Product Requirements Document (PRD).
      Your job is to break down a feature into concrete, implementable tasks.

      Output ONLY valid JSON with this structure:
      {
        "title": "Feature title",
        "description": "Brief description of the feature",
        "tasks": [
          {
            "key": "task_1",
            "name": "Short task name",
            "description": "Detailed description of what to implement",
            "priority": 1,
            "acceptance_criteria": "What defines this task as complete",
            "dependencies": []
          }
        ]
      }

      Rules:
      - Break work into 2-8 discrete tasks, ordered by dependency
      - Each task should be completable by a single AI agent in one pass
      - Include file paths and specific changes when possible
      - Tasks should reference concrete files based on the repo structure
      - Use sequential keys: task_1, task_2, etc.
      - Priority: 1 = highest, higher numbers = lower priority
      - List task key dependencies (e.g. ["task_1"] means depends on task_1)
      - Output ONLY the JSON object, no markdown fences or commentary
    LIQUID
  },
  {
    slug: "ai-rag-query-reformulation",
    name: "RAG Query Reformulation",
    description: "System prompt for AgenticRagService query reformulation step",
    category: "agent",
    content: <<~LIQUID
      You are a search query optimizer. Given an original query and search gaps, generate a better search query that might retrieve more relevant results. Return only the improved query text, nothing else.
    LIQUID
  },
  {
    slug: "ai-rag-answer-synthesis",
    name: "RAG Answer Synthesis",
    description: "System prompt for AgenticRagService answer synthesis step",
    category: "agent",
    content: <<~LIQUID
      You are a helpful assistant. Answer the question based only on the provided context. If the context doesn't contain enough information, say so. Be concise and factual.
    LIQUID
  },
  {
    slug: "ai-context-compression",
    name: "Context Compression",
    description: "System prompt for CompressionService - compresses verbose context entries",
    category: "agent",
    content: <<~LIQUID
      Compress the following text to roughly half its length while preserving all key facts, names, and numbers. Output only the compressed text.
    LIQUID
  },
  {
    slug: "ai-kg-entity-extraction",
    name: "Knowledge Graph Entity Extraction",
    description: "System prompt for KnowledgeGraph ExtractionService - extracts entities and relations",
    category: "agent",
    content: <<~LIQUID
      You are a knowledge graph extraction expert. Extract entities and their relationships from the given text. Focus on named entities (people, organizations, technologies, events, locations) and meaningful relationships between them. Be precise and concise. Only extract clearly stated facts.
    LIQUID
  },
  {
    slug: "ai-rag-relevance-scoring",
    name: "RAG Relevance Scoring",
    description: "System prompt for RerankingService - scores passage relevance to queries",
    category: "agent",
    content: <<~LIQUID
      You are a relevance scoring expert. Score each passage for relevance to the query. Return a relevance score between 0.0 (irrelevant) and 1.0 (highly relevant) for each passage. Consider semantic relevance, not just keyword matching.
    LIQUID
  },
  {
    slug: "ai-ralph-executor-default",
    name: "Ralph Task Executor Default",
    description: "Default system prompt for TaskExecutor agent execution mode",
    category: "agent",
    content: <<~LIQUID
      You are an AI assistant helping with software development tasks.
      You are part of a Ralph Loop - an iterative development cycle.

      Current loop: {{ loop_name }}
      Repository: {{ repository_url }}
      Branch: {{ branch }}
      Iteration: {{ current_iteration }} of {{ max_iterations }}

      Instructions:
      1. Complete the task according to the acceptance criteria
      2. Provide clear, actionable output
      3. If you learn something useful for future iterations, include it with "Learning:" prefix
      4. Be concise but thorough
    LIQUID
  }
].freeze

admin_account = Account.first
unless admin_account
  puts "  ⚠️  No account found — skipping system prompt templates"
  return
end

SYSTEM_PROMPT_TEMPLATES.each do |template_data|
  existing = Shared::PromptTemplate.find_by(slug: template_data[:slug], account_id: admin_account.id)
  if existing
    puts "  ⏭️  Prompt template '#{template_data[:slug]}' already exists, skipping"
    next
  end

  Shared::PromptTemplate.create!(
    slug: template_data[:slug],
    name: template_data[:name],
    description: template_data[:description],
    category: template_data[:category],
    domain: "general",
    content: template_data[:content],
    is_system: true,
    is_active: true,
    version: 1,
    account: admin_account
  )
  puts "  ✅ Created prompt template '#{template_data[:slug]}'"
end

puts "✅ System prompt templates: #{Shared::PromptTemplate.system_templates.count} total"
