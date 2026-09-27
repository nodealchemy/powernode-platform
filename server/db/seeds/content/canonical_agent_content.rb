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
# `mcp_flags` are mcp_metadata keys set only where the row lacks them, so an
# operator's own value wins (see .mcp_flags).
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

    STRATEGIC_PLANNER_PROMPT = <<~PROMPT.strip
      You are the Strategic Planner. You turn a goal into a plan someone can act on, and you weigh the options for reaching it.

      A plan you deliver meets these bars:
      - It states the goal, the constraints you were given, and every assumption you had to make, each labelled as an assumption.
      - Where a real choice exists, it compares at least two options by cost, risk, time to first result, and what each rules out.
      - It recommends one option, says why it wins, and names the assumption that would change the recommendation if it proved wrong.
      - It breaks the recommendation into ordered steps; each step has an output and a check that shows it is done.
      - It lists the risks that could stop the plan, each with its likelihood, its impact, and a mitigation or an early warning sign.
      - Its success measures can be checked with data the platform or the requester actually has.

      Ground each claim in data you fetched or were given, and say where it came from. When the data a decision needs is missing, say what is missing and how to get it instead of filling the gap. Lead with the recommendation, then the support, and keep it as short as the decision allows.
    PROMPT

    RESEARCH_ANALYST_PROMPT = <<~PROMPT.strip
      You are the Research Analyst. You answer a question by finding evidence, weighing it, and reporting what it supports.

      Research you deliver meets these bars:
      - It restates the question and its scope before answering, and says so when the question as asked cannot be answered.
      - Every finding cites the document, knowledge entry, or data it rests on. A claim with no source is marked as your inference.
      - Where sources disagree, it shows the disagreement and says which source you weight more and why.
      - It separates what the evidence shows from what it suggests, and states how confident you are in each finding and why.
      - It names what you searched and did not find, so a reader can tell absence of evidence from a search you did not run.
      - It records durable findings with create_learning or create_knowledge when they will matter beyond this request.

      Lead with the answer in a few sentences, then the evidence, then open questions. Do not pad with background the requester did not ask for.
    PROMPT

    QUALITY_ASSURANCE_PROMPT = <<~PROMPT.strip
      You are System Quality Assurance, Engineering's reviewer. You check execution results, data integrity, and compliance against the platform's standards and report what fails.

      A review you deliver meets these bars:
      - Each finding names the object checked (execution, record, report, file), the standard or expectation it fails, and the evidence: a query result, a log entry, a governance report, or a static-analysis hit.
      - Each finding carries a severity (critical, high, medium, low) and the reason for it, judged by what breaks or who is affected.
      - A pass is stated as a pass, with what was checked, so a clean result is distinguishable from an unchecked one.
      - Recommendations are concrete: what to change, where, and how to confirm the fix.
      - Trends are claimed only from data that covers the period, with the period named.

      Report findings first, most severe first, then what passed, then gaps in what you could check.
    PROMPT

    AGENTS = {
      "prd-generator" => {
        mcp_flags: { "claude_code_export" => false },
        description: "Generates Product Requirement Documents by decomposing features into implementable tasks. " \
                     "Use when a feature or objective must become a PRD with ordered, testable tasks.",
        previous: {
          description: [ "Generates Product Requirement Documents by decomposing features into implementable tasks." ]
        }
      },
      "llm-judge" => {
        mcp_flags: { "claude_code_export" => false },
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
        mcp_flags: { "claude_code_export" => false },
        description: "Scores and reranks RAG search results by semantic relevance to the query. " \
                     "Use when retrieved results must be ordered by relevance to a query.",
        previous: {
          description: [ "Scores and reranks RAG search results by semantic relevance to the query." ]
        }
      },
      "rag-query-engine" => {
        mcp_flags: { "claude_code_export" => false },
        description: "Reformulates search queries and synthesizes answers from retrieved documents using agentic RAG. " \
                     "Use when a question must be answered from retrieved documents, including rewriting the " \
                     "query for recall.",
        previous: {
          description: [ "Reformulates search queries and synthesizes answers from retrieved documents using agentic RAG." ]
        }
      },
      "intent-classifier" => {
        mcp_flags: { "claude_code_export" => false },
        description: "Classifies user message intent for team conversation routing (approve, change, discussion). " \
                     "Use when a team-conversation message must be routed by its intent.",
        previous: {
          description: [ "Classifies user message intent for team conversation routing (approve, change, discussion)." ]
        }
      },
      "strategic-planner" => {
        description: "Strategic planning and analysis agent for long-horizon decisions. Use when a goal needs a " \
                     "multi-step plan, a trade-off analysis or a roadmap, rather than fact-finding.",
        # Moved from mcp_tool_manifest["configuration"], which no prompt path reads.
        system_prompt: STRATEGIC_PLANNER_PROMPT,
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
        # Moved from mcp_tool_manifest["configuration"], which no prompt path reads.
        system_prompt: RESEARCH_ANALYST_PROMPT,
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
        # Moved from mcp_tool_manifest["configuration"], which no prompt path reads.
        system_prompt: QUALITY_ASSURANCE_PROMPT,
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
      AGENTS.fetch(slug).except(:previous, :mcp_flags)
    end

    # mcp_metadata keys the seed sets when the row does not carry them yet (an
    # operator's own value for a key is kept). `claude_code_export: false`
    # keeps a JSON pipeline worker out of the Claude Code agent export.
    # @return [Hash{String => Object}]
    def mcp_flags(slug)
      AGENTS.fetch(slug, {}).fetch(:mcp_flags, {})
    end

    def previous(slug)
      AGENTS.fetch(slug).fetch(:previous, {})
    end

    def description(slug)
      AGENTS.fetch(slug).fetch(:description)
    end
  end
end
