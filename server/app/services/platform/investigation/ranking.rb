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

        # WHICH `Ai::Agent` ROW ACTUALLY ACTS (HIER-P2I).
        #
        # Two steps, and the second is the one that was missing. The
        # contributor's own `owner_agent_slug` names the canonical — resolved
        # through `InvestigationService#owner_agent_slug_for` so there is ONE
        # answer to "who owns this kind". `Ai::Agent.resolve_for` then returns
        # the account's own row for that slug IF it has one, and otherwise the
        # GLOBAL canonical (account_id NULL), which is the normal case because
        # canonicals are seeded global.
        #
        # A global canonical is a TEMPLATE, not a principal. `Ai::Tools::BaseTool`
        # refuses one by name, so a ranker whose prompt needs a lookup gets
        # nothing back and answers from the prompt alone; and the executor does
        # not refuse it, so the call would proceed with a principal that has no
        # account and therefore no account role bounding it.
        #
        # `Ai::Agents::AccountPrincipalResolver` is THE resolver of "which row
        # acts for canonical X in account Y", and its own header says not to
        # write a second copy. `acting` passes an account-scoped row through
        # untouched and swaps a canonical for the account's clone, minting it
        # on first use.
        #
        # A SHARED investigation (NULL account) has no tenant, so there is no
        # account principal to mint and none is invented: it returns nil and
        # the investigation concludes on core's deterministic candidates. That
        # is the honest answer — falling back to the global canonical here
        # would be the exact bypass this method exists to close.
        def agent_for(investigation, account)
          return nil if account.nil?

          slug = ::Platform::InvestigationService
                   .new(account: account)
                   .owner_agent_slug_for(investigation.component_kind)

          resolved = ::Ai::Agent.resolve_for(investigation.account_id, slug: slug)
          return nil if resolved.nil?

          ::Ai::Agents::AccountPrincipalResolver.acting(resolved, account: account)
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] agent resolution failed: #{e.class}: #{e.message}")
          nil
        end

        private

        def invoke(agent, investigation, account)
          prompt = build_prompt(investigation, account)
          return { error: "no ranking prompt could be resolved" } if prompt.blank?

          # An `Ai::AgentExecution` FIRST, and handed to the executor, so the
          # provider spend lands in the ledger. Without it the executor's own
          # `record_security_telemetry` books `@execution&.cost_usd || 0.0` —
          # money spent against no budget and no row, which sits badly beside
          # this verb's own justification for gating at `ai.autonomy.manage`
          # ("it spends money").
          execution = create_execution(agent, investigation, account)

          result = ::Ai::McpAgentExecutor
                     .new(agent: agent, execution: execution, account: account)
                     .execute("input" => prompt)

          text = extract_text(result)
          if text.blank?
            reason = executor_error(result)
            finish_execution(execution, investigation, status: "failed", error_message: reason)
            return { error: reason }
          end

          finish_execution(execution, investigation, status: "completed")
          { text: text }
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] ranking invocation failed: #{e.class}: #{e.message}")
          { error: "#{e.class}: #{e.message}" }
        end

        # THE EXECUTOR'S REAL RETURN SHAPE, verified by running it rather than
        # by reading its name.
        #
        # `McpAgentExecutor#execute` ends at `format_mcp_response`, which NESTS
        # the provider result: `{"result" => {"output" => …, "metadata" => …},
        # "tool_id" => …, "execution_id" => …, "telemetry" => …}`. The text is
        # at `["result"]["output"]`.
        #
        # This previously read `result[:output] || result[:response] ||
        # result["output"]` — three keys the executor never returns, so every
        # successful LLM call was reported as "ranker returned no output" and
        # every investigation stayed open forever. The same wrong read exists at
        # `Ai::DevopsBridge::CodeReviewAgent#execute_agent`, which is where the
        # pattern was copied from; that is a second instance of the bug, not a
        # precedent for it, and it is filed as an offer.
        def extract_text(result)
          return nil unless result.is_a?(Hash)

          result.dig("result", "output").presence&.to_s
        end

        # A BLOCK IS NOT AN EMPTY ANSWER. The executor returns `{"error" => {…}}`
        # rather than raising when a security gate or a guardrail refuses, and
        # reporting that as "no output" would send an operator looking at the
        # provider for a refusal the platform itself issued.
        def executor_error(result)
          message = result.is_a?(Hash) ? result.dig("error", "message") : nil
          message.presence || "ranker returned no output"
        end

        # `Ai::AgentExecution` requires a user and a provider, and an
        # investigation is started by a system trigger as often as by a person.
        # The agent's creator is the honest owner of the spend — it is who the
        # account made responsible for that agent — with the account's first
        # user as the fallback, the same resolution `Ai::Tools::AgentAsToolAdapter`
        # already uses for a tool-initiated run. No user and no provider means
        # no ledger row rather than a fabricated one.
        def create_execution(agent, investigation, account)
          user = agent.try(:creator) || account.users.first
          provider = agent.try(:resolved_provider) || agent.try(:provider)
          return nil if user.nil? || provider.nil?

          ::Ai::AgentExecution.create!(
            agent: agent,
            account: account,
            provider: provider,
            user: user,
            execution_id: UUID7.generate,
            status: "pending",
            input_parameters: {
              invocation_type: "platform_investigation",
              investigation_id: investigation.id,
              component_kind: investigation.component_kind,
              component_ref: investigation.component_ref
            },
            execution_context: { source: "platform_investigation", priority: "normal" }
          )
        rescue StandardError => e
          # A ledger that cannot be written must not stop the diagnosis. The
          # executor tolerates a nil execution; the cost simply goes unrecorded,
          # and it is logged rather than silently dropped.
          Rails.logger.error("[Platform::Investigation] execution record failed: #{e.class}: #{e.message}")
          nil
        end

        # Close the ledger row and copy the spend onto the investigation, which
        # is where design §5.3 puts it and where an operator reading one
        # investigation can see what it cost.
        # `Ai::AgentExecution` validates that a FAILED row carries an
        # `error_message`, which is the right rule: a failed execution with no
        # reason is a ledger entry nobody can act on. The reason passed here is
        # the executor's own — a gate's refusal in the gate's words, or the
        # ranker's unusable answer — so the ledger and the investigation's
        # recorded error say the same thing.
        def finish_execution(execution, investigation, status:, error_message: nil)
          return if execution.nil?

          attrs = { status: status, completed_at: Time.current }
          attrs[:error_message] = error_message.to_s.truncate(1000) if status == "failed"
          execution.update!(attrs)
          cost = execution.reload.cost_usd
          investigation.update_columns(cost_usd: cost, updated_at: Time.current) if cost.present?
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] execution close failed: #{e.class}: #{e.message}")
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
