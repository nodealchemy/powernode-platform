# frozen_string_literal: true

module Ai
  class Mission < ApplicationRecord
    self.table_name = "ai_missions"

    include Auditable

    # ==================== Constants ====================
    MISSION_TYPES = %w[development research operations infrastructure agent_fleet content_production custom].freeze

    STATUSES = %w[draft active paused completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    # ---- Per-project scaling bounds (APO 3a) ----------------------------
    #
    # A mission is the platform's PROJECT. An instance POOL has carried
    # min_size/max_size since it existed; a mission had neither — only a bare
    # `watch_policies.auto_scale_max_replicas` ceiling that the adaptation
    # composer read directly, and NO floor at all, so the actuating scale-in
    # skill clamped every project at one platform-wide constant. This is that
    # missing home, read by both arms of the scale lane:
    #
    #   * the composer's downgrade-only bounds verdict
    #     (Ai::Provisioning::AdaptationProposerService#auto_apply?), which may
    #     clear a scale-OUT for unattended application only INSIDE the window;
    #   * the actuating skill's replica floor, which bounds a scale-IN.
    #
    # Scale-IN is never released by these bounds. Ratified 2026-09-02:
    # destructive removals take an operator approval regardless of policy, and
    # the composer states that as an allowlist of the one additive strategy —
    # so widening a project's window can never reach the removal arm.
    #
    # The `watch_policies` keys a mission declares them under. Both are
    # OPTIONAL: an undeclared bound resolves through the settings ladder below.
    MIN_REPLICAS_POLICY_KEY = "auto_scale_min_replicas"
    MAX_REPLICAS_POLICY_KEY = "auto_scale_max_replicas"

    # DB-driven config, resolved mission `watch_policies` → the mission
    # TEMPLATE's `default_configuration` watch_policies → Account#settings →
    # SiteSetting → the constant below. The template rung is what makes a
    # seeded project shape (e.g. the system_provisioning template) carry a
    # window at all: nothing merges a template's default_configuration into a
    # mission's own configuration, so a bound declared there is only reachable
    # by reading the template directly — the same shape other consumers of a
    # template default already use. The SiteSetting keys let an operator move
    # the platform-wide default without a deploy.
    MIN_REPLICAS_SETTING = "ai.provisioning.auto_scale_min_replicas"
    MAX_REPLICAS_SETTING = "ai.provisioning.auto_scale_max_replicas"

    # Last-resort floor. The platform never scales a project to zero, and this
    # mirrors the actuating skill's own minimum: a project may RAISE its floor,
    # never lower it below this.
    DEFAULT_AUTO_SCALE_MIN_REPLICAS = 1

    # Last-resort ceiling — deliberately a NON-CEILING. Zero means "no ceiling
    # was declared anywhere", and an undeclared ceiling must never license
    # unattended scale-out: that is the fail-closed behaviour the bare
    # `auto_scale_max_replicas` read already had, and resolving a real number
    # here would silently widen unattended actuation for every project that
    # declares nothing. An operator opts in per project, or globally through
    # MAX_REPLICAS_SETTING.
    DEFAULT_AUTO_SCALE_MAX_REPLICAS = 0

    # ---- Per-project utilization ceilings (IMP-7684d3f8658a) ------------
    #
    # The cpu / memory percentages above which a project is UTILIZATION-BOUND
    # and its SLO sensor should say so. They live here, next to the scaling
    # window, for the reason APO-3a moved the window here: a project's declared
    # numbers must have ONE home, or the sensor that fires and the composer
    # that sizes the response end up holding different opinions of the same
    # project.
    #
    # The keys a mission declares them under, inside `configuration
    # ["slo_targets"]` — the hash that already carries availability_pct,
    # p99_latency_ms, cost_ceiling_usd and min_throughput_bytes_per_s.
    MAX_CPU_PCT_SLO_KEY    = "max_cpu_pct"
    MAX_MEMORY_PCT_SLO_KEY = "max_memory_pct"

    # Operator-movable platform defaults, same ladder as the scaling bounds.
    # Setting either one turns the corresponding check on FLEET-WIDE — read
    # DEFAULT_MAX_CPU_PCT below before you do.
    MAX_CPU_PCT_SETTING    = "ai.provisioning.max_cpu_pct"
    MAX_MEMORY_PCT_SETTING = "ai.provisioning.max_memory_pct"

    # Constant fallbacks — the last rung, never a literal at a call site.
    #
    # DECLARED-ONLY, exactly like the SDWAN throughput floor: nil means no
    # ceiling is checked until an operator declares one (on the project, on its
    # template, on the account, or fleet-wide via the SiteSetting above).
    #
    # A shipped default was considered and rejected, because a utilization
    # ceiling is NOT the quiet direction the scaling window's 0 is. A
    # `system.project_slo_violation` on cpu_pct maps to change_type
    # `scale_horizontal`, which System::AdaptationGate seeds `auto_approve`
    # deliberately paired with the watch_policies ceiling — and the seeded
    # `system_provisioning` mission template, which EVERY mission
    # Ai::Tools::ProvisioningTool creates inherits from, declares
    # auto_scale_min_replicas 1 / auto_scale_max_replicas 5. #scaling_bounds
    # therefore reads that window off the TEMPLATE rung and #auto_scale_out? is
    # already true for a project that declared nothing itself. A defaulted
    # ceiling would consequently open an UNATTENDED, money-spending provision
    # path on existing projects the moment this shipped, which is not a default
    # a code change gets to choose. Declaring a ceiling is that decision, made
    # deliberately and per project (or once, fleet-wide, via the SiteSetting).
    DEFAULT_MAX_CPU_PCT    = nil
    DEFAULT_MAX_MEMORY_PCT = nil

    # A resolved target of nil means NO CEILING for that metric: nothing usable
    # was declared, so the metric is not checked at all. See
    # #resolved_utilization_target for why an unusable declaration resolves
    # this way rather than to a wider default.
    UtilizationTargets = Struct.new(:cpu_pct, :memory_pct, keyword_init: true) do
      # Keyed by the CANONICAL METRIC NAME a project metrics sample carries
      # ("cpu_pct" / "memory_pct"), so a reader maps a sample to its ceiling
      # without maintaining a second name table alongside this one.
      def target_for(metric_name)
        case metric_name.to_s
        when "cpu_pct"    then cpu_pct
        when "memory_pct" then memory_pct
        end
      end
    end

    # The resolved window. `max` of 0 means "no ceiling declared" — see
    # DEFAULT_AUTO_SCALE_MAX_REPLICAS — which is why #ceiling_declared? is a
    # named question rather than a `max.positive?` scattered across callers.
    ScalingBounds = Struct.new(:min, :max, keyword_init: true) do
      def ceiling_declared? = max.to_i.positive?

      # A floor ABOVE the ceiling is not a narrower window, it is an empty one.
      # Guessing which half the operator meant is how a bounds check quietly
      # becomes a rubber stamp, so an incoherent declaration clears nothing.
      def coherent? = min.to_i >= 1 && (!ceiling_declared? || max.to_i >= min.to_i)

      # Whether unattended scale-out is eligible AT ALL for this project. Not
      # a decision to apply — the policy gate still has to grant it, and this
      # verdict can only ever narrow what the gate may grant.
      def auto_scale_out? = ceiling_declared? && coherent?

      def permits_replica_count?(count)
        return false unless auto_scale_out?

        count.to_i >= min.to_i && count.to_i <= max.to_i
      end
    end

    # ---- Per-project snapshot schedule (IMP-e025722ef14e, APO-5 remainder) --
    #
    # A project's volumes can be snapshotted and restored (APO-5), but until
    # this reader nothing let a project DECLARE how often, or how many restore
    # points to keep — so no sensor could ask whether one was overdue and no
    # retention could ever prune. Same home and same ladder as the scaling
    # window, for the same reason: the sensor that fires and the applier that
    # acts must read ONE declaration.
    #
    # The `watch_policies` keys a mission declares them under. Both OPTIONAL.
    SNAPSHOT_INTERVAL_HOURS_POLICY_KEY  = "snapshot_interval_hours"
    SNAPSHOT_RETENTION_COUNT_POLICY_KEY = "snapshot_retention_count"

    # Operator-movable platform defaults, same ladder as the scaling bounds
    # (mission watch_policies → template default_configuration → Account
    # #settings → SiteSetting → constant).
    SNAPSHOT_INTERVAL_HOURS_SETTING  = "ai.provisioning.snapshot_interval_hours"
    SNAPSHOT_RETENTION_COUNT_SETTING = "ai.provisioning.snapshot_retention_count"

    # Constant fallbacks — both 0, meaning "not declared anywhere", and both
    # deliberately NOT a working number. A scheduled snapshot is a provider
    # call that costs money on every interval for as long as the project
    # lives, and a retention count DESTROYS restore points once exceeded;
    # neither is a default a code change gets to choose for every project
    # that declared nothing. An operator opts in per project, per template,
    # per account, or fleet-wide through the SiteSettings above.
    DEFAULT_SNAPSHOT_INTERVAL_HOURS  = 0
    DEFAULT_SNAPSHOT_RETENTION_COUNT = 0

    # The resolved policy. `interval_hours` 0 means no schedule; `retention
    # _count` 0 means keep every completed snapshot. Named questions rather
    # than `.positive?` scattered across callers, exactly like ScalingBounds.
    SnapshotPolicy = Struct.new(:interval_hours, :retention_count, keyword_init: true) do
      def scheduled? = interval_hours.to_i.positive?

      def prunes? = retention_count.to_i.positive?
    end

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
    belongs_to :team, class_name: "Ai::AgentTeam", foreign_key: "team_id", optional: true
    belongs_to :conversation, class_name: "Ai::Conversation", foreign_key: "conversation_id", optional: true
    belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract", foreign_key: "risk_contract_id", optional: true
    belongs_to :ralph_loop, class_name: "Ai::RalphLoop", foreign_key: "ralph_loop_id", optional: true
    belongs_to :review_state, class_name: "Ai::CodeFactory::ReviewState", foreign_key: "review_state_id", optional: true
    belongs_to :mission_template, class_name: "Ai::MissionTemplate", foreign_key: "mission_template_id", optional: true

    # APO `app-4-project-noun` — the durable owner this mission is work FOR.
    #
    # OPTIONAL, permanently. Every mission that existed before the project noun
    # has none, and a nil project must not change any behaviour: the bounds and
    # utilization ladders below simply skip the project rung, and every reader
    # here is unchanged. See Ai::Project for why a project is a real model
    # rather than a facade over this one.
    belongs_to :project, class_name: "Ai::Project", foreign_key: "ai_project_id", optional: true, inverse_of: :missions
    # Self-Serve Hardening M4 Slice A — optional per-team isolation pointer.
    # Backed by an extension-provided `Account::TeamDelegation` model. Leading `::` keeps
    # the constant resolved at the top level when that extension is loaded; when the
    # extension is absent, this column stays NULL on every row.
    belongs_to :delegation,
               class_name: "::Account::TeamDelegation",
               foreign_key: "delegation_id",
               inverse_of: :missions,
               optional: true

    has_many :approvals, class_name: "Ai::MissionApproval", foreign_key: "mission_id", dependent: :destroy

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :mission_type, presence: true, inclusion: { in: MISSION_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    # "completed" is a universal terminal sentinel written by
    # OrchestratorService#complete_mission! for every mission type, even when a
    # template's own phase pipeline ends earlier (e.g. reap, adapting). Allow it
    # alongside the template-defined phases so missions can actually finish.
    validates :current_phase, inclusion: { in: ->(m) { m.phases_for_type + %w[completed] } }, allow_nil: true
    validates :deployed_port, numericality: { only_integer: true, greater_than_or_equal_to: 6000, less_than_or_equal_to: 6199 }, allow_nil: true
    validate :repository_required_for_development

    # ==================== Scopes ====================
    scope :active, -> { where(status: "active") }
    scope :draft, -> { where(status: "draft") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :in_progress, -> { where(status: %w[active paused]) }
    scope :development, -> { where(mission_type: "development") }
    scope :research, -> { where(mission_type: "research") }
    scope :operations, -> { where(mission_type: "operations") }
    scope :infrastructure, -> { where(mission_type: "infrastructure") }
    scope :content_production, -> { where(mission_type: "content_production") }
    scope :recent, -> { order(created_at: :desc) }
    scope :with_deployment, -> { where.not(deployed_port: nil) }

    # ==================== Callbacks ====================
    before_validation :set_defaults, on: :create
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    after_save :broadcast_status_update, if: :saved_change_to_status?
    after_save :broadcast_phase_update, if: :saved_change_to_current_phase?
    # M5 conversation unification: provisioning missions tag their associated
    # conversation so the operator UI's chat sidebar can surface them in a
    # dedicated "Provisioning" group alongside agent + workspace conversations.
    after_save :tag_conversation_as_provisioning, if: -> {
      saved_change_to_conversation_id? && conversation_id.present? && mission_type == "infrastructure"
    }
    after_save :post_milestone_to_conversation, if: -> {
      saved_change_to_current_phase? && conversation_id.present?
    }

    # ==================== Instance Methods ====================

    def development?
      mission_type == "development"
    end

    def research?
      mission_type == "research"
    end

    def operations?
      mission_type == "operations"
    end

    def infrastructure?
      mission_type == "infrastructure"
    end

    def content_production?
      mission_type == "content_production"
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def awaiting_approval?
      approval_gate_phases.include?(current_phase)
    end

    def approval_gate_phases
      if custom_phases.present?
        custom_phases.select { |p| p["requires_approval"] }.map { |p| p["key"] }
      elsif mission_template.present?
        mission_template.approval_gate_keys
      else
        []
      end
    end

    def current_gate
      current_phase if awaiting_approval?
    end

    # The blast-radius marker this mission stamps onto everything it creates
    # (F3, IMP 019fe4c4-e813): PlanComposerService threads it into the
    # provisioning step as `name_prefix`, the executor prefixes node names, and
    # instance names derive from those. Explicit `configuration.name_prefix`
    # wins; a dryrun run id derives the charter's prefix; anything else means
    # the mission has no prefix opinion and returns nil.
    #
    # It lives on the mission — not in the composer that first needed it —
    # because it is a property of the mission's own configuration and it is
    # read on BOTH sides of the containment rail: composition stamps it, and
    # a scale-in refuses to terminate a victim that does not carry it. Two
    # private copies of that derivation would let the two sides disagree about
    # what this mission owns, which is precisely the containment failure the
    # marker exists to prevent.
    def provenance_name_prefix
      cfg = configuration
      return nil unless cfg.is_a?(Hash)

      explicit = cfg["name_prefix"].presence
      return explicit if explicit

      run_id = cfg["dryrun_run_id"].presence
      run_id ? "dryrun-#{run_id}" : nil
    end

    # This project's declared scaling window — see the ScalingBounds constants.
    #
    # The floor is clamped UP to DEFAULT_AUTO_SCALE_MIN_REPLICAS: a project may
    # raise its floor, never declare one that permits scaling to zero. The
    # ceiling is taken as declared and is not clamped here — the composer's own
    # per-step delta bound and the actuating skill's ceiling already cap what a
    # single step may reach, and clamping the ceiling here would silently
    # rewrite an operator's number instead of honouring it.
    def scaling_bounds
      ScalingBounds.new(
        min: [ resolved_scale_bound(MIN_REPLICAS_POLICY_KEY, MIN_REPLICAS_SETTING,
                                    DEFAULT_AUTO_SCALE_MIN_REPLICAS),
               DEFAULT_AUTO_SCALE_MIN_REPLICAS ].max,
        max: resolved_scale_bound(MAX_REPLICAS_POLICY_KEY, MAX_REPLICAS_SETTING,
                                  DEFAULT_AUTO_SCALE_MAX_REPLICAS)
      )
    end

    # This project's declared snapshot schedule — see the SnapshotPolicy
    # constants. Walks .resolve_scale_bound, the SAME ladder as a scaling
    # bound and with the same fail-closed reading: presence is decisive, and
    # a non-positive or garbled declaration is 0 ("off here") rather than a
    # fall-through to a wider default that would silently start snapshotting
    # or pruning a project whose operator said not to. Each half resolves
    # independently, so an unreadable interval cannot take retention with it.
    def snapshot_policy
      SnapshotPolicy.new(
        interval_hours: resolved_scale_bound(SNAPSHOT_INTERVAL_HOURS_POLICY_KEY,
                                             SNAPSHOT_INTERVAL_HOURS_SETTING,
                                             DEFAULT_SNAPSHOT_INTERVAL_HOURS),
        retention_count: resolved_scale_bound(SNAPSHOT_RETENTION_COUNT_POLICY_KEY,
                                              SNAPSHOT_RETENTION_COUNT_SETTING,
                                              DEFAULT_SNAPSHOT_RETENTION_COUNT)
      )
    end

    # THE ONE LADDER WALK for every home a scaling window has.
    #
    # Extracted from the instance ladder (IMP-f986d379120a) so the system
    # extension's System::PlatformDeployment#scaling_bounds — the deployment-
    # side twin of #scaling_bounds, read by the platform ReplicaReconciler's
    # scale-out gate — resolves its window through the SAME walk rather than a
    # copy that is free to drift in exactly the direction a bounds ladder must
    # never resolve. `rungs` is an ordered list of [label, lambda] pairs, most
    # specific first; a lambda answers nil (or a blank string) for "this rung
    # does not carry the key". Core knows nothing of the caller: this is a
    # generic reader, not a seam onto any extension.
    #
    # PRESENCE is decisive: the first rung that CARRIES the key answers, even
    # when what it carries is non-positive. A project declaring a zero ceiling
    # is stating "no unattended scale-out here", and falling through to a wider
    # account or global default would silently overrule it — the one direction
    # a bounds ladder must never resolve. A value that is negative or not a
    # number reads the same fail-closed way (0) and is logged, the way
    # Ai::Provisioning::DryrunHarness#config_number logs an ignored one. `nil`
    # and a blank string are the same statement as absent. Any rung that
    # RAISES resolves the whole bound to `default`, logged.
    def self.resolve_scale_bound(rungs, key:, default:)
      rungs.each do |rung, source|
        raw = source.call
        next if raw.nil? || (raw.respond_to?(:to_str) && raw.to_str.strip.empty?)

        value = scale_bound_integer(raw)
        unless value&.positive?
          Rails.logger.warn("[Ai::Mission] #{key}=#{raw.inspect} declared at #{rung}; " \
                            "reading it as 0 (no window declared) rather than inheriting a wider default")
          return 0
        end

        return value
      end
      default
    rescue StandardError => e
      Rails.logger.warn("[Ai::Mission] scaling bound #{key} unresolved (#{e.class}); using #{default}")
      default
    end

    # `.to_i` semantics for anything genuinely numeric (a JSON column can hand
    # back an Integer, a Float or a numeric string), and nil for a value that
    # is not a number at all — which .resolve_scale_bound then reads as an
    # explicit 0 rather than as a silent 0 from `"abc".to_i`.
    def self.scale_bound_integer(raw)
      return raw.to_i if raw.is_a?(Numeric)

      str = raw.to_s.strip
      Integer(str, exception: false) || Float(str, exception: false)&.to_i
    end
    private_class_method :scale_bound_integer

    # The GLOBAL rung of the utilization ladder, resolved once. SiteSetting.get
    # is an uncached `find_by`, and these two keys are per-DEPLOYMENT values,
    # not per-mission ones — so a caller that walks many missions in one pass
    # (System::Fleet::Sensors::ProjectSloSensor, every tick) reads them ONCE
    # here and hands the result to #utilization_targets, instead of paying two
    # SELECTs per mission per tick. Returns a hash keyed by setting key; a
    # missing setting is present with a nil value, so "resolved and unset" is
    # distinguishable from "not supplied".
    def self.global_utilization_settings
      [ MAX_CPU_PCT_SETTING, MAX_MEMORY_PCT_SETTING ].index_with do |key|
        ::Ai::FableRouting.global_setting(key)
      end
    end

    # This project's declared utilization ceilings — see the
    # UtilizationTargets constants. Resolved per metric and INDEPENDENTLY: an
    # unreadable cpu declaration must not take the memory ceiling with it.
    #
    # `global_settings:` is the optional hoist described on
    # .global_utilization_settings. nil (the default) keeps the ladder LAZY, as
    # #scaling_bounds is: a project that answers on its own rung never reads a
    # SiteSetting at all.
    def utilization_targets(global_settings: nil)
      UtilizationTargets.new(
        cpu_pct: resolved_utilization_target(MAX_CPU_PCT_SLO_KEY, MAX_CPU_PCT_SETTING,
                                             DEFAULT_MAX_CPU_PCT, global_settings),
        memory_pct: resolved_utilization_target(MAX_MEMORY_PCT_SLO_KEY, MAX_MEMORY_PCT_SETTING,
                                                DEFAULT_MAX_MEMORY_PCT, global_settings)
      )
    end

    # M4 Enterprise Polish — second-signature gate.
    #
    # Returns true when the mission is sitting at the `handoff` phase AND
    # the account's active plan has `features["second_signature_required"]`
    # set to true. Business+ tiers opt in via the plan seed. Free/Pro tiers
    # return false here so the existing single-approval handoff flow is
    # preserved verbatim.
    #
    # Defensive against missing chain links — if any of account /
    # active_subscription / plan / features is nil or non-hash, returns
    # false (fail-open to existing behavior, never harder than configured).
    def requires_second_signature?
      return false unless current_phase == "handoff"

      features = account&.try(:active_subscription)&.try(:plan)&.try(:features)
      features.is_a?(Hash) && features["second_signature_required"] == true
    end

    # Distinct count of approved approvers at the given gate. Used by the
    # second-signature gate to determine whether the threshold (>= 2 distinct
    # users) has been met. Same user approving twice counts once.
    def distinct_approver_count(gate)
      approvals.approved.where(gate: gate).distinct.pluck(:user_id).compact.length
    end

    # Approval-unification cascade target. Ai::ApprovalRequest#notify_source_of_decision
    # invokes this when a gateway-routed mission gate resolves (see
    # Ai::Approvals::Gateway). Advances the mission on approval, rolls it back on
    # rejection/expiry — but only while the mission is still parked at the gate
    # the request was opened for, which guards against stale or duplicate
    # cascades after the mission has already moved on.
    #
    # Note: request_data["action_type"] holds the GATE name (e.g.
    # "feature_selection") while current_phase holds the PHASE name (e.g.
    # "awaiting_feature_approval"), so we compare via the canonical
    # phase→gate mapping rather than equating them directly.
    def on_approval_decision(request)
      gate = request.request_data["action_type"].presence
      return Ai::ApprovalRequest::DISPATCH_NOOP unless awaiting_approval?

      gate_matches = gate.blank? ||
                     gate == Ai::MissionApproval.gate_for_phase(current_phase, mission: self)
      return Ai::ApprovalRequest::DISPATCH_NOOP unless gate_matches

      orchestrator = Ai::Missions::OrchestratorService.new(mission: self)
      case request.status
      when "approved"
        orchestrator.advance!(result: { approval_request_id: request.id })
      when "rejected", "expired"
        orchestrator.reject_gate!(comment: request.decisions.order(:created_at).last&.comments)
      else
        return Ai::ApprovalRequest::DISPATCH_NOOP
      end

      Ai::ApprovalRequest::DISPATCH_EXECUTED
    end

    # ---- canonical land source seam (Ai::Land, flag-gated default OFF) -----
    # These let a Mission act as a polymorphic land source for the unified
    # Ai::Land::LandService, mirroring the campaign hooks. They are only reached
    # when Ai::Land::Feature.mission_landing_enabled? is on (default false), so
    # by default a mission's merging phase keeps dispatching AiMissionMergeJob
    # and none of this runs.

    # Surface a land issue to the mission's creator (best-effort; never raises).
    def land_park_notify!(reason:, land:)
      Notification.create_for_user(
        created_by,
        type: "mission_land_attention",
        title: "Mission land needs attention",
        message: "Mission **#{name}** land needs attention: #{reason}\n\n" \
                 "`#{land.source_branch}` → `#{land.target_branch}`",
        severity: "warning",
        category: "ai",
        action_url: "/app/ai/missions/#{id}",
        action_label: "Review Mission",
        metadata: { mission_id: id, campaign_land_id: land.id, reason: reason }
      )
    rescue StandardError => e
      Rails.logger.warn("[Ai::Mission] land_park_notify! failed (mission #{id}): #{e.message}")
    end

    # The land merged + post-merge CI passed: advance the mission out of the
    # merging phase to its terminal completion.
    def on_land_completed!(land)
      Ai::Missions::OrchestratorService.new(mission: self)
                                       .advance!(result: { campaign_land_id: land.id })
    end

    # The land's post-merge CI failed and the merge was reverted: roll the
    # mission back to the previewing gate so an operator can re-decide.
    def on_land_rolled_back!(_land)
      Ai::Missions::OrchestratorService.new(mission: self)
                                       .transition_to!("previewing", dispatch: false)
    end

    def phases_for_type
      if custom_phases.present?
        custom_phases.sort_by { |p| p["order"] || 0 }.map { |p| p["key"] }
      elsif mission_template.present?
        mission_template.phase_keys
      else
        []
      end
    end

    def phase_index
      phases_for_type.index(current_phase) || 0
    end

    def phase_progress
      total = phases_for_type.length
      return 0 if total.zero?
      ((phase_index.to_f / (total - 1)) * 100).round
    end

    def mission_summary
      {
        id: id,
        name: name,
        mission_type: mission_type,
        status: status,
        current_phase: current_phase,
        phase_progress: phase_progress,
        repository: repository&.full_name,
        team: team&.name,
        created_by: created_by&.name,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        mission_template_id: mission_template_id,
        phases: phases_for_type,
        approval_gate_phases: approval_gate_phases,
        created_at: created_at.iso8601
      }
    end

    def mission_details
      mission_summary.merge(
        repository_id: repository_id,
        team_id: team_id,
        description: description,
        objective: objective,
        phase_config: phase_config,
        analysis_result: analysis_result,
        feature_suggestions: feature_suggestions,
        selected_feature: selected_feature,
        prd_json: prd_json,
        test_result: test_result,
        review_result: review_result,
        phase_history: phase_history,
        configuration: configuration,
        branch_name: branch_name,
        base_branch: base_branch,
        pr_number: pr_number,
        pr_url: pr_url,
        deployed_port: deployed_port,
        deployed_url: deployed_url,
        error_message: error_message,
        error_details: error_details,
        conversation_id: conversation_id,
        ralph_loop_id: ralph_loop_id,
        risk_contract_id: risk_contract_id,
        review_state_id: review_state_id,
        custom_phases: custom_phases,
        approval_gate_phases: approval_gate_phases,
        approvals: approvals.order(created_at: :desc).map(&:approval_summary)
      )
    end

    def save_as_template!(name: nil, description: nil)
      template_phases = if custom_phases.present?
        custom_phases
      else
        phases_for_type.map.with_index do |phase_key, i|
          {
            "key" => phase_key,
            "label" => phase_key.humanize.titleize,
            "order" => i,
            "requires_approval" => approval_gate_phases.include?(phase_key)
          }
        end
      end

      Ai::MissionTemplate.create!(
        account: account,
        name: name || "Template from: #{self.name}",
        description: description || "Auto-generated from mission #{id}",
        template_type: "account",
        mission_type: mission_type,
        phases: template_phases,
        approval_gates: approval_gate_phases,
        rejection_mappings: build_rejection_mappings,
        default_configuration: configuration
      )
    end

    private

    # One scaling bound, resolved DB-first: this project's own
    # `watch_policies` → its mission TEMPLATE's default_configuration →
    # the account's settings → the global SiteSetting → the constant fallback.
    # Reuses the settings reader Ai::FableRouting and the dry-run harness
    # already share, so operators configure all of them the same way. Each rung
    # is a lambda so a project that answers on the first one never pays for the
    # template load or the SiteSetting read. The walk itself is
    # .resolve_scale_bound — shared with the deployment-side window.
    def resolved_scale_bound(policy_key, setting_key, default)
      self.class.resolve_scale_bound(scale_bound_rungs(policy_key, setting_key),
                                     key: policy_key, default: default)
    end

    # The resolution ladder, most specific first. Lazy on purpose — see
    # #resolved_scale_bound.
    def scale_bound_rungs(policy_key, setting_key)
      [
        [ "the mission's watch_policies", -> { watch_policies_hash[policy_key] } ],
        # APO `app-4-project-noun` — the PROJECT rung. It sits BELOW the
        # mission's own declaration (a mission is the more specific object: one
        # project has many, and a single mission may need a narrower window) and
        # ABOVE the mission TEMPLATE's, because the seeded system_provisioning
        # template declares BOTH bounds. Under the template this rung could
        # never answer for a mission created through the provisioning flow —
        # which is every mission a project owns — and a rung that is
        # unreachable for the priority case is not a rung. A mission with no
        # project skips it and resolves exactly as before.
        [ "the project's watch_policies", -> { project_watch_policies_hash[policy_key] } ],
        [ "the mission template's default_configuration", -> { template_watch_policies_hash[policy_key] } ],
        [ "the account's settings", -> { ::Ai::FableRouting.setting(account, setting_key) } ],
        [ "SiteSetting #{setting_key}", -> { ::Ai::FableRouting.global_setting(setting_key) } ]
      ]
    end

    # One utilization ceiling, resolved on the same DB-first ladder as a
    # scaling bound: this project's `slo_targets` → its mission TEMPLATE's
    # default_configuration → the account's settings → the global SiteSetting →
    # the constant fallback (nil — see DEFAULT_MAX_CPU_PCT: these ceilings are
    # declared-only, so a project nobody declared one for is UNCHECKED, not
    # checked at a shipped number).
    #
    # PRESENCE IS DECISIVE, as it is for a scaling bound — but an unusable
    # declaration resolves to nil (NO ceiling, the metric goes unchecked)
    # rather than to 0. The two fail different ways on purpose: a scaling bound
    # of 0 means "no unattended scale-out", the quiet direction; a utilization
    # ceiling of 0 would mean "breach on every tick", the loudest possible
    # direction, so reading a garbled declaration that way would flood an
    # operator with signals for a number the platform could not parse. Out of
    # range (<= 0 or > 100) is unusable for the same reason: these are
    # percentages of a bounded quantity, and a 140% ceiling can never be
    # crossed, so honouring it silently would disable the check while looking
    # like a declaration.
    def resolved_utilization_target(slo_key, setting_key, default, global_settings = nil)
      utilization_target_rungs(slo_key, setting_key, global_settings).each do |rung, source|
        raw = source.call
        next if raw.nil? || (raw.respond_to?(:to_str) && raw.to_str.strip.empty?)

        value = utilization_percent(raw)
        unless value
          Rails.logger.warn("[Ai::Mission] #{slo_key}=#{raw.inspect} declared at #{rung} is not a " \
                            "usable percentage; reading it as NO ceiling rather than inheriting " \
                            "a wider default")
          return nil
        end

        return value
      end
      default
    rescue StandardError => e
      Rails.logger.warn("[Ai::Mission] utilization target #{slo_key} unresolved (#{e.class}); using #{default}")
      default
    end

    # A percentage in (0, 100], as a Float — or nil for anything else. A JSON
    # column and a SiteSetting both hand values back as Integer, Float or
    # String, so all three are accepted; a non-number is nil, never `"abc"
    # .to_f`'s silent 0.0.
    def utilization_percent(raw)
      value = raw.is_a?(Numeric) ? raw.to_f : Float(raw.to_s.strip, exception: false)
      return nil if value.nil?
      return nil unless value.positive? && value <= 100.0

      value
    end

    # The resolution ladder, most specific first. Lazy, exactly like
    # #scale_bound_rungs — a project that answers on the first rung never pays
    # for the template load or the SiteSetting read.
    def utilization_target_rungs(slo_key, setting_key, global_settings = nil)
      [
        [ "the mission's slo_targets", -> { slo_targets_hash[slo_key] } ],
        # Same rung, same position, same reason as #scale_bound_rungs above: a
        # project's declared ceilings must not be shadowed by the seeded
        # template every provisioning mission inherits from.
        [ "the project's slo_targets", -> { project_slo_targets_hash[slo_key] } ],
        [ "the mission template's default_configuration", -> { template_slo_targets_hash[slo_key] } ],
        [ "the account's settings", -> { ::Ai::FableRouting.setting(account, setting_key) } ],
        [ "SiteSetting #{setting_key}",
          # `key?`, not `[]` — a hoisted hash that resolved the setting to nil
          # must NOT silently re-read it here, or the hoist stops being a hoist
          # for exactly the common case (nothing set) it exists to make cheap.
          lambda do
            if global_settings.is_a?(Hash) && global_settings.key?(setting_key)
              global_settings[setting_key]
            else
              ::Ai::FableRouting.global_setting(setting_key)
            end
          end ]
      ]
    end

    def slo_targets_hash
      extract_slo_targets(configuration)
    end

    # Same reason as #template_watch_policies_hash: nothing merges a template's
    # default_configuration into a mission's own configuration, so a target
    # declared on the seeded project shape is only reachable by reading the
    # template directly.
    def template_slo_targets_hash
      extract_slo_targets(mission_template&.default_configuration)
    end

    # The PROJECT rung's declarations. Ai::Project stores them under the same
    # `watch_policies` / `slo_targets` keys a mission does, so the extractors
    # above serve both rungs and cannot drift apart. Lazy like every other rung:
    # a mission that answers on its own configuration never loads the project.
    def project_watch_policies_hash
      extract_watch_policies(project&.configuration)
    end

    def project_slo_targets_hash
      extract_slo_targets(project&.configuration)
    end

    def extract_slo_targets(cfg)
      return {} unless cfg.is_a?(Hash)

      targets = cfg["slo_targets"] || cfg[:slo_targets]
      targets.is_a?(Hash) ? targets.deep_stringify_keys : {}
    end

    def watch_policies_hash
      extract_watch_policies(configuration)
    end

    # Nothing merges a template's default_configuration into a mission's own
    # configuration (Ai::Mission#set_defaults assigns the template, it does not
    # copy its defaults), so a bound declared on the seeded project shape is
    # only reachable by reading the template directly.
    def template_watch_policies_hash
      extract_watch_policies(mission_template&.default_configuration)
    end

    # Tolerant of a symbol-keyed configuration held in memory, matching the
    # reader this replaced (AdaptationProposerService#watch_policies, which
    # deep_stringify_keys first). A missed floor here would remove MORE
    # replicas, not fewer.
    def extract_watch_policies(cfg)
      return {} unless cfg.is_a?(Hash)

      policies = cfg["watch_policies"] || cfg[:watch_policies]
      policies.is_a?(Hash) ? policies.deep_stringify_keys : {}
    end

    def build_rejection_mappings
      if mission_template.present?
        mission_template.rejection_mappings || {}
      else
        {}
      end
    end

    # Tags the associated conversation as provisioning-typed so the chat
    # sidebar groups it accordingly. Idempotent: safe to call repeatedly,
    # only updates when the type isn't already 'provisioning'.
    def tag_conversation_as_provisioning
      conv = conversation
      return unless conv
      return if conv.conversation_type == "provisioning"
      conv.update_column(:conversation_type, "provisioning")
    end

    def post_milestone_to_conversation
      return unless conversation

      phase = current_phase
      previous_phase = saved_change_to_current_phase&.first

      # Resolve the previous approval gate message if we just left one
      resolve_approval_message(previous_phase) if previous_phase && approval_gate_phases.include?(previous_phase)

      message = if approval_gate_phases.include?(phase)
        "Mission **#{name}** requires **#{phase.humanize}** — review and approve to proceed"
      elsif phase == "completed"
        "Mission **#{name}** completed successfully!"
      else
        "Mission **#{name}** entered **#{phase.humanize}** phase (#{phase_progress}% complete)"
      end

      is_gate = approval_gate_phases.include?(phase)
      metadata = {
        "activity_type" => "mission_#{is_gate ? 'approval_required' : 'phase_changed'}",
        "mission_id" => id,
        "mission_name" => name,
        "phase" => phase,
        "phase_progress" => phase_progress
      }

      # Inline approval affordance — lets the operator approve/reject a
      # provisioning gate directly from the concierge chat (routed via
      # ConciergeService#handle_confirmed_action → OrchestratorService#handle_approval!).
      # Scoped to infrastructure missions so development-mission gates that
      # need richer input (feature selection, PRD edits) keep their modal UX.
      if is_gate && mission_type == "infrastructure"
        metadata.merge!(
          "concierge_action" => true,
          "action_type" => "approve_mission_gate",
          "action_params" => { "mission_id" => id, "gate" => phase, "decision" => "approved" },
          "actions" => [
            { "type" => "confirm", "label" => "Approve", "style" => "primary", "params" => { "decision" => "approved" } },
            { "type" => "reject", "label" => "Reject", "style" => "danger", "params" => { "decision" => "rejected" } }
          ],
          "action_context" => { "type" => "mission_approval", "action_type" => "approve_mission_gate", "status" => "pending" }
        )
      end

      conversation.add_system_message(message, content_metadata: metadata)

      # Push a real-time notification for approval gates
      if approval_gate_phases.include?(phase)
        notify_approval_required(phase.humanize)
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to post mission milestone to conversation: #{e.message}")
    end

    def resolve_approval_message(gate_phase)
      pending_msg = conversation.messages
                                .where(role: "system")
                                .order(created_at: :desc)
                                .find { |m|
                                  m.content_metadata&.dig("activity_type") == "mission_approval_required" &&
                                    m.content_metadata&.dig("mission_id") == id &&
                                    m.content_metadata&.dig("phase") == gate_phase
                                }

      return unless pending_msg

      updated_metadata = pending_msg.content_metadata.deep_dup
      updated_metadata["resolved"] = true
      updated_metadata["resolved_at"] = Time.current.iso8601
      pending_msg.update!(content_metadata: updated_metadata)
    rescue StandardError => e
      Rails.logger.warn("Failed to resolve approval message: #{e.message}")
    end

    def notify_approval_required(gate_label)
      Notification.create_for_user(
        created_by,
        type: "ai_plan_review",
        title: "Mission awaiting #{gate_label}",
        message: "**\"#{name}\"** requires **#{gate_label}** before it can continue.\n\n" \
                 "Review and approve to allow the mission to proceed to the next phase.",
        severity: "warning",
        category: "ai",
        action_url: "/app/ai/missions/#{id}",
        action_label: "Review Mission",
        metadata: { mission_id: id, phase: current_phase }
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to create approval notification: #{e.message}")
    end

    def set_defaults
      self.status ||= "draft"
      self.phase_config ||= {}
      self.analysis_result ||= {}
      self.feature_suggestions ||= []
      self.selected_feature ||= {}
      self.prd_json ||= {}
      self.test_result ||= {}
      self.review_result ||= {}
      self.phase_history ||= []
      self.configuration ||= {}
      self.metadata ||= {}
      self.error_details ||= {}
      self.base_branch = repository&.default_branch || base_branch if !base_branch_changed?
      assign_default_template if mission_template_id.blank? && custom_phases.blank?
    end

    def assign_default_template
      template = Ai::MissionTemplate
        .for_account(account_id)
        .active
        .defaults
        .by_type(mission_type)
        .first
      self.mission_template = template if template
    end

    def repository_required_for_development
      if mission_type == "development" && repository_id.blank?
        errors.add(:repository, "is required for development missions")
      end
    end

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_ms = ((completed_at - started_at) * 1000).to_i
    end

    def broadcast_status_update
      MissionChannel.broadcast_mission_event(id, "status_changed", {
        mission_id: id,
        status: status,
        current_phase: current_phase
      })
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast mission status update: #{e.message}")
    end

    def broadcast_phase_update
      MissionChannel.broadcast_mission_event(id, "phase_changed", {
        mission_id: id,
        status: status,
        current_phase: current_phase,
        phase_progress: phase_progress
      })
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast mission phase update: #{e.message}")
    end
  end
end
