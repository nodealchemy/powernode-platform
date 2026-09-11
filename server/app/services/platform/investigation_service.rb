# frozen_string_literal: true

module Platform
  # THE INVESTIGATION (design §5.3) — evidence assembly, then ranking.
  #
  # ── IT EXTENDS THE CORRELATOR, IT DOES NOT FORK IT ──────────────────────
  # `Ai::SelfHealing::CrossSystemCorrelator` already assembles AI failures and
  # DevOps events, matches them temporally AND causally (an event that happened
  # AFTER the failure is not a candidate cause), and returns ranked correlations
  # with a suggested cause. Re-implementing that here would give the platform
  # two definitions of "these two things are related" that drift apart within a
  # release. So this subclasses it and ADDS the classes the correlator has no
  # reason to know about:
  #
  #   conditions_at_start · dependency_chain · status_events ·
  #   correlations (the parent's own work) · learnings ·
  #   whatever the EvidenceSources seam offers (module changes, remediation
  #   history — both extension-owned)
  #
  # ── ASSEMBLY IS SYNCHRONOUS, RANKING IS NOT ─────────────────────────────
  # `assemble_evidence` is pure reading and safe anywhere. Ranking calls a
  # canonical agent through the gated skill path, which is an LLM call: it
  # belongs in a worker job (`PlatformInvestigationJob`) and NEVER in a request
  # thread. `open!` therefore records the evidence and returns; the job
  # concludes. An investigation that is `open` with evidence and no hypotheses
  # is not a bug — it is one waiting for the worker.
  #
  # ── BOUNDS ──────────────────────────────────────────────────────────────
  # Two, and both are checked before any work: the open-fingerprint rule (one
  # open investigation per component, enforced by a partial unique index) and a
  # per-account daily cap (`platform.investigation.daily_cap`, default 20). The
  # cap exists because the automatic triggers are attached to failure — the
  # exact condition under which a platform generates events fastest — and an
  # unbounded investigator would answer a fleet-wide outage by starting an
  # investigation per component and calling an LLM for each.
  class InvestigationService < ::Ai::SelfHealing::CrossSystemCorrelator
    DAILY_CAP_SETTING = "platform.investigation.daily_cap"
    DEFAULT_DAILY_CAP = 20

    # How far back evidence is gathered. One hour matches the correlator's own
    # default time range, so the parent's correlations and this class's events
    # describe the same window rather than two overlapping ones.
    DEFAULT_WINDOW = 1.hour

    # Every evidence class core assembles itself. Named so the confidence rule
    # can count CLASSES rather than items, and so a class that produced nothing
    # is visibly empty rather than absent.
    CORE_EVIDENCE_CLASSES = %w[conditions dependency_chain status_events correlations learnings].freeze

    # Refusal reasons, returned rather than raised: a trigger that fires into a
    # cap must be able to say so without an exception in a sweep.
    REFUSED_ALREADY_OPEN = "AlreadyOpen"
    REFUSED_DAILY_CAP    = "DailyCapReached"
    REFUSED_NO_COMPONENT = "NoSuchComponent"

    # The canonical agent that ranks hypotheses when the contributor names
    # none. A SLUG, not a class: core resolves it at run time and finds nothing
    # in core mode, which is the correct answer there — an investigation still
    # concludes on its deterministic candidates, it just does not get an
    # agent's reading of them.
    DEFAULT_OWNER_AGENT_SLUG = "infrastructure-generalist"

    class << self
      def daily_cap
        configured = ::SiteSetting.get(DAILY_CAP_SETTING)
        configured.present? && configured.to_i.positive? ? configured.to_i : DEFAULT_DAILY_CAP
      end

      # @return [Hash] `{investigation:, opened: true}` or `{refused: <reason>}`
      def open!(component_status, trigger:, account: nil, now: Time.current)
        new(account: account || component_status&.account).open!(component_status, trigger: trigger, now: now)
      end
    end

    def initialize(account:)
      super
      @account = account
    end

    def open!(component_status, trigger:, now: Time.current)
      return { refused: REFUSED_NO_COMPONENT } if component_status.blank?

      fingerprint = ::Platform::Investigation.fingerprint_for(
        component_kind: component_status.component_kind,
        component_ref: component_status.component_ref
      )

      return { refused: REFUSED_ALREADY_OPEN } if already_open?(fingerprint)
      return { refused: REFUSED_DAILY_CAP } if daily_cap_reached?(now)

      investigation = build(component_status, trigger: trigger, now: now)
      investigation.evidence = assemble_evidence(component_status, now: now)
      investigation.save!

      enqueue_ranking(investigation)

      { investigation: investigation, opened: true }
    rescue ActiveRecord::RecordNotUnique
      # The index won the race. That is the index doing its job, not an error:
      # two triggers fired in the same second and exactly one investigation
      # exists, which is the guarantee.
      { refused: REFUSED_ALREADY_OPEN }
    end

    # PURE READING. Every class is present in the result even when empty, so a
    # class that found nothing is distinguishable from a class that did not run
    # — the difference the confidence rule turns into a discount.
    def assemble_evidence(component_status, now: Time.current, window: DEFAULT_WINDOW)
      rows = neighbourhood_rows(component_status)

      base = {
        "assembled_at" => now.iso8601,
        "window_seconds" => window.to_i,
        "conditions" => Array(component_status.conditions),
        "dependency_chain" => dependency_chain(component_status, rows),
        "status_events" => status_events(component_status, now: now, window: window),
        "correlations" => safe_correlations(window),
        "learnings" => learnings_for(component_status)
      }

      external = ::Platform::Investigation::EvidenceSources.collect(
        component_kind: component_status.component_kind,
        component_ref: component_status.component_ref,
        account: @account, window: window
      )

      base.merge(external[:collected]).merge("errors" => external[:errors])
    end

    # The classes that actually carry something. This — not the item count — is
    # what the confidence rule discounts by.
    def self.evidence_classes(evidence)
      return [] unless evidence.is_a?(Hash)

      evidence.filter_map do |key, value|
        next if %w[assembled_at window_seconds errors].include?(key.to_s)
        next if value.blank?

        key.to_s
      end
    end

    # CONCLUDE. `ranked` is the hypothesis list an agent produced, or nil to
    # conclude on the deterministic candidates core assembled itself.
    #
    # THE CONFIDENCE NUMBER IS APPLIED HERE, NOT ACCEPTED FROM THE RANKER. An
    # agent asked for a confidence would return one, and it would be a number
    # with no rule behind it that an operator could check. The ranker orders
    # and explains; Platform::Investigation::Confidence scores. One rule, one
    # place, both arms assertable.
    def conclude!(investigation, ranked: nil, conclusion: nil, agent: nil, now: Time.current)
      return investigation if investigation.blank? || investigation.concluded?

      # `nil` and `[]` ARE DIFFERENT ANSWERS, and `.presence` cannot tell them
      # apart. `nil` means no ranking was supplied — nobody looked — so core
      # derives its own candidates. `[]` means a ranker DID look and found
      # none, which is a finding: deriving candidates over the top of it would
      # overrule the only thing that actually read the evidence, and would make
      # "the agent found nothing" indistinguishable from "no agent ran". Same
      # distinction the confidence rule draws between a measured zero and
      # `not_measured`, one level up.
      candidates = ranked.nil? ? deterministic_candidates(investigation) : Array(ranked)
      scores = ::Platform::Investigation::Confidence.for_each(candidates)

      investigation.hypotheses = candidates.each_with_index.map do |candidate, index|
        hypothesis_for(candidate, scores[index])
      end
      investigation.conclusion = conclusion.presence || summarize(investigation)
      investigation.agent = agent if agent
      investigation.status = ::Platform::Investigation::STATUS_COMPLETED
      investigation.completed_at = now
      investigation.save!

      record_learning(investigation)
      offer_remediation(investigation)

      investigation
    end

    # The slug of the agent that should rank this component's hypotheses: the
    # contributor's own `owner_agent_slug` when it declares one, otherwise the
    # default. Resolved through the registry so core learns no kind's owner.
    def owner_agent_slug_for(component_kind)
      contributor = ::Platform::Status::Registry.fetch(component_kind)
      contributor.try(:owner_agent_slug).presence || DEFAULT_OWNER_AGENT_SLUG
    rescue StandardError
      DEFAULT_OWNER_AGENT_SLUG
    end

    private

    # What core can say without an agent: one candidate per failing condition,
    # scored by how much of the evidence names its reason token, and carrying
    # the evidence CLASSES that mention it. Deliberately dull — its job is to
    # be a floor under the agent, not a rival to it.
    def deterministic_candidates(investigation)
      evidence = investigation.evidence || {}
      classes = self.class.evidence_classes(evidence)

      failing = Array(evidence["conditions"]).select do |condition|
        condition.is_a?(Hash) && ::Platform::Status::Condition.verdict_for(condition)
          .in?(::Platform::ComponentStatus::UNHEALTHY_VERDICTS)
      end

      failing.map do |condition|
        reason = (condition["reason"] || condition[:reason]).to_s
        {
          cause: "#{condition['type']}: #{reason}",
          reason: reason,
          score: 1.0,
          evidence_classes: classes_mentioning(evidence, reason, classes),
          recommended_action_category: nil
        }
      end
    end

    # A class counts for a candidate when its serialized content names the
    # reason token. Crude on purpose and stated as such: it is a keyword match,
    # not an inference, and it is the reason the confidence rule discounts a
    # single class so hard.
    def classes_mentioning(evidence, reason, classes)
      return [] if reason.blank?

      mentioning = classes.select do |name|
        name == "conditions" || evidence[name].to_json.include?(reason)
      end
      mentioning.presence || [ "conditions" ]
    end

    def hypothesis_for(candidate, score)
      source = candidate.respond_to?(:transform_keys) ? candidate.transform_keys(&:to_s) : {}

      {
        "cause" => source["cause"].to_s,
        "evidence_refs" => Array(source["evidence_classes"]).map(&:to_s),
        "confidence" => score[:value],
        "confidence_state" => score[:state],
        "confidence_detail" => score.transform_keys(&:to_s),
        "recommended_action_category" => source["recommended_action_category"],
        "runbook" => source["runbook"]
      }
    end

    def summarize(investigation)
      top = investigation.hypotheses.first
      return "No candidate cause could be derived from the assembled evidence." if top.blank?

      state = top["confidence_state"]
      if state == ::Platform::Investigation::Confidence::NOT_MEASURED
        "Most likely: #{top['cause']}. Confidence is not measured — the evidence set was empty."
      else
        "Most likely: #{top['cause']} (confidence #{top['confidence']})."
      end
    end

    # Through the EXISTING extractor seam, never a second learning writer.
    def record_learning(investigation)
      return if @account.blank?
      return if investigation.conclusion.blank?

      # An explicit hash, not keywords: `store_learning` takes a positional
      # learning_data hash, and Ruby 3 does not convert keywords into one.
      ::Ai::Learning::CompoundLearningService.new(account: @account).store_learning(
        {
          content: "#{investigation.component_kind} #{investigation.component_ref}: #{investigation.conclusion}",
          category: "failure_mode",
          source: "platform_investigation"
        }
      )
    rescue StandardError => e
      Rails.logger.error("[Platform::Investigation] learning write failed: #{e.class}: #{e.message}")
    end

    # OFFER, never act. The router reports what a lane says; core constructs no
    # proceed, and an investigation is a reading, not an authority.
    def offer_remediation(investigation)
      signal_kind = investigation.top_hypothesis&.dig("recommended_action_category")
      return nil if signal_kind.blank?

      component = ::Platform::ComponentStatus.find_by(
        account_id: investigation.account_id,
        component_kind: investigation.component_kind,
        component_ref: investigation.component_ref
      )
      return nil if component.blank?

      ::Platform::RemediationRouter.route(component, signal_kind: signal_kind)
    rescue StandardError => e
      Rails.logger.error("[Platform::Investigation] remediation offer failed: #{e.class}: #{e.message}")
      nil
    end

    # THE SECOND HALF OF AN INVESTIGATION, and it belongs HERE rather than in
    # each door.
    #
    # `open!` records the evidence; ranking is an LLM call and runs in the
    # worker. Nothing enqueued that job for an entire increment, so all three
    # doors -- the MCP verb, the REST button and the automatic emitter --
    # opened investigations that nothing ever concluded. Because the
    # open-fingerprint index only releases when a row LEAVES `open`, "one open
    # investigation per component" silently became one investigation per
    # component, ever.
    #
    # One enqueue for all three doors, for the same reason the bounds live
    # here: a door that has to remember to enqueue is a door that can forget,
    # and the one that forgets is invisible until somebody opens the drawer.
    #
    # AFTER `save!`, never before: the job carries only the id, so a job that
    # raced its own row would look up nothing and fail for a reason naming
    # none of this.
    #
    # A FAILED ENQUEUE DOES NOT UNDO THE INVESTIGATION. The evidence is the
    # part that decays -- it describes the failure at the moment it happened --
    # so an investigation with evidence and no ranking is worth strictly more
    # than no investigation at all. It is logged loudly instead.
    def enqueue_ranking(investigation)
      ::WorkerJobService.enqueue_job(
        "PlatformInvestigationJob",
        args: [ { "investigation_id" => investigation.id } ],
        queue: "ai_orchestration"
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Platform::Investigation] ranking enqueue failed for " \
        "#{investigation.id}: #{e.class}: #{e.message}"
      )
      nil
    end

    def already_open?(fingerprint)
      ::Platform::Investigation.where(account_id: @account&.id, fingerprint: fingerprint)
                               .open_investigations.exists?
    end

    def daily_cap_reached?(now)
      ::Platform::Investigation.where(account_id: @account&.id)
                               .since(now - 1.day)
                               .count >= self.class.daily_cap
    end

    # WHOSE INVESTIGATION IS THIS (A9 review S1).
    #
    # An ACCOUNT-SCOPED component's investigation always belongs to that
    # component's account — never re-homed, even if a caller passes a
    # different account, so no door can file one tenant's investigation under
    # another's id.
    #
    # A SHARED (NULL-account) component has no tenant, so the investigation
    # belongs to whoever OPENED it. This previously wrote the component's nil,
    # which put every operator-opened investigation of a shared component into
    # one bucket all tenants share: the daily cap (counted by `account_id`)
    # was charged to that shared bucket, bypassing the caller's own cap; every
    # tenant listed every other tenant's investigation; and the
    # open-fingerprint rule, keyed on the same nil, let one tenant's open row
    # refuse every other tenant with AlreadyOpen indefinitely.
    #
    # With no opener (`@account` nil — the automatic trigger on a shared
    # component), it stays shared: there is no tenant to charge or to own it.
    def owning_account_id(component_status)
      component_status.account_id || @account&.id
    end

    def build(component_status, trigger:, now:)
      ::Platform::Investigation.new(
        account_id: owning_account_id(component_status),
        component_kind: component_status.component_kind,
        component_ref: component_status.component_ref,
        trigger: trigger.to_s,
        status: ::Platform::Investigation::STATUS_OPEN,
        started_at: now
      )
    end

    # The component's declared dependencies, resolved to rows so the chain
    # carries VERDICTS rather than bare references — "it depends on X" is not
    # evidence; "it depends on X and X is down" is.
    def dependency_chain(component_status, rows)
      index = rows.index_by { |row| [ row.component_kind, row.component_ref ] }

      Array(component_status.dependencies).filter_map do |edge|
        next unless edge.is_a?(Hash)

        kind = (edge["kind"] || edge[:kind]).to_s
        ref  = (edge["ref"] || edge[:ref]).to_s
        neighbour = index[[ kind, ref ]]

        {
          "kind" => kind, "ref" => ref,
          "relation" => (edge["relation"] || edge[:relation]).to_s.presence,
          "verdict" => neighbour&.verdict,
          "resolved" => !neighbour.nil?
        }.compact
      end
    end

    # THE NEIGHBOURHOOD IS THE READER'S, NOT THE COMPONENT'S (A9 review S5).
    #
    # This keyed on `component_status.account_id`, which is nil for a SHARED
    # component, so `[nil, nil].uniq` collapsed to `[nil]` and the dependency
    # walk saw only other shared rows. Every dependent living in a real account
    # was invisible: the chain reported `resolved: false` for a neighbour the
    # reader can see perfectly well, and the confidence rule then discounted an
    # evidence class that should have carried a `down` verdict. A4's controller
    # documents fixing the identical defect on its own impact walk
    # (`ComponentStatusesController#neighbourhood_rows`); this is the same fix.
    #
    # The set is the one the reader may legally see: the opener's account, the
    # component's own account, and the shared rows. For an account-scoped
    # component those are the same account. For a shared component opened by a
    # tenant they are that tenant plus shared. With no opener (an automatic
    # trigger on a shared component) it is shared rows only — there is no
    # reader whose rows could be included.
    #
    # Keyed on the reader explicitly rather than by passing an account in:
    # the review's own probe showed that handing the reader's account to a
    # method that still keyed on the component changed nothing.
    def neighbourhood_rows(component_status)
      accounts = [ @account&.id, component_status.account_id ].compact.uniq
      ::Platform::ComponentStatus.where(account_id: accounts + [ nil ]).to_a
    rescue StandardError => e
      Rails.logger.error("[Platform::Investigation] neighbourhood load failed: #{e.class}: #{e.message}")
      []
    end

    def status_events(component_status, now:, window:)
      ::Platform::StatusEvent
        .for_component(component_status.component_kind, component_status.component_ref)
        .where(occurred_at: (now - window)..now)
        .recent_first
        .limit(50)
        .map do |event|
          {
            "kind" => event.kind, "from" => event.from_verdict, "to" => event.to_verdict,
            "occurred_at" => event.occurred_at&.iso8601
          }
        end
    rescue StandardError => e
      Rails.logger.error("[Platform::Investigation] status events failed: #{e.class}: #{e.message}")
      []
    end

    # The parent class's own work. Rescued because it reaches into several
    # DevOps tables and an investigation must not die because one of them is
    # unavailable — the missing class is recorded by its emptiness.
    def safe_correlations(window)
      correlate_failures(time_range: window)
    rescue StandardError => e
      Rails.logger.error("[Platform::Investigation] correlation failed: #{e.class}: #{e.message}")
      []
    end

    # The recall surface, not a re-implementation of it: whatever
    # CompoundLearningService returns for a query naming this component.
    def learnings_for(component_status)
      return [] if @account.blank?

      query = "#{component_status.component_kind} #{component_status.display_name} #{reason_tokens(component_status).join(' ')}"
      result = ::Ai::Learning::CompoundLearningService.new(account: @account)
                                                      .search_learnings(query: query, limit: 5)

      Array(result[:learnings]).map do |learning|
        { "id" => learning.id, "title" => learning.try(:title), "category" => learning.try(:category) }
      end
    rescue StandardError => e
      Rails.logger.error("[Platform::Investigation] learning recall failed: #{e.class}: #{e.message}")
      []
    end

    def reason_tokens(component_status)
      Array(component_status.conditions).filter_map do |condition|
        next unless condition.is_a?(Hash)

        condition["reason"] || condition[:reason]
      end.uniq
    end
  end
end
