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
    # ── THREE OUTCOMES, AND WHICH ONES END THE INVESTIGATION ────────────────
    # `run!` answers one of three ways. What separates them is whether trying
    # again could change the answer.
    #
    #   - **Ranked.** An agent read the evidence and ordered candidates.
    #
    #   - **Terminal: conclude on core's candidates and say why.** No retry
    #     changes the answer. Either no principal can act for this
    #     investigation (core mode, an unseeded platform, a shared
    #     investigation with no tenant), or the security gate refused the
    #     spend. Leaving such an investigation open would block every future
    #     investigation of the component forever (A6 review F4). So it
    #     concludes on the deterministic candidates with the refusal recorded.
    #
    #   - **Retryable: stay open, but only within the job's budget.** A
    #     provider failure or a prose answer may succeed on the next attempt,
    #     so the investigation stays open and the job retries. The attempt that
    #     reaches `MAX_RANKING_ATTEMPTS` is the job's last, and `record_outcome!`
    #     turns ANY failure on it terminal (A6 review F4, G2-2). After it
    #     nothing retries, so an open row would promise a retry that never
    #     comes while refusing every new investigation of the component.
    #
    # Every outcome without an agent's ranking is written to
    # `evidence["ranking"]` as `{state, reason, message, retryable, attempts,
    # recorded_at}`. The drawer renders it, and `conclude!` folds its message
    # into the conclusion.
    #
    # ── AUTOMATIC SPEND NEEDS A GRANT (A6 re-verification G1) ───────────────
    # The executor's security gate treats an execution's `user_id` as a person
    # having initiated the call, which waives the capability matrix's
    # `requires_approval`. So the only user this ever attaches is the person
    # who opened the investigation (`opened_by_user`). An investigation that an
    # automatic trigger opened has none, and `run!` refuses it BEFORE the gate,
    # at every tier, as `AutomaticSpendNeedsGrant`. The gate alone was not
    # enough: the A6 re-review found that at the seeded `monitored` tier the
    # matrix allows `execute`, and the automatic call went out with no ledger
    # row. Until A6b gives machine spend an agent-attributed ledger row, no
    # automatic investigation spends at all.
    #
    # ── NO LEDGER ROW, NO CALL ────────────────────────────────────────────────
    # The provider is called only with a persisted `Ai::AgentExecution` in
    # hand (`create_execution`). If the row cannot be written, the attempt
    # fails as `LedgerUnavailable` and the provider is never called.
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

      # How many attempts the worker job makes: one run plus `retry: 2` in
      # `PlatformInvestigationJob`. The attempt that reaches this count is the
      # job's last, so any failure on it concludes, whatever its reason (G2-2).
      # If the job's retry count changes, this must change with it.
      MAX_RANKING_ATTEMPTS = 3

      STATE_NOT_RUN = "not_run"
      STATE_REFUSED = "refused"
      STATE_FAILED  = "failed"

      REASON_AUTOMATIC_SPEND_NEEDS_GRANT = "AutomaticSpendNeedsGrant"
      REASON_SECURITY_GATE_REFUSED       = "SecurityGateRefused"
      REASON_RANKER_UNUSABLE             = "RankerUnusable"
      REASON_PROVIDER_ERROR              = "ProviderError"
      REASON_NO_PRINCIPAL                = "NoPrincipal"
      REASON_LEDGER_UNAVAILABLE          = "LedgerUnavailable"

      # The executor's refusal types. It returns these instead of raising, and
      # both are decisions the platform made about THIS input with THIS agent,
      # so a retry sends the same input to the same gate.
      REFUSAL_TYPES = %w[SecurityGateViolation GuardrailViolation].freeze

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
        #   `{ranked: [..], agent: <Ai::Agent>}`         an agent ranked it
        #   `{ranked: nil, agent: nil, ranking: {..}}`  terminal: conclude on core's candidates
        #   `{error: "..", reason: ".."}`                retryable: see `record_outcome!`
        def run!(investigation, account: nil)
          return no_principal(account) if account.nil?
          # Before any clone is minted or any gate consulted: automatic spend
          # is refused at every tier (see the header), whatever the matrix says.
          return automatic_spend_refused(investigation) if investigation.opened_by_user_id.nil?

          agent = agent_for(investigation, account)
          return no_principal(account) if agent.nil?

          output = invoke(agent, investigation, account)
          return output if output.key?(:ranking) || output[:error].present?

          ranked = parse(output[:text])
          return { error: "ranker returned no usable hypotheses", reason: REASON_RANKER_UNUSABLE } if ranked.nil?

          { ranked: ranked, agent: agent }
        end

        # WRITE DOWN WHAT RANKING CONCLUDED, and decide whether the
        # investigation stays open. The one writer of `evidence["ranking"]`.
        #
        # `attempts` counts every call that did not end in an agent's ranking,
        # so any failure turns terminal on the job's last attempt
        # (`MAX_RANKING_ATTEMPTS`). An agent's ranking clears the record:
        # the hypotheses speak for themselves, and a stale "failed" left beside
        # them would contradict them.
        #
        # @return [Hash, nil] the record now stored, or nil when an agent ranked it
        def record_outcome!(investigation, outcome, now: Time.current)
          evidence = investigation.evidence.is_a?(Hash) ? investigation.evidence.deep_dup : {}
          attempts = investigation.ranking_record.to_h["attempts"].to_i + 1

          record = if outcome.key?(:ranking) then outcome[:ranking]
                   elsif outcome[:error].present? then failure_record(outcome, attempts)
                   end

          return nil if record.nil? && !evidence.key?("ranking")

          if record.nil?
            evidence.delete("ranking")
          else
            evidence["ranking"] = record.merge("attempts" => attempts, "recorded_at" => now.utc.iso8601)
          end
          investigation.update_columns(evidence: evidence, updated_at: now)
          evidence["ranking"]
        end

        # THE REASON A GATE REFUSAL IS RECORDED UNDER. Public because the
        # legacy rewrite maps old stored messages through this same rule
        # instead of a copy of it.
        #
        # Read from the gate's own answer, never re-derived: the gate is the
        # one place that decides, and a copy of its matrix here would be a
        # rival answer. The anomaly precheck is where the capability matrix
        # speaks, and "requires approval" is its approval-required branch
        # (`AgentAnomalyDetectionService#evaluate_trust_gate`). With no opener,
        # no person's consent could have satisfied it.
        def refusal_reason(investigation, blocked_by:, message:)
          automatic = investigation.opened_by_user_id.nil? &&
                      blocked_by.to_s == "anomaly_precheck" &&
                      message.to_s.include?("requires approval")
          automatic ? REASON_AUTOMATIC_SPEND_NEEDS_GRANT : REASON_SECURITY_GATE_REFUSED
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

        def failure_record(outcome, attempts)
          reason = outcome[:reason] || REASON_PROVIDER_ERROR
          exhausted = attempts >= MAX_RANKING_ATTEMPTS
          message = exhausted ? exhausted_message(reason, attempts, outcome[:error]) : outcome[:error].to_s.truncate(500)

          { "state" => STATE_FAILED, "reason" => reason, "message" => message, "retryable" => !exhausted }
        end

        def exhausted_message(reason, attempts, error)
          last = "last error: #{error.to_s.truncate(300)}"
          what = case reason
                 when REASON_RANKER_UNUSABLE
                   "the ranker returned no usable hypotheses in #{attempts} attempts"
                 when REASON_LEDGER_UNAVAILABLE
                   "the spend ledger could not be written on any of the #{attempts} attempts the worker makes (#{last})"
                 else
                   "the provider failed on all #{attempts} attempts the worker makes (#{last})"
                 end
          "Ranking failed: #{what}, so the investigation concluded on the platform's own candidates."
        end

        def no_principal(account)
          detail = if account.nil?
                     "a shared investigation belongs to no tenant, so no agent can act for it"
                   else
                     "no agent can act for this component in this account"
                   end
          terminal(STATE_NOT_RUN, REASON_NO_PRINCIPAL, "Ranking was not run: #{detail}.")
        end

        # An investigation the MCP verb opened (A6 H1) is automatic too: no
        # person asked for it. The message says who opened it, and where a
        # ranked diagnosis can come from.
        def automatic_spend_refused(investigation = nil)
          opener = if investigation&.opened_by_agent_id then "An agent"
                   elsif investigation&.opened_via_mcp? then "An MCP client"
                   else "An automatic trigger"
                   end
          terminal(STATE_NOT_RUN, REASON_AUTOMATIC_SPEND_NEEDS_GRANT,
                   "Ranking was not run because automatic spend needs an agent-scoped grant. #{opener} " \
                     "opened this investigation, and no automatic spend is allowed at any trust tier " \
                     "until that spend can be attributed to an agent on the ledger. For a ranked " \
                     "diagnosis, open an investigation from the status page.")
        end

        def terminal(state, reason, message)
          { ranked: nil, agent: nil,
            ranking: { "state" => state, "reason" => reason,
                       "message" => message.to_s.truncate(500), "retryable" => false } }
        end

        def invoke(agent, investigation, account)
          prompt = build_prompt(investigation, account)
          return { error: "no ranking prompt could be resolved", reason: REASON_RANKER_UNUSABLE } if prompt.blank?

          # An `Ai::AgentExecution` FIRST, and handed to the executor, so the
          # provider spend lands in the ledger. Without it the executor's own
          # `record_security_telemetry` books `@execution&.cost_usd || 0.0` —
          # money spent against no budget and no row, which sits badly beside
          # this verb's own justification for gating at `ai.autonomy.manage`
          # ("it spends money").
          execution, refused = create_execution(agent, investigation, account)
          return refused if refused

          result = ::Ai::McpAgentExecutor
                     .new(agent: agent, execution: execution, account: account)
                     .execute("input" => prompt)

          text = extract_text(result)
          if text.blank?
            failure = classify_failure(result, investigation)
            finish_execution(execution, investigation, status: "failed",
                                                       error_message: failure[:error] || failure.dig(:ranking, "message"))
            return failure
          end

          # Booked BEFORE the row closes (F7), so the close sees the cost.
          booked = book_usage(execution, result)
          finish_execution(execution, investigation, status: "completed", booked: booked)
          { text: text }
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] ranking invocation failed: #{e.class}: #{e.message}")
          message = "#{e.class}: #{e.message}"
          # A row opened for this call is closed as failed, never left pending.
          finish_execution(execution, investigation, status: "failed", error_message: message) if execution
          { error: message, reason: REASON_PROVIDER_ERROR }
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

        # A BLOCK IS NOT AN EMPTY ANSWER, AND A REFUSAL IS NOT AN OUTAGE.
        #
        # The executor returns `{"error" => {...}}` instead of raising when a
        # security gate or a guardrail refuses, and when the provider call
        # itself fails. Reporting a refusal as "no output" would send an
        # operator to the provider for a decision the platform made. Treating
        # it as retryable would retry the same input against the same gate.
        # A provider failure and a blank answer are retryable within
        # `MAX_RANKING_ATTEMPTS`. A refusal is terminal at once.
        def classify_failure(result, investigation)
          error = result.is_a?(Hash) ? result["error"] : nil
          message = error.is_a?(Hash) ? error["message"].presence : nil
          return { error: "ranker returned no output", reason: REASON_RANKER_UNUSABLE } if message.nil?
          return { error: message, reason: REASON_PROVIDER_ERROR } unless REFUSAL_TYPES.include?(error["type"])

          if refusal_reason(investigation, blocked_by: error["blocked_by"], message: message) ==
             REASON_AUTOMATIC_SPEND_NEEDS_GRANT
            terminal(STATE_NOT_RUN, REASON_AUTOMATIC_SPEND_NEEDS_GRANT,
                     "Ranking was not run because automatic spend needs an agent-scoped grant. " \
                       "An automatic trigger opened this investigation, and the security gate answered: #{message}")
          else
            terminal(STATE_REFUSED, REASON_SECURITY_GATE_REFUSED, "Ranking was refused: #{message}")
          end
        end

        # THE USER ON THE LEDGER ROW IS THE PERSON WHO ACTED, OR NOBODY
        # (A6 re-verification G1).
        #
        # This used to be `agent.creator || account.users.first`, "the honest
        # owner of the spend". But the field has two readers. The ledger reads
        # it as who pays. The executor's security gate reads it as who
        # CONSENTED: `evaluate_trust_gate` allows any call whose `user_id` is
        # present. A value defensible for the first is a forgery for the
        # second, and every automatic investigation passed a gate that refuses
        # the identical call without it.
        #
        # So the user is `investigation.opened_by_user` and nothing else. An
        # automatic investigation, which has none, is refused by `run!` before
        # it gets here; the nil check below is the same rule held a second time.
        #
        # @return [Array] `[row, nil]` when the call may go ahead, or
        #   `[nil, outcome]` when it may not. NO ROW, NO CALL: a row that cannot
        #   be written stops the call instead of letting it run unrecorded, which
        #   is what this used to do.
        def create_execution(agent, investigation, account)
          user = investigation.opened_by_user
          return [ nil, automatic_spend_refused(investigation) ] if user.nil?

          provider = agent.try(:resolved_provider) || agent.try(:provider)
          if provider.nil?
            return [ nil, terminal(STATE_NOT_RUN, REASON_NO_PRINCIPAL,
                                   "Ranking was not run: the agent has no provider in this account to run on.") ]
          end

          row = ::Ai::AgentExecution.create!(
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
          [ row, nil ]
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] execution record failed: #{e.class}: #{e.message}")
          [ nil, { error: "the spend ledger could not be written (#{e.class}: #{e.message})",
                   reason: REASON_LEDGER_UNAVAILABLE } ]
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
        #
        # `investigation.cost_usd` stays nil unless a cost was actually booked
        # and priced (F7). The execution's column defaults to 0.0, and copying
        # that default made every investigation report that it cost nothing,
        # including the ones nobody measured. An unpriced model gets nil,
        # meaning unknown, not $0.00.
        def finish_execution(execution, investigation, status:, error_message: nil, booked: false)
          return if execution.nil?

          attrs = { status: status, completed_at: Time.current }
          attrs[:error_message] = error_message.to_s.truncate(1000) if status == "failed"
          execution.update!(attrs)
          cost = execution.reload.cost_usd
          return unless booked && cost.to_f.positive?

          # ACCUMULATED ACROSS ATTEMPTS (A6 re-review). This used to overwrite,
          # so an investigation that paid for three attempts showed the cost of
          # the last one. The total is read fresh, because each attempt is a
          # separate request holding its own copy of the row.
          total = (investigation.class.where(id: investigation.id).pick(:cost_usd) || 0) + cost
          investigation.update_columns(cost_usd: total, updated_at: Time.current)
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] execution close failed: #{e.class}: #{e.message}")
        end

        # BOOK THE TOKENS THE PROVIDER REPORTED (A6 review F7).
        #
        # Nothing else does this. The executor reads `@execution.cost_usd` for
        # its telemetry but never writes it, so every ranking execution closed
        # at the column default. The prompt/completion split and the model that
        # answered go into `output_data` first, because that is where
        # `AgentExecution#calculate_cost` reads them. `record_token_usage!`
        # then prices the call and, through the model's own callback, debits
        # the agent's budget.
        #
        # @return [Boolean] whether usage was booked
        def book_usage(execution, result)
          return false if execution.nil?

          metadata = result.is_a?(Hash) ? result.dig("result", "metadata") : nil
          return false unless metadata.is_a?(Hash)

          tokens = metadata["tokens_used"].to_i
          return false unless tokens.positive?

          breakdown = metadata.slice("prompt_tokens", "completion_tokens", "model_used").compact
          execution.update!(output_data: (execution.output_data || {}).merge(breakdown)) if breakdown.any?
          execution.record_token_usage!(tokens)
          true
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] usage booking failed: #{e.class}: #{e.message}")
          false
        end

        def build_prompt(investigation, account)
          resolve_prompt_template(
            PROMPT_SLUG,
            account: account,
            variables: {
              component_kind: investigation.component_kind,
              component_ref: investigation.component_ref,
              # The ranking record is about earlier attempts, not the component,
              # and the prompt tells the ranker to cite only keys it can see.
              evidence: (investigation.evidence || {}).except("ranking", ::Platform::Investigation::OPENED_VIA_MCP_KEY).to_json.truncate(MAX_EVIDENCE_CHARS)
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
