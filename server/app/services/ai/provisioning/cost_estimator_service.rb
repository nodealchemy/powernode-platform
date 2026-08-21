# frozen_string_literal: true

module Ai
  module Provisioning
    # Estimates the monthly + one-time spend for a provisioning plan so the
    # operator can review costs before approving. Walks every plan step,
    # inspects `step.execution_config["inputs"]` for the resource selectors a
    # provisioning skill would need (provider_region_id, provider_instance_type_id,
    # count/target_count, with_storage_gb, egress_gb), looks the live hourly
    # price up out of `System::ProviderInstanceType.hourly_price`, and rolls
    # everything into a single envelope the Plan Review modal renders.
    #
    # Every line item is quoted from what the step ACTUALLY declares. A resource
    # the plan does not request produces no line and no charge, even where that
    # leaves the quote empty — see #declared_gb and FLEET_SIZED_SKILLS.
    #
    # Falls back to the captured Project Brief (regions + scale.initial) when
    # the step doesn't carry explicit selectors — common in the M0 plan where
    # PlanComposerService doesn't yet pin a region or instance type.
    #
    # Confidence is `low` when ANY priced instance type's pricing data hasn't
    # been refreshed in `STALE_PRICING_DAYS` days (we use updated_at as the
    # proxy until the dedicated `pricing_synced_at` column lands), `med` when
    # the plan contains skills we can't price (skipped), and `high` otherwise.
    #
    # Output shape:
    #   {
    #     monthly_usd:   Float,
    #     one_time_usd:  Float,
    #     by_resource:   [{ resource_type: "compute"|"storage"|"network"|"sdwan",
    #                       name: String, monthly_usd: Float, count: Integer }],
    #     confidence:    "high" | "med" | "low"
    #   }
    class CostEstimatorService
      HOURS_PER_MONTH                 = 730 # 24 * 365.25 / 12
      STORAGE_USD_PER_GB_MONTH        = 0.10
      EGRESS_USD_PER_GB               = 0.09
      DEFAULT_INSTANCE_COUNT          = 1
      STALE_PRICING_DAYS              = 30
      ONE_TIME_PER_NETWORK_USD        = 0.0  # SDWAN VIP cost is zero today.

      # Skills that touch compute (each step contributes the priced instance(s)).
      COMPUTE_SKILLS = %w[
        provision_full_stack
        provision_cluster
        docker_provision
        rolling_module_upgrade
        scale_project
      ].freeze

      # Of the compute skills, the ones whose step provisions the WHOLE fleet,
      # so a missing explicit count may legitimately fall back to the brief's
      # `scale.initial`.
      #
      # Deliberately excludes `docker_provision`, `rolling_module_upgrade`, and
      # `scale_project`:
      #
      #   * `docker_provision` and `rolling_module_upgrade` both CONFIGURE
      #     instances an earlier step already created — see
      #     CONFIGURES_EXISTING_INSTANCES — so neither creates a fleet to size.
      #     (IMP-051509357291, IMP-fa199b518d65)
      #   * `scale_project` prices a DELTA (see #instance_count) — a scale-out
      #     that forgot its delta must not silently quote the whole fleet.
      FLEET_SIZED_SKILLS = %w[
        provision_full_stack
        provision_cluster
      ].freeze

      # Compute skills whose step CONFIGURES instances an earlier step already
      # created, rather than creating any of its own. They contribute no compute
      # line at all, and are proven by what each executor's `perform` actually
      # does, not by name or docstring:
      #
      #   * DockerProvisionExecutor#perform takes a `node_instance_id`, looks
      #     the instance up and fails when it does not exist
      #     (docker_provision_executor.rb:42-47). (IMP-051509357291)
      #   * RollingModuleUpgradeExecutor#perform resolves its targets via
      #     `system_list_instances(template_id:)`, filtered to instances
      #     already `running`/`starting` (rolling_module_upgrade_executor.rb:
      #     74-80), then batches them for an in-place module swap
      #     (:94-103) — no arm calls a provisioning action. (IMP-fa199b518d65)
      #
      # Either way, whatever those instances cost is already carried by the
      # provision step that made them. Billing the leg again double-counts the
      # fleet on the very card the operator approves.
      CONFIGURES_EXISTING_INSTANCES = %w[docker_provision rolling_module_upgrade].freeze

      # The `scale_project` arms that ADD instances, so their delta is a real
      # marginal cost. The skill also offers `vertical_resize` (resizes in
      # place) and `remove_replicas` (scale-IN), both of which carry a
      # `target_count` and create NOTHING — pricing their delta as new compute
      # would fabricate exactly the class of line this service stopped emitting,
      # and would be worse than the old behaviour, which priced scale_project at
      # nothing at all.
      #
      # Same rule as VerificationService#additive_scaling?, widened by
      # `add_region` because the skill's own input descriptor counts that arm as
      # instances to ADD. Plain strings flowing through the skill-resolution
      # seam — core does not reference the extension executor or its strategy
      # list (the same reason AdaptationProposerService names its own).
      ADD_REGION_STRATEGY = "add_region"

      # Skills that compose only network/sdwan resources.
      NETWORK_SKILLS = %w[
        sdwan_failover
        sdwan_vip_failover
        sdwan_bgp_session_remediate
        sdwan_peer_remediate
      ].freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Aggregate cost estimate for a whole plan. Pulls the brief out of the
      # backing mission's configuration so steps that omit selectors can fall
      # back to scale.initial / regions.
      #
      # @param plan [Ai::GoalPlan]
      # @return [Hash]
      def estimate(plan:)
        brief    = brief_for(plan) || {}
        steps    = ordered_steps(plan)
        by_resource = []
        monthly  = 0.0
        one_time = 0.0
        stale    = false
        priced_anything = false
        unpriceable = 0
        compute_unpriced = false

        steps.each do |step|
          line_items = estimate_step(step: step, brief: brief)
          line_items[:by_resource].each do |row|
            by_resource << row
            monthly += row[:monthly_usd].to_f
          end
          one_time += line_items[:one_time_usd].to_f
          stale ||= line_items[:stale]
          priced_anything ||= line_items[:priced]
          unpriceable += 1 if line_items[:unpriceable]
          compute_unpriced ||= line_items[:compute_unpriced]
        end

        {
          monthly_usd:  monthly.round(2),
          one_time_usd: one_time.round(2),
          by_resource:  collapse_by_resource(by_resource),
          confidence:   confidence_for(
            stale: stale, priced_anything: priced_anything,
            unpriceable: unpriceable, compute_unpriced: compute_unpriced
          )
        }
      end

      # Per-step estimate. Public so the Plan Review modal can show a per-step
      # contribution if the operator drills in.
      #
      # @param step [Ai::GoalPlanStep, #execution_config]
      # @param brief [Hash, nil] optional fallback for scale/region defaults.
      # @return [Hash] {
      #   by_resource: [...], one_time_usd: Float, stale: Boolean, priced: Boolean,
      #   unpriceable: Boolean, compute_unpriced: Boolean
      # }
      def estimate_step(step:, brief: nil)
        cfg     = (step.respond_to?(:execution_config) ? step.execution_config : {}) || {}
        cfg     = cfg.is_a?(Hash) ? cfg : {}
        skill   = cfg["skill"] || cfg[:skill] || ""
        inputs  = cfg["inputs"] || cfg[:inputs] || {}
        inputs  = inputs.is_a?(Hash) ? inputs : {}

        # `.presence`, not `||`: #estimate always passes `brief_for(plan) || {}`,
        # and `{}` is truthy — a bare `||` chain never reached the step's own
        # embedded brief, silently disabling the FLEET_SIZED_SKILLS
        # scale.initial fallback for goals whose metadata carries no
        # provisioning_mission_id (IMP-260b13250127). PlanComposerService
        # embeds the brief into step inputs (synthesize_plan!, rewrite_step!),
        # so the step-local copy is the legitimate fallback source.
        embedded_brief = inputs["brief"] || inputs[:brief]
        effective_brief = (brief.presence || embedded_brief || {})

        if COMPUTE_SKILLS.include?(skill.to_s)
          compute_line_items(skill: skill.to_s, inputs: inputs, brief: effective_brief)
        elsif NETWORK_SKILLS.include?(skill.to_s)
          network_line_items(skill: skill.to_s, inputs: inputs, brief: effective_brief)
        else
          # Skills we can't reliably price (drift_remediate, runbook_generate,
          # capacity_recommend, etc.). Surface them as unpriceable so confidence
          # downgrades to medium.
          { by_resource: [], one_time_usd: 0.0, stale: false, priced: false, unpriceable: true, compute_unpriced: false }
        end
      end

      private

      # ---------------- compute pricing ----------------

      # Provider types that don't accrue cloud-style charges — runs on the
      # operator's own hardware/disk/network, so compute/storage/egress are
      # all $0. Surface a single "free" line so the plan still shows what's
      # being provisioned without confusing operators with phantom costs.
      LOCAL_PROVIDER_TYPES = %w[local_qemu].freeze

      def compute_line_items(skill:, inputs:, brief:)
        instance_type = lookup_instance_type(inputs)
        region_id     = inputs["provider_region_id"] || inputs[:provider_region_id]
        count         = instance_count(skill: skill, inputs: inputs, brief: brief)
        # Key ORDER from the shared reader (IMP-b439270dab0d) so a change there
        # cannot leave the quote reading a different declaration than the
        # actuator. #declared_gb keeps its own NORMALISATION — a quote needs a
        # non-negative integer, which the other surfaces do not.
        storage_gb    = declared_gb(inputs, *::Shared::StorageSizeResolution::KEYS)
        egress_gb     = declared_gb(inputs, "egress_gb")

        regions = Array(brief["regions"] || brief[:regions])
        region_label = region_label_for(region_id) || regions.first || "default"

        # Local hypervisor short-circuit — no compute/storage/egress charges.
        if instance_type && local_provider?(instance_type)
          name = "#{instance_type.name} on local hypervisor × #{count}"
          rows = [build_row(resource_type: "compute", name: name, monthly_usd: 0.0, count: count)]
          return {
            by_resource: rows,
            one_time_usd: 0.0,
            stale: false,
            priced: true,
            unpriceable: false,
            compute_unpriced: false
          }
        end

        compute_monthly = 0.0
        priced = false
        stale = false
        compute_unpriced = false

        if instance_type
          hourly = price_for_instance(instance_type, region_id)
          compute_monthly = (hourly.to_f * HOURS_PER_MONTH * count).round(2)
          priced = compute_monthly > 0
          # A pinned instance type that couldn't be priced (nil/zero hourly) must
          # not be masked by defaulted storage/egress when confidence is judged.
          compute_unpriced = count.positive? && compute_monthly <= 0
          stale = pricing_stale?(instance_type)
          name = "#{region_label} #{instance_type.name}"
        else
          # Unpinned instance type — emit a placeholder so the operator knows
          # this is a sketch, not a hard quote.
          name = "#{region_label} (instance type TBD)"
        end

        rows = []
        rows << build_row(resource_type: "compute", name: name, monthly_usd: compute_monthly, count: count) if count.positive?

        # NO DATA ⇒ NO LINE (IMP-051509357291). Both of these are quoted only
        # when the step actually declares the resource. They used to fall back
        # to a 50GB volume and a 100GB egress allowance per instance, but
        # nothing writes either key by default — so every approval card billed
        # the operator for resources the plan does not provision, and the
        # phantom lines simultaneously marked the step `priced`, painting a
        # fabricated total as high confidence.
        #
        # No root-disk line is emitted either. The storage a SKU includes lives
        # on the resolved instance type's own `storage_gb` and is already bought
        # by `hourly_price` (the Proxmox provider uses that field as the rootfs
        # size), so charging it again here would swap one fabricated line for
        # another.
        storage_monthly = (storage_gb * STORAGE_USD_PER_GB_MONTH * count).round(2)
        rows << build_row(resource_type: "storage", name: "#{storage_gb}GB volume × #{count}", monthly_usd: storage_monthly, count: count) if storage_monthly.positive?

        egress_monthly = (egress_gb * EGRESS_USD_PER_GB * count).round(2)
        rows << build_row(resource_type: "network", name: "egress (~#{egress_gb}GB × #{count})", monthly_usd: egress_monthly, count: count) if egress_monthly.positive?

        {
          by_resource: rows,
          one_time_usd: one_time_for(skill),
          stale: stale,
          priced: priced || storage_monthly.positive? || egress_monthly.positive?,
          unpriceable: false,
          compute_unpriced: compute_unpriced
        }
      end

      # True when the instance type belongs to a provider that runs on local
      # hardware (LocalQemu, future on-prem types) and accrues no cloud charges.
      def local_provider?(instance_type)
        return false unless instance_type.respond_to?(:provider) && instance_type.provider
        LOCAL_PROVIDER_TYPES.include?(instance_type.provider.provider_type.to_s)
      rescue StandardError
        false
      end

      # ---------------- network/sdwan pricing ----------------

      def network_line_items(skill:, inputs:, brief:)
        # SDWAN VIPs and overlay setup carry no marginal cost today — the
        # underlying compute hosts the agent. Surface a zero-cost line so the
        # operator sees the resource was considered.
        regions = Array(brief["regions"] || brief[:regions])
        label = "SDWAN (#{regions.first || 'default'})"

        rows = [build_row(resource_type: "sdwan", name: label, monthly_usd: 0.0, count: 1)]

        {
          by_resource: rows,
          one_time_usd: ONE_TIME_PER_NETWORK_USD,
          stale: false,
          priced: true,
          unpriceable: false,
          compute_unpriced: false
        }
      end

      def one_time_for(skill)
        # Reserved for skills that involve a one-time setup cost (e.g.,
        # data migration, image build). Zero today.
        case skill
        when "rolling_module_upgrade" then 0.0
        else 0.0
        end
      end

      # ---------------- helpers ----------------

      def lookup_instance_type(inputs)
        id = inputs["provider_instance_type_id"] || inputs[:provider_instance_type_id]
        return nil if id.blank?
        return nil unless defined?(::System::ProviderInstanceType)
        ::System::ProviderInstanceType.find_by(id: id, account_id: account.id)
      rescue StandardError => e
        Rails.logger.warn("[CostEstimatorService] instance type lookup failed: #{e.class}: #{e.message}")
        nil
      end

      def price_for_instance(instance_type, region_id)
        if region_id.present? && instance_type.respond_to?(:price_in_region)
          region = lookup_region(region_id)
          return instance_type.price_in_region(region) if region
        end
        instance_type.respond_to?(:hourly_price) ? instance_type.hourly_price : nil
      rescue StandardError
        instance_type.respond_to?(:hourly_price) ? instance_type.hourly_price : nil
      end

      def lookup_region(region_id)
        return nil unless defined?(::System::ProviderRegion)
        ::System::ProviderRegion.find_by(id: region_id, account_id: account.id)
      rescue StandardError
        nil
      end

      def region_label_for(region_id)
        return nil if region_id.blank?
        region = lookup_region(region_id)
        region&.region_code || region&.name
      end

      def pricing_stale?(instance_type)
        # Use updated_at as the staleness proxy until the dedicated
        # `pricing_synced_at` column lands (PricingSyncService backfills LLM
        # token pricing today, not provider instance pricing).
        ts = instance_type.respond_to?(:updated_at) ? instance_type.updated_at : nil
        return true unless ts
        ts < STALE_PRICING_DAYS.days.ago
      end

      # How many instances this step CREATES — which is what the plan is billed
      # for. Zero is a legitimate answer, and #compute_line_items emits no rows
      # at all for it.
      #
      # `scale_project` prices a DELTA: AdaptationProposerService stamps
      # `target_count` as "the number of NEW instances to add", not an absolute
      # target, so the marginal cost of an additive scale-out IS that value —
      # but ONLY for the additive arms (see ADD_REGION_STRATEGY).
      #
      # The brief's `scale.initial` fallback applies to FLEET_SIZED_SKILLS only
      # — see that constant for why inheriting it elsewhere over-quotes.
      def instance_count(inputs:, brief:, skill: nil)
        return 0 if CONFIGURES_EXISTING_INSTANCES.include?(skill.to_s)

        explicit = inputs["count"] || inputs[:count] || inputs["instance_count"] || inputs[:instance_count]

        if skill.to_s == "scale_project"
          # A non-additive (or unstated) strategy creates nothing, so neither
          # an authored count nor a delta may be quoted as new compute.
          return 0 unless additive_scaling?(inputs)
          explicit ||= inputs["target_count"] || inputs[:target_count]
          return explicit.present? ? explicit.to_i : 0
        end

        return explicit.to_i if explicit.present?

        if FLEET_SIZED_SKILLS.include?(skill.to_s)
          scale = brief["scale"] || brief[:scale] || {}
          scale = scale.is_a?(Hash) ? scale : {}
          initial = scale["initial"] || scale[:initial]
          return initial.to_i if initial.present?
        end

        DEFAULT_INSTANCE_COUNT
      end

      # Whether a `scale_project` step's strategy is one that ADDS instances.
      # Resolved through AdaptationProposerService's own constant so core states
      # the scale-out strategy in exactly one place, matching
      # VerificationService#additive_scaling?.
      def additive_scaling?(inputs)
        strategy = (inputs["scaling_strategy"] || inputs[:scaling_strategy]).to_s
        return false if strategy.blank?

        strategy == ::Ai::Provisioning::AdaptationProposerService::SCALE_OUT_STRATEGY ||
          strategy == ADD_REGION_STRATEGY
      end

      # A resource size the step explicitly declares, in GB, or 0 when it
      # declares none. There is deliberately NO default: a quote for a resource
      # the plan never requested is a fabricated line item (IMP-051509357291).
      #
      # Non-positive reads as "not requested", matching
      # PlanComposerService#brief_storage_gb and the provisioning executor's own
      # `storage_requested?` guard (IMP-33fa6c51f05d closed the gap where that
      # guard was `blank?` — `0.blank?` is false in Ruby, so a hand-authored 0
      # used to reach it and fail its storage leg per node while this quote
      # showed no volume line at all). Composer, quote, and actuator now agree
      # on the SIZE question; a change to one of them is a change to a contract
      # the other two are written against.
      #
      # They agree on the KEY too (IMP-f85254148755): `storage_gb` is read
      # here as an alias, and ProvisionFullStackExecutor now resolves the same
      # alias in the same order — `with_storage_gb` first, first PRESENT value
      # wins — so a hand-authored plan carrying `storage_gb` alone is
      # provisioned for exactly what this quote prices. `with_storage_gb`
      # remains the only ADVERTISED input key; the alias is a compatibility
      # read on both surfaces, not a descriptor entry.
      #
      # `respond_to?(:to_i)` screens out shapes with no numeric reading at all
      # (Hash/Array/true). It deliberately does NOT screen out the not-found
      # case — nil does respond to :to_i, and nil.to_i == 0 lands on the same
      # "not requested" answer. A DECLARED-but-unreadable value ("plenty",
      # true, {a: 1}) also quotes no line here — nothing will be provisioned
      # for it — but it is not silent end-to-end: the executor records a
      # per-node `provision_storage` failure entry for it
      # (requested-but-unusable fails loud; the ratified 4db30efae fork).
      def declared_gb(inputs, *keys)
        raw = keys.lazy.flat_map { |k| [ inputs[k], inputs[k.to_sym] ] }.find(&:present?)
        return 0 unless raw.respond_to?(:to_i)

        value = raw.to_i
        value.positive? ? value : 0
      end

      def ordered_steps(plan)
        return [] unless plan&.respond_to?(:steps)
        relation = plan.steps
        relation.respond_to?(:in_order) ? relation.in_order.to_a : relation.to_a.sort_by { |s| s.step_number.to_i }
      end

      def brief_for(plan)
        meta = plan.respond_to?(:goal) ? plan.goal&.metadata : nil
        mission_id = meta.is_a?(Hash) ? meta["provisioning_mission_id"] : nil
        return nil unless mission_id

        mission = account.ai_missions.find_by(id: mission_id)
        cfg = mission&.configuration
        cfg.is_a?(Hash) ? (cfg["brief"] || cfg[:brief]) : nil
      rescue StandardError
        nil
      end

      def build_row(resource_type:, name:, monthly_usd:, count:)
        { resource_type: resource_type, name: name, monthly_usd: monthly_usd.to_f.round(2), count: count.to_i }
      end

      # Collapse rows that have the same (resource_type, name) pair so the UI
      # doesn't render duplicate lines. Sums monthly_usd + count.
      def collapse_by_resource(rows)
        rows.each_with_object({}) do |row, h|
          key = [row[:resource_type], row[:name]]
          existing = h[key]
          if existing
            existing[:monthly_usd] = (existing[:monthly_usd] + row[:monthly_usd]).round(2)
            existing[:count] += row[:count]
          else
            h[key] = row.dup
          end
        end.values
      end

      def confidence_for(stale:, priced_anything:, unpriceable:, compute_unpriced: false)
        return "low"  if stale
        return "low"  unless priced_anything
        # A pinned-but-unpriceable compute line is a missing hard quote — downgrade
        # to medium so defaulted storage/egress can't paint it as high confidence.
        return "med"  if compute_unpriced
        return "med"  if unpriceable.positive?
        "high"
      end
    end
  end
end
