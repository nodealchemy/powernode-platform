# frozen_string_literal: true

module Ai
  module Provisioning
    # Single source of truth for the "rich plan" shape consumed by the
    # provisioning frontend (BriefCard, ProvisioningPlanReview,
    # ChatProvisioningCardSlot, StackTopologyPreview, CostBreakdown,
    # StepProgressStream).
    #
    # Both surfaces that surface a plan use this:
    #   - Ai::Tools::ProvisioningTool#compose_plan (chat tool returning a card)
    #   - Api::V1::Ai::MissionsController#compose_plan (REST endpoint hit by
    #     the deep-link page /app/system/provision?mission_id=…)
    #
    # Returned shape:
    #   {
    #     plan_id:,
    #     dag: { nodes: [...], edges: [...] },   # nodes/edges, not steps
    #     cost_estimate: { monthly_usd:, one_time_usd:, by_resource:, ... },
    #     topology_preview: { nodes:, edges:, regions:, estimated_resources: },
    #     risk: { score:, severity:, factors: }
    #   }
    #
    # Each enrichment is wrapped in `rescue StandardError` with a sane fallback
    # so a failing renderer doesn't 500 the response — the operator sees a
    # placeholder card instead.
    class PlanSnapshotService
      def initialize(account:)
        @account = account
      end

      # @param plan [Ai::GoalPlan]
      # @return [Hash] rich plan snapshot
      def snapshot(plan:)
        estimate = build_cost_estimate(plan)
        {
          plan_id: plan.id,
          dag: build_dag(plan),
          cost_estimate: estimate,
          topology_preview: build_topology_preview(plan),
          risk: build_risk(plan),
          budget: build_budget(plan, estimate)
        }.compact
      end

      # F7 (IMP 019fe4c5-2e24): the brief states a monthly cap and the
      # snapshot states an estimate — and no surface ever compared them
      # ($5 cap vs $42 and $168 estimates sailed through both operator
      # gates unflagged). Surface the comparison as a first-class field so
      # the approver — and P2's auto-approver — sees the overage.
      def build_budget(plan, estimate)
        brief = plan_brief(plan)
        cap = brief && (brief["budget_cap_usd_monthly"] || brief[:budget_cap_usd_monthly])
        return nil if cap.blank?

        cap = cap.to_f
        est = ((estimate || {})[:monthly_usd] || (estimate || {})["monthly_usd"]).to_f
        {
          cap_usd_monthly: cap,
          estimate_usd_monthly: est,
          within_budget: est <= cap,
          overage_usd_monthly: [ (est - cap).round(2), 0.0 ].max
        }
      end

      # The composer stamps the brief onto every step's inputs — read it back
      # from the first step that carries one.
      def plan_brief(plan)
        plan.steps.each do |s|
          brief = (s.execution_config || {}).dig("inputs", "brief")
          return brief if brief.is_a?(Hash)
        end
        nil
      end

      private

      attr_reader :account

      # Frontend ProvisioningPlanReview reads `plan.dag.nodes` with each node
      # having { id, name, skill, description, status, dependencies }. The
      # legacy `serialize_dag` returned `{steps: [...]}` which silently
      # rendered as "0 steps" everywhere it was consumed.
      def build_dag(plan)
        steps = plan.steps.reload.to_a.sort_by { |s| s.step_number.to_i }
        purpose = plan_purpose_for(plan)
        nodes = steps.map { |s| node_for(s, plan_purpose: purpose) }
        edges = build_edges(steps)
        { nodes: nodes, edges: edges }
      end

      # Pulls the operator's stated purpose from the plan's goal — the brief's
      # use_case ends up here via PlanComposerService.find_or_create_goal!
      # ("marketing website for an insulation company", "Discord bot for daily
      # RSS posts"). Used to differentiate steps that share the same skill +
      # resource shape but serve a particular project, so the operator sees
      # "Provision 1× qemu.small for marketing site" instead of just
      # "Provision 1× qemu.small".
      def plan_purpose_for(plan)
        return nil unless plan.respond_to?(:goal) && plan.goal
        desc = plan.goal.description.to_s.strip
        return desc if desc.present?
        plan.goal.title.to_s.sub(/\AProvision:\s*/, "").strip.presence
      rescue StandardError
        nil
      end

      def node_for(step, plan_purpose: nil)
        cfg = step.execution_config.is_a?(Hash) ? step.execution_config : {}
        skill = (cfg["skill"] || cfg[:skill]).to_s
        inputs = (cfg["inputs"] || cfg[:inputs] || {})
        node = {
          id: step.id.to_s,
          step_number: step.step_number,
          name: cfg["name"] || cfg[:name] || derive_step_name(skill, inputs),
          skill: skill.presence,
          description: cfg["description"] || cfg[:description] || derive_step_description(skill, inputs, plan_purpose: plan_purpose),
          dependencies: Array(step.dependencies).map(&:to_i),
          status: step.respond_to?(:status) ? step.status.to_s : "pending",
          on_failure: cfg["on_failure"] || cfg[:on_failure]
        }

        # IMP-1fc00ac8547a: declared-required inputs the composer resolves but
        # this step did not get. Served so the omission reaches the plan-review
        # surface rather than living only in the composer's log. Added only
        # when present — an ADDITIVE key, so no existing node field changes
        # shape for a healthy step.
        omitted = cfg["unnormalized_inputs"] || cfg[:unnormalized_inputs]
        node[:unnormalized_inputs] = omitted if omitted.present?
        node
      end

      # Derive a human-friendly headline from skill + inputs so 4 identical
      # `provision_full_stack` steps stop reading as 4 identical rows.
      # Example outputs:
      #   "Provision 2× qemu.small (local hypervisor)"
      #   "Scale qemu.small +1"
      #   "Attach 50GB volume"
      def derive_step_name(skill, inputs)
        case skill
        when "provision_full_stack"
          count = (inputs["count"] || inputs[:count] || 1).to_i
          inst = resolve_instance_label(inputs)
          region = resolve_region_label(inputs)
          parts = ["Provision"]
          parts << "#{count}×"
          parts << inst if inst
          parts << "(#{region})" if region
          parts.join(" ")
        when "scale_project"
          delta = (inputs["delta"] || inputs[:delta] || inputs["count"] || 1).to_i
          inst = resolve_instance_label(inputs)
          "Scale #{inst || 'compute'} #{delta.positive? ? '+' : ''}#{delta}"
        when "attach_storage"
          # ONE order, shared with the executor and the estimator
          # (IMP-b439270dab0d). This spelled its own: it read by TRUTHINESS, so
          # a blank-but-non-nil `with_storage_gb: ""` won here and labelled 0 GB
          # while the executor fell through to the alias and provisioned it; and
          # it interposed `size_gb`, which is ProviderVolume's own column rather
          # than a step input — no producer emits it, and neither of the other
          # two readers looks for it.
          gb = ::Shared::StorageSizeResolution.from_inputs(inputs).to_i
          gb.positive? ? "Attach #{gb}GB volume" : "Attach storage"
        when "configure_sdwan_for_project"
          "Configure SDWAN"
        when "deploy_app_code"
          repo = inputs["repo_url"] || inputs[:repo_url]
          repo.present? ? "Deploy #{repo.to_s.split('/').last(2).join('/')}" : "Deploy app code"
        when "relocate_workload"
          dst = inputs["target_region"] || inputs[:target_region]
          dst.present? ? "Relocate to #{dst}" : "Relocate workload"
        when "", nil
          "Step"
        else
          skill.tr("_", " ").capitalize
        end
      end

      # Build the second-line description for a step. Leads with the
      # operator's stated purpose ("marketing website for an insulation
      # company") so the row tells you WHAT will run on the box, not just
      # the resource shape. Falls back to the resource breakdown alone
      # when no purpose was captured.
      def derive_step_description(skill, inputs, plan_purpose: nil)
        bits = []
        bits << "For: #{plan_purpose}" if plan_purpose.present? && provision_like?(skill)

        if skill == "provision_full_stack"
          if (count = (inputs["count"] || inputs[:count] || 1).to_i).positive?
            bits << "#{count} instance#{count == 1 ? '' : 's'}"
          end
          if (inst = resolve_instance_label(inputs))
            bits << inst
          end
          if (region = resolve_region_label(inputs))
            bits << region
          end
          # Last, but never omitted: boot_mode is what makes the difference
          # between a Powernode node and an inert cloud VM.
          if (template = resolve_template_label(inputs))
            bits << template
          end
        elsif skill == "scale_project"
          if (inst = resolve_instance_label(inputs))
            bits << inst
          end
        elsif skill == "attach_storage"
          # ONE order, shared with the executor and the estimator
          # (IMP-b439270dab0d). This spelled its own: it read by TRUTHINESS, so
          # a blank-but-non-nil `with_storage_gb: ""` won here and labelled 0 GB
          # while the executor fell through to the alias and provisioned it; and
          # it interposed `size_gb`, which is ProviderVolume's own column rather
          # than a step input — no producer emits it, and neither of the other
          # two readers looks for it.
          gb = ::Shared::StorageSizeResolution.from_inputs(inputs).to_i
          bits << "#{gb}GB" if gb.positive?
        elsif skill == "deploy_app_code"
          bits << inputs["branch"] if inputs["branch"].present?
        end

        bits.empty? ? nil : bits.join(" · ")
      end

      # Skill families where a "For: <purpose>" prefix on the step row makes
      # sense. Pure-infrastructure operations (configure_sdwan, etc.) read
      # better without one.
      def provision_like?(skill)
        %w[provision_full_stack scale_project attach_storage deploy_app_code relocate_workload].include?(skill.to_s)
      end

      # Provision-step inputs may reference fleet-substrate records (instance types, regions)
      # owned by the System extension. Core resolves their display labels through the generic
      # provider(:provision_label_resolver) seam — the extension injects the lookup (and any
      # provider-type-specific naming); core names no extension constant. nil ⇒ core mode (the
      # extension is absent), in which case the label is simply omitted.
      def provision_label_resolver
        ::Powernode::ExtensionRegistry.provider(:provision_label_resolver)
      rescue StandardError
        nil
      end

      def resolve_instance_label(inputs)
        provision_label_resolver&.instance_label(account: account, inputs: inputs)
      rescue StandardError
        nil
      end

      def resolve_region_label(inputs)
        provision_label_resolver&.region_label(account: account, inputs: inputs)
      rescue StandardError
        nil
      end

      # The template (with boot_mode) the step will actually use. Surfaced at
      # the approval gate because boot_mode decides whether the provisioned node
      # carries the agent at all — a plan that resolved to the wrong template
      # otherwise reads completely normal here (IMP 019fe1e0-0b8a).
      # respond_to? guards a resolver from an older extension build that
      # predates this method.
      def resolve_template_label(inputs)
        resolver = provision_label_resolver
        return nil unless resolver.respond_to?(:template_label)

        resolver.template_label(account: account, inputs: inputs)
      rescue StandardError
        nil
      end

      # Each step's `dependencies` field stores upstream step_numbers; resolve
      # them back to step IDs so the frontend can draw arrows between nodes.
      def build_edges(steps)
        by_number = steps.each_with_object({}) { |s, h| h[s.step_number.to_i] = s }
        edges = []
        steps.each do |s|
          Array(s.dependencies).each do |dep_num|
            source = by_number[dep_num.to_i]
            edges << { from: source.id.to_s, to: s.id.to_s } if source
          end
        end
        edges
      end

      def build_cost_estimate(plan)
        ::Ai::Provisioning::CostEstimatorService.new(account: account).estimate(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[PlanSnapshotService] cost estimate failed: #{e.class}: #{e.message}")
        { monthly_usd: 0.0, one_time_usd: 0.0, by_resource: [], confidence: "low" }
      end

      def build_topology_preview(plan)
        ::Ai::Provisioning::TopologyRendererService.new(account: account, plan: plan).render
      rescue StandardError => e
        Rails.logger.warn("[PlanSnapshotService] topology render failed: #{e.class}: #{e.message}")
        { nodes: [], edges: [], regions: [], estimated_resources: [] }
      end

      def build_risk(plan)
        ::Ai::Provisioning::RiskScorerService.new(account: account).score(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[PlanSnapshotService] risk scoring failed: #{e.class}: #{e.message}")
        { score: 0, severity: "low", factors: [] }
      end
    end
  end
end
