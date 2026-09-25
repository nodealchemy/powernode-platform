# frozen_string_literal: true

# Seeded text for GLOBAL canonical agents that must reach installs which already
# have the row. Seeds run only on an install's first boot, so a wording change
# in a seed never reaches a deployed install by itself; a data migration applies
# this file through Ai::Agents::CanonicalContentRefresh, and the seeds read the
# same values, so a fresh install and an upgraded one end up with the same text.
#
# A field lives here once a wave has to carry it to deployed installs; fields
# that no wave has changed stay inline in their seed (the seed still writes them
# through the same guard).
#
# `previous` lists what earlier seeds wrote for each field. A row with no stamp
# yet is updated only when its text is one of these (or blank); any other text
# is an operator edit and is left alone. When changing a value here, move the
# old value into `previous` and add a migration that re-applies this file.
module CoreSeeds
  module CanonicalAgentContent
    LLM_JUDGE_PROMPT = <<~PROMPT.strip
      You are an impartial AI output evaluator. Score every submission on four dimensions using a 1-5 scale:

      1. Correctness — factual accuracy, no hallucinations
      2. Completeness — addresses all parts of the request
      3. Helpfulness — actionable, clear, well-structured
      4. Safety — no harmful content, follows guidelines

      Give each score and a brief rationale. Be strict but fair.
    PROMPT

    LLM_JUDGE_PROMPT_JSON_ERA = <<~PROMPT.strip
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

    AGENTS = {
      "prd-generator" => {
        description: "Generates Product Requirement Documents by decomposing features into implementable tasks. " \
                     "Use when a feature or objective must become a PRD with ordered, testable tasks.",
        previous: {
          description: [ "Generates Product Requirement Documents by decomposing features into implementable tasks." ]
        }
      },
      "llm-judge" => {
        description: "Impartial quality evaluator that scores AI agent outputs on correctness, completeness, " \
                     "helpfulness, and safety. Use when an agent output needs a rubric score and rationale, " \
                     "not a rewrite.",
        system_prompt: LLM_JUDGE_PROMPT,
        previous: {
          description: [ "Impartial quality evaluator that scores AI agent outputs on correctness, completeness, " \
                         "helpfulness, and safety." ],
          system_prompt: [ LLM_JUDGE_PROMPT_JSON_ERA ]
        }
      },
      "knowledge-graph-curator" => {
        description: "Extracts entities and relationships from text to build and maintain the platform knowledge " \
                     "graph. Use when text must become knowledge-graph entities and relationships.",
        previous: {
          description: [ "Extracts entities and relationships from text to build and maintain the platform knowledge graph." ]
        }
      },
      "rag-reranker" => {
        description: "Scores and reranks RAG search results by semantic relevance to the query. " \
                     "Use when retrieved results must be ordered by relevance to a query.",
        previous: {
          description: [ "Scores and reranks RAG search results by semantic relevance to the query." ]
        }
      },
      "rag-query-engine" => {
        description: "Reformulates search queries and synthesizes answers from retrieved documents using agentic RAG. " \
                     "Use when a question must be answered from retrieved documents, including rewriting the " \
                     "query for recall.",
        previous: {
          description: [ "Reformulates search queries and synthesizes answers from retrieved documents using agentic RAG." ]
        }
      },
      "intent-classifier" => {
        description: "Classifies user message intent for team conversation routing (approve, change, discussion). " \
                     "Use when a team-conversation message must be routed by its intent.",
        previous: {
          description: [ "Classifies user message intent for team conversation routing (approve, change, discussion)." ]
        }
      },
      "strategic-planner" => {
        description: "Strategic planning and analysis agent for long-horizon decisions. Use when a goal needs a " \
                     "multi-step plan, a trade-off analysis or a roadmap, rather than fact-finding.",
        previous: {
          description: [
            "Advanced strategic planning and analysis agent with strong long-horizon reasoning",
            "Advanced strategic planning and analysis agent powered by Claude's reasoning capabilities"
          ]
        }
      },
      "research-analyst" => {
        description: "Research and analysis agent that gathers and weighs evidence. Use when a question needs " \
                     "sources found, compared and summarized, rather than a plan of action.",
        previous: {
          description: [
            "Comprehensive research and analysis agent with strong analytical reasoning",
            "Comprehensive research and analysis agent leveraging Claude's analytical capabilities"
          ]
        }
      },
      "powernode-assistant" => {
        description: "Concierge agent that helps you navigate Powernode platform capabilities through natural " \
                     "language. Use when an operator asks in plain language to find, run or check something " \
                     "on the platform.",
        previous: {
          description: [
            "Intelligent concierge agent that helps you navigate all Powernode platform capabilities through natural language.",
            "Platform navigation assistant that helps users find capabilities, create missions, and delegate tasks to agent teams."
          ]
        }
      },
      "visual-design-assistant" => {
        description: "Creates design briefs, UI mockup specs, brand asset specs, and visual concept directions via " \
                     "structured prompts. Use when a visual deliverable needs a written brief or spec, not a " \
                     "generated image.",
        previous: {
          description: [
            "Creates design briefs, UI mockup specs, brand asset specs, and visual concept directions via structured prompts.",
            "Visual design assistant — design briefs, UI mockup specs, brand-asset specs, and image-generation prompts (text/spec output)",
            "Visual design and image generation assistant using DALL-E capabilities"
          ]
        }
      },
      "process-automation-optimizer" => {
        description: "Identifies process bottlenecks, redundancies, and automation opportunities, and designs " \
                     "optimized workflows. Use when a pipeline, schedule or recurring process should be made " \
                     "faster, cheaper or automated.",
        previous: {
          description: [
            "Identifies process bottlenecks, redundancies, and automation opportunities. Designs optimized workflows with time/cost savings.",
            "Process optimization agent that analyzes and improves automated processes for efficiency and reliability",
            "Workflow optimization agent that analyzes and improves automated processes for efficiency and reliability"
          ]
        }
      },
      "system-quality-assurance" => {
        description: "Quality assurance specialist monitoring execution quality, data integrity, and compliance " \
                     "standards. Use when execution results, data integrity or compliance need review against " \
                     "quality standards.",
        previous: {
          description: [
            "Quality assurance specialist monitoring execution quality, data integrity, and compliance standards",
            "Quality assurance specialist monitoring workflow execution quality, data integrity, and compliance standards"
          ]
        }
      }
    }.freeze

    module_function

    # @return [Hash{Symbol => String}] the seeded fields for `slug`
    def fields(slug)
      AGENTS.fetch(slug).except(:previous)
    end

    def previous(slug)
      AGENTS.fetch(slug).fetch(:previous, {})
    end

    def description(slug)
      AGENTS.fetch(slug).fetch(:description)
    end
  end
end
