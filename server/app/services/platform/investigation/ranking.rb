# frozen_string_literal: true

module Platform
  # Reopened, not declared: `Platform::Investigation` is the ActiveRecord
  # class in app/models. Zeitwerk resolves the namespace from that file
  # before loading this child, so `class` here is a reopen and `module`
  # would be a TypeError.
  class Investigation
    # HYPOTHESIS RANKING (design §5.3) — the LLM half of an investigation.
    #
    # `InvestigationService` assembles the evidence synchronously and stops.
    # This is what the worker's `PlatformInvestigationJob` reaches through the
    # internal door: it asks the component's owning canonical agent to read the
    # assembled evidence and propose ordered candidate causes, and hands them
    # back for `conclude!` to SCORE.
    #
    # ── THE AGENT ORDERS; CORE SCORES ───────────────────────────────────────
    # The prompt deliberately does NOT ask for a confidence number. An agent
    # asked for one returns one, and it is a number with no rule behind it that
    # an operator could check — which is exactly the defect
    # `Platform::Investigation::Confidence` exists to fix one layer up. What is
    # asked for is a cause, the evidence CLASSES that support it, a relative
    # score, and optionally an action category. Any `confidence` key the model
    # volunteers is discarded by `conclude!`.
    #
    # ── NO AGENT IS A VALID ANSWER, GARBAGE IS NOT ──────────────────────────
    # Two failure shapes that must not be collapsed:
    #
    #   - **No canonical agent resolves.** That is core mode, or a platform
    #     whose agents are not seeded. Nothing is wrong and nothing will change
    #     on a retry, so the investigation concludes on the deterministic
    #     candidates core derived itself. It gets a worse answer, not no answer.
    #
    #   - **An agent answered and its answer was unusable.** Something IS wrong
    #     — a provider outage, a model returning prose, a truncated response —
    #     and it may well succeed on a retry. So the investigation stays OPEN,
    #     the reason is recorded on the row, and the caller is told it failed so
    #     the job can raise and Sidekiq can retry. Concluding here would burn
    #     the one open investigation this component is allowed on a result we
    #     know is empty.
    module Ranking
      PROMPT_SLUG = "platform-investigation-ranking"

      # Ranked candidates are capped, because the ranking is a reading for a
      # person: an operator handed twenty hypotheses has been handed none.
      MAX_CANDIDATES = 5

      # Evidence is truncated before it reaches a prompt. An investigation of a
      # component with a long event history can assemble far more than a
      # context window, and a silently truncated prompt produces a confident
      # answer about the half that fit.
      MAX_EVIDENCE_CHARS = 12_000

      FALLBACK_PROMPT = <<~PROMPT
        You are diagnosing one failing component of an infrastructure control plane.

        Component: {{ component_kind }} / {{ component_ref }}

        Here is every piece of evidence the platform assembled around the failure,
        as JSON. Classes present with empty values were checked and found nothing;
        anything under "errors" could not be checked at all.

        {{ evidence }}

        Propose at most #{MAX_CANDIDATES} candidate root causes, most likely first.

        Reply with JSON only, no prose and no code fence:

        {"hypotheses":[{"cause":"one sentence","evidence_classes":["conditions","status_events"],"score":0.0,"recommended_action_category":null}]}

        Rules:
        - "evidence_classes" must name only keys that appear in the evidence above.
          Do not name a class you did not actually use.
        - "score" is a RELATIVE weight among your own candidates. Do not report a
          confidence or a probability; the platform computes those itself from a
          rule you are not being asked to apply.
        - "recommended_action_category" is a remediation signal kind if one is
          obviously indicated, otherwise null. Do not invent one to fill the field.
        - If the evidence does not support any candidate, reply {"hypotheses":[]}.
      PROMPT

      class << self
        include ::Ai::Concerns::PromptTemplateLookup

        # @return [Hash] one of
        #   `{ranked: [..], agent: <Ai::Agent>}` — an agent answered
        #   `{ranked: nil, agent: nil}`          — no agent to ask; conclude deterministically
        #   `{error: "..."}`                     — an agent answered unusably; stay open
        def run!(investigation, account: nil)
          agent = agent_for(investigation, account)
          return { ranked: nil, agent: nil } if agent.nil?

          output = invoke(agent, investigation, account)
          return { error: output[:error] } if output[:error].present?

          ranked = parse(output[:text])
          return { error: "ranker returned no usable hypotheses" } if ranked.nil?

          { ranked: ranked, agent: agent }
        end

        # The contributor's own `owner_agent_slug`, defaulting to the
        # Infrastructure Generalist — resolved through
        # `InvestigationService#owner_agent_slug_for` so there is ONE answer to
        # "who owns this kind", not a second copy here.
        #
        # `resolve_for` honours the override model: an account with its own
        # agent of that slug gets it, otherwise the global canonical.
        def agent_for(investigation, account)
          slug = ::Platform::InvestigationService
                   .new(account: account)
                   .owner_agent_slug_for(investigation.component_kind)

          ::Ai::Agent.resolve_for(investigation.account_id, slug: slug)
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] agent resolution failed: #{e.class}: #{e.message}")
          nil
        end

        private

        def invoke(agent, investigation, account)
          prompt = build_prompt(investigation, account)
          return { error: "no ranking prompt could be resolved" } if prompt.blank?

          result = ::Ai::McpAgentExecutor.new(agent: agent, account: account).execute("input" => prompt)
          text = result.is_a?(Hash) ? (result[:output] || result[:response] || result["output"]) : nil
          return { error: "ranker returned no output" } if text.blank?

          { text: text.to_s }
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] ranking invocation failed: #{e.class}: #{e.message}")
          { error: "#{e.class}: #{e.message}" }
        end

        def build_prompt(investigation, account)
          resolve_prompt_template(
            PROMPT_SLUG,
            account: account,
            variables: {
              component_kind: investigation.component_kind,
              component_ref: investigation.component_ref,
              evidence: (investigation.evidence || {}).to_json.truncate(MAX_EVIDENCE_CHARS)
            },
            fallback: FALLBACK_PROMPT
          )
        end

        # nil means UNUSABLE — the caller keeps the investigation open. An empty
        # array does NOT: a ranker that read the evidence and found no candidate
        # has answered the question, and that answer concludes the
        # investigation with no hypotheses rather than retrying forever.
        def parse(text)
          payload = extract_json(text)
          return nil unless payload.is_a?(Hash)

          raw = payload["hypotheses"] || payload[:hypotheses]
          return nil unless raw.is_a?(Array)

          raw.filter_map { |item| candidate_from(item) }.first(MAX_CANDIDATES)
        end

        # Models fence JSON, prepend "Here is the JSON:", and append apologies.
        # Taking the first balanced object is more forgiving than demanding a
        # bare document, and still refuses prose that contains none.
        def extract_json(text)
          body = text.to_s.strip
          body = body.sub(/\A```(?:json)?/i, "").sub(/```\z/, "").strip
          start = body.index("{")
          finish = body.rindex("}")
          return nil if start.nil? || finish.nil? || finish < start

          JSON.parse(body[start..finish])
        rescue JSON::ParserError
          nil
        end

        def candidate_from(item)
          return nil unless item.is_a?(Hash)

          cause = (item["cause"] || item[:cause]).to_s.strip
          return nil if cause.blank?

          {
            cause: cause,
            score: (item["score"] || item[:score]).to_f,
            evidence_classes: Array(item["evidence_classes"] || item[:evidence_classes]).map(&:to_s),
            recommended_action_category: (item["recommended_action_category"] ||
                                          item[:recommended_action_category]).presence
          }
        end
      end
    end
  end
end
