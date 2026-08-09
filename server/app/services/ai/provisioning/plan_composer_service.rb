# frozen_string_literal: true

module Ai
  module Provisioning
    # Composes an executable provisioning plan from a Project Brief.
    #
    # Reads the brief out of `mission.configuration["brief"]`, finds (or creates)
    # a backing `Ai::AgentGoal`, defers DAG synthesis to the existing
    # `Ai::Autonomy::GoalDecompositionService` LLM kernel, and then rewrites
    # every step into the provisioning shape the runner expects:
    #
    #     step.step_type == "provisioning_skill"
    #     step.execution_config == { "skill" => <executor>, "inputs" => {...},
    #                                 "on_failure" => "rollback" }
    #
    # The returned plan is an `Ai::GoalPlan` whose steps are persisted.
    class PlanComposerService
      class BriefMissingError < StandardError; end
      class AgentMissingError < StandardError; end

      # Allowed executor names — must match the `descriptor[:name]` of every
      # registered provisioning skill. Validated by #validate_plan and by
      # #rewrite_step!.
      ALLOWED_EXECUTORS = %w[
        provision_full_stack
        drift_remediate
        docker_provision
        provision_cluster
        rolling_module_upgrade
        capacity_recommend
        cve_response
        sdwan_failover
        sdwan_vip_failover
        sdwan_bgp_session_remediate
        sdwan_peer_remediate
        module_compose
        runbook_generate
        attribute_failure
        cve_runbook_generate
        deploy_app_code
      ].freeze

      DEFAULT_EXECUTOR = "provision_full_stack"

      # M3 "Run My Code" — role module selection.
      #
      # When a brief carries a `repo_url`, the provisioned NodeTemplate needs
      # a runtime role module attached so the deploy_app_code step has the
      # right interpreter / toolchain available. The selection priority is:
      #
      #   1. brief["runtime_hint"] — explicit operator hint wins.
      #      A known hint that maps to nil (e.g. "ruby" today) is honored
      #      as "skip attachment" rather than falling through, so the
      #      plan doesn't silently attach the wrong runtime.
      #   2. brief["use_case"] — workload-shape default.
      #   3. DEFAULT_ROLE_MODULE — final fallback.
      #
      # The actual System::NodeModule lookup is best-effort — if Slice A
      # hasn't seeded the named module yet, we log and skip rather than
      # raise.
      ROLE_MODULE_FOR_USE_CASE = {
        "discord_bot" => "nodejs-runtime",
        "telegram_bot" => "nodejs-runtime",
        "web_app" => "nodejs-runtime", # default for web_app; runtime_hint can override
        "api_server" => "nodejs-runtime",
        "database" => "postgres-server",
        "cache" => "redis-cache",
        "containerized_app" => "docker-runtime"
      }.freeze

      RUNTIME_HINT_TO_MODULE = {
        "node" => "nodejs-runtime",
        "python" => "python-runtime",
        "ruby" => nil,    # not yet seeded; Slice A may add later
        "go" => nil,
        "docker" => "docker-runtime",
        "java" => nil,
        "none" => nil
      }.freeze

      DEFAULT_ROLE_MODULE = "nodejs-runtime"

      # Static fallback action→skill map (used when SemanticToolDiscoveryService
      # is unavailable or returns no in-allowlist match). Order matters — first
      # pattern that matches wins, so put more specific patterns first.
      # Order matters — first match wins. Specific patterns first, then generic
      # fallbacks. Anchor terms with `\b` so plain "sdwan" doesn't swallow a
      # "sdwan failover" utterance that should land on sdwan_failover.
      STATIC_ACTION_MAP = [
        [/\bcve\s+runbook|vuln(erability)?\s+runbook\b/i, "cve_runbook_generate"],
        [/\bcve\b|\bvuln/i, "cve_response"],
        [/\brunbook\b/i, "runbook_generate"],
        [/\bbgp\b/i, "sdwan_bgp_session_remediate"],
        [/\bvip\b|virtual\s+ip/i, "sdwan_vip_failover"],
        [/\bfail-?over\b/i, "sdwan_failover"],
        [/\bpeer\b/i, "sdwan_peer_remediate"],
        [/\bmodule\s+compose|compose.*module/i, "module_compose"],
        [/\brolling\s+upgrade|upgrade.*rolling|rolling\s+module/i, "rolling_module_upgrade"],
        [/\bdrift\b/i, "drift_remediate"],
        [/\bcapacity|sizing|recommend/i, "capacity_recommend"],
        [/\battribute.*fail|attr\s+fail/i, "attribute_failure"],
        [/\bdocker|container/i, "docker_provision"],
        [/\bcluster\b/i, "provision_cluster"],
        [/\bprovision|create|stand[\s-]?up|deploy.*stack|new\s+stack/i, "provision_full_stack"]
      ].freeze

      attr_reader :account, :mission

      def initialize(account:, mission:)
        @account = account
        @mission = mission
      end

      # Build a plan, persist it, and rewrite each step to the provisioning shape.
      # Raises BriefMissingError when the mission's configuration has no brief.
      #
      # Returns nil when the account has burned through its daily LLM cost cap
      # (CostCapGuard) — the caller already has the brief and should surface
      # an upgrade prompt rather than retry.
      def compose!
        brief = extract_brief!

        guard = ::Ai::Provisioning::CostCapGuard.allow?(account: account)
        if guard.cap_exceeded?
          Rails.logger.warn(
            "[PlanComposerService] LLM cost cap exceeded for account=#{account&.id} " \
              "(spent=$#{guard.payload[:spent]}, cap=$#{guard.payload[:cap]}); " \
              "skipping decompose for mission=#{mission.id}"
          )
          @cap_exceeded_payload = guard.payload
          return nil
        end

        # M2 BYOC routing — disambiguate which configured cloud provider should
        # back this plan. Returns the chosen System::Provider record, nil when
        # the account has none configured (legacy / test path), or a Hash
        # `{ clarification_needed: true, ... }` that the caller surfaces to the
        # operator without proceeding to decompose.
        provider_choice = resolve_provider_choice(brief)
        return provider_choice if clarification_payload?(provider_choice)
        @account_provider_override = provider_choice

        goal = find_or_create_goal!(brief)
        plan = decompose_goal!(goal)

        return plan unless plan

        rewrite_steps!(plan, brief)
        attach_role_module_to_template!(brief)
        append_deploy_app_code_step!(plan, brief) if brief["repo_url"].present?
        persist_plan_pointer!(plan)
        plan
      end

      # Lazy compaction for already-composed plans. Plans created before
      # collapse_redundant_provisioning_clusters! existed (or composed when
      # the LLM emitted a redundant tree) carry duplicate provision steps
      # in the DB. The deep-link page returns the cached plan as-is, so
      # operators still see the redundant rows. Calling this on read folds
      # them in place — idempotent (no changes when the plan is already
      # compact).
      def compact_existing_plan!(plan)
        collapse_consecutive_same_target_steps!(plan)
      end

      # Set when #compose! aborts because of a cost-cap miss. Callers (the
      # provisioning tool, internal API) read this to render UpgradeRequiredCard.
      attr_reader :cap_exceeded_payload

      # Validate a plan returned by #compose! (or any plan with provisioning
      # steps). Returns `{ valid: Boolean, errors: Array<String> }`. Does not
      # mutate the plan.
      def validate_plan(plan)
        errors = []

        errors << "Plan has no steps" if plan.steps.empty?

        plan.steps.each do |step|
          skill = (step.execution_config || {}).then { |c| c["skill"] || c[:skill] }
          unless ALLOWED_EXECUTORS.include?(skill.to_s)
            errors << "Step #{step.step_number} skill '#{skill}' not in allowed executor list"
          end
        end

        errors << "Plan has circular dependencies" if has_dependency_cycle?(plan)

        valid_step_numbers = plan.steps.map(&:step_number).to_set
        plan.steps.each do |step|
          Array(step.dependencies).each do |dep|
            dep_num = dep.to_i
            unless valid_step_numbers.include?(dep_num)
              errors << "Step #{step.step_number} depends on unknown step #{dep_num}"
            end
          end
        end

        { valid: errors.empty?, errors: errors }
      end

      private

      def extract_brief!
        config = mission.configuration
        brief = config.is_a?(Hash) ? config["brief"] || config[:brief] : nil
        if brief.blank?
          raise BriefMissingError,
                "Mission #{mission.id} has no configuration['brief']; run IntentCaptureService first"
        end
        brief.deep_stringify_keys
      end

      # ----- M2 BYOC: provider routing --------------------------------------
      #
      # Resolves which configured cloud provider the plan should target.
      #
      # Return shapes:
      #   nil                                — account has no providers (test
      #                                        and legacy paths fall back to
      #                                        the unscoped region/instance
      #                                        lookup).
      #   System::Provider                   — single match; subsequent
      #                                        merge_resolved_inputs! scopes
      #                                        the region/instance lookup to
      #                                        this provider.
      #   { clarification_needed: true, ... } — multiple providers and the
      #                                        brief lacks an unambiguous
      #                                        preferred_provider. The caller
      #                                        (ProvisioningTool) surfaces this
      #                                        to the chat UI and aborts the
      #                                        compose without invoking the LLM
      #                                        decomposition kernel.
      def resolve_provider_choice(brief)
        # Core mode: the system extension supplies System::Provider. Its
        # absence already has a defined meaning here — nil means "account has
        # no providers" (see the return-shape doc above), and every caller
        # already treats nil that way (compose! proceeds with
        # @account_provider_override = nil; the unscoped region/instance-type
        # lookups below are the existing legacy/test fallback for exactly
        # that case). Returning nil early is not a new contract, just an
        # earlier exit to the same one.
        return nil unless defined?(::System::Provider)

        providers = ::System::Provider.where(account_id: account.id, enabled: true).to_a
        return nil if providers.empty?
        return providers.first if providers.size == 1

        preferred = brief["preferred_provider"].to_s.strip.downcase
        if preferred.present?
          match = providers.find { |p| p.provider_type.to_s.downcase == preferred }
          return match if match
        end

        {
          clarification_needed: true,
          message: build_clarification_message(providers),
          available_providers: providers.map do |p|
            { id: p.id, name: p.name, type: p.provider_type }
          end
        }
      end

      def clarification_payload?(value)
        value.is_a?(Hash) && value[:clarification_needed] == true
      end

      def build_clarification_message(providers)
        names = providers.map { |p| display_provider_name(p) }.uniq.join(", ")
        "I see you have multiple cloud providers configured (#{names}). " \
          "Which would you like to use?"
      end

      def display_provider_name(provider)
        type = provider.provider_type.to_s
        case type
        when "aws", "gcp" then type.upcase
        when "openstack" then "OpenStack"
        when "digitalocean" then "DigitalOcean"
        when "local_qemu" then "Local QEMU"
        when "pro_cloud" then "Pro Cloud"
        else
          type.split(/[\s_-]/).reject(&:empty?).map(&:capitalize).join(" ")
        end
      end

      # Reuse the most-recent active goal for this mission if one exists,
      # otherwise create a fresh provisioning goal owned by an account agent.
      def find_or_create_goal!(brief)
        existing = Ai::AgentGoal.where(account_id: account.id)
                                .where("metadata @> ?", { "provisioning_mission_id" => mission.id }.to_json)
                                .active
                                .order(created_at: :desc)
                                .first
        return existing if existing

        agent = resolve_provisioning_agent

        # GC stale provisioning goals before creating — Ai::AgentGoal caps
        # active goals per agent at MAX_ACTIVE_GOALS (5). Each chat session
        # that opens compose_plan creates a goal; if the user doesn't follow
        # through to approve+execute, the goal sits at status=pending forever
        # and the next mission hits the cap. Sweep zombie provisioning goals
        # belonging to abandoned chat sessions before creating ours.
        gc_stale_provisioning_goals!(agent)

        Ai::AgentGoal.create!(
          account: account,
          agent: agent,
          title: "Provision: #{brief["intent"].presence || mission.name}",
          description: brief["use_case"].presence || mission.objective.to_s,
          goal_type: "creation",
          status: "pending",
          priority: 3,
          progress: 0.0,
          success_criteria: { "brief" => brief, "mission_id" => mission.id },
          metadata: { "provisioning_mission_id" => mission.id }
        )
      end

      # Threshold for considering a pending provisioning goal abandoned. The
      # user has either closed the chat or moved on to a different mission;
      # the goal will never advance to "active" because no one approved+executed
      # the plan. Conservative — 30 minutes is much longer than a typical
      # provisioning conversation.
      STALE_PROVISIONING_GOAL_THRESHOLD = 30.minutes

      def gc_stale_provisioning_goals!(agent)
        return unless agent

        # Only sweep when we're about to hit the cap — a no-op for
        # accounts under normal load.
        active_count = Ai::AgentGoal.where(ai_agent_id: agent.id).active.count
        return if active_count < Ai::AgentGoal::MAX_ACTIVE_GOALS

        zombies = Ai::AgentGoal
                    .where(ai_agent_id: agent.id, status: "pending")
                    .where("metadata ? 'provisioning_mission_id'")
                    .where("updated_at < ?", STALE_PROVISIONING_GOAL_THRESHOLD.ago)
                    .order(updated_at: :asc)

        zombies.find_each do |goal|
          goal.abandon!("auto-gc: stale provisioning chat session")
          Rails.logger.info(
            "[PlanComposerService] GC'd stale provisioning goal #{goal.id} " \
              "(mission #{goal.metadata["provisioning_mission_id"]})"
          )
        end
      end

      # Select a text-capable agent whose provider matches the account's
      # active LLM credential, so GoalDecompositionService's WorkerLlmClient
      # call resolves to a compatible model. Selecting "first active agent"
      # blindly produces a provider mismatch (e.g. picking an
      # image_generator agent on OpenAI when the working credential is
      # Anthropic) and the LLM call fails on an unknown model ID.
      def resolve_provisioning_agent
        active_credential = account.ai_provider_credentials&.active&.includes(:provider)&.first
        text_capable_types = %w[assistant code_assistant data_analyst monitor mcp_client]

        scope = account.ai_agents
        scope = scope.where(status: "active") if scope.respond_to?(:where)

        if active_credential
          credential_match = scope.where(
            ai_provider_id: active_credential.ai_provider_id,
            agent_type: text_capable_types
          ).first
          return credential_match if credential_match
        end

        # Fallback: any text-capable active agent on the account
        agent = scope.where(agent_type: text_capable_types).first
        agent ||= scope.first
        agent ||= account.ai_agents.first

        unless agent
          raise AgentMissingError,
                "Account #{account.id} has no agents available for plan composition"
        end
        agent
      end

      def decompose_goal!(goal)
        Ai::Autonomy::GoalDecompositionService.new(account: account).decompose(goal)
      end

      # Stamps the new plan's id onto `mission.configuration["plan"]["plan_id"]`
      # so downstream callers (the internal /execute endpoint, the MCP
      # ProvisioningTool, the worker's AiProvisioningStepJob → controller
      # lookup) all resolve the same plan without walking back through the
      # goal metadata. Uses update_columns to skip Mission's broadcast
      # callbacks — composing a plan is an internal step, not a phase change.
      def persist_plan_pointer!(plan)
        return unless plan&.respond_to?(:id)
        cfg = mission.configuration.is_a?(Hash) ? mission.configuration.deep_dup : {}
        cfg["plan"] ||= {}
        cfg["plan"]["plan_id"] = plan.id
        mission.update_columns(configuration: cfg)
      end

      # Convert the LLM's mixed step output into provisioning-skill steps.
      # The LLM emits a variety of step_types via build_decomposition_prompt:
      # `agent_execution` (the real provisioning work), plus advisory types
      # like `human_review`, `observation`, and `sub_goal`. Only executable
      # steps belong in the runner's DAG — we drop the advisory ones rather
      # than blindly converting every step to `provision_full_stack`, which
      # was producing 9-17 step plans for trivial single-instance briefs.
      EXECUTABLE_STEP_TYPES = %w[agent_execution provisioning_skill].freeze

      def rewrite_steps!(plan, brief)
        steps = plan.steps.reload.to_a

        executable, advisory = steps.partition do |s|
          EXECUTABLE_STEP_TYPES.include?(s.step_type.to_s)
        end

        # Drop advisory steps and renumber executable steps + their
        # dependencies so the resulting DAG is contiguous from 1.
        renumber = {}
        executable.sort_by(&:step_number).each_with_index do |step, idx|
          renumber[step.step_number] = idx + 1
        end

        advisory.each(&:destroy!)

        executable.each do |step|
          rewrite_step!(step, brief, renumber: renumber)
        end

        collapse_consecutive_same_target_steps!(plan)
        # AFTER the collapse, and the ordering is load-bearing: collapse is what
        # sums duplicate counts into the single total this pass then divides.
        fan_out_regions!(plan, brief)
      end

      # Skills whose steps carry an instance count worth distributing.
      FAN_OUT_SKILLS = %w[provision_full_stack].freeze

      # Distribute a provisioning step across EVERY region the brief names
      # (IMP 019fe351-7d10).
      #
      # Placement previously collapsed to Array(regions).first with the full
      # instance count, so "dna AND rna" silently became a single-node
      # deployment. Here each provision_full_stack step becomes one step per
      # resolved region, with the count split across them.
      #
      # Siblings are APPENDED (numbered after every existing step) rather than
      # inserted. Inserting would mean shifting every later step_number and
      # rewriting every dependency pointing past the insertion — the same
      # bookkeeping that makes #merge_step_pair! hairy — for no benefit, since
      # execution is topological rather than numeric. Instead every step that
      # depended on the original gains a dependency on each sibling, so a
      # dependent still waits for ALL the provisioning it waited for before.
      #
      # Safe against the collapse pass: #mergeable? requires template_id AND
      # provider_region_id AND provider_instance_type_id to match, so per-region
      # siblings are never re-merged.
      def fan_out_regions!(plan, brief)
        regions = resolve_regions_for_brief(brief)
        return if regions.size < 2

        steps = plan.steps.reload.order(:step_number).to_a
        next_number = steps.map { |s| s.step_number.to_i }.max.to_i

        steps.each do |step|
          cfg = step.execution_config.is_a?(Hash) ? step.execution_config.deep_stringify_keys : {}
          next unless FAN_OUT_SKILLS.include?(cfg["skill"].to_s)

          inputs = cfg["inputs"] || {}
          total = (Integer(inputs["count"] || 1) rescue 1)
          shares = split_count_across(total, regions.size)
          next if shares.size < 2 # fewer instances than regions — nothing to split

          origin_number = step.step_number.to_i
          sibling_numbers = []

          first_cfg = cfg.deep_dup
          first_cfg["inputs"] = inputs.merge("count" => shares.first,
                                             "provider_region_id" => regions.first.id)
          step.update!(execution_config: first_cfg)

          shares.drop(1).each_with_index do |share, i|
            next_number += 1
            sib_cfg = cfg.deep_dup
            sib_cfg["inputs"] = inputs.merge("count" => share,
                                             "provider_region_id" => regions[i + 1].id)
            plan.steps.create!(
              step_number: next_number,
              step_type: step.step_type,
              description: step.description,
              dependencies: Array(step.dependencies).map(&:to_i),
              execution_config: sib_cfg
            )
            sibling_numbers << next_number
          end

          plan.steps.reload.each do |other|
            deps = Array(other.dependencies).map(&:to_i)
            next unless deps.include?(origin_number)
            next if sibling_numbers.include?(other.step_number.to_i)

            other.update!(dependencies: (deps + sibling_numbers).uniq)
          end

          Rails.logger.info(
            "[PlanComposerService] fanned step #{origin_number} across " \
              "#{regions.map { |r| r.region_code.presence || r.name }.inspect} as #{shares.inspect} (total #{total})"
          )
        end
      end

      # Step-collapse pass — fixes 1-instance-brief → N-step over-decomposition.
      #
      # The LLM kernel sometimes emits separate sequential steps that target
      # the exact same skill + template + region + instance type. Those should
      # be a single step with `inputs["count"]` summed, not three identical
      # provisioning steps in series.
      #
      # Algorithm: walk the persisted plan in dependency order, and for each
      # consecutive pair (A, B) where:
      #   - A.skill == B.skill
      #   - inputs.template_id / provider_region_id / provider_instance_type_id all match
      #   - B depends ONLY on A (B.dependencies == [A.step_number]) — i.e. linear chain,
      #     not a parallel branch
      # merge B into A by accumulating count, destroy B, then renumber the
      # remaining steps + repoint any dependencies onto A. Repeat until a full
      # pass produces no merges.
      def collapse_consecutive_same_target_steps!(plan)
        loop do
          steps = plan.steps.reload.order(:step_number).to_a
          merged = try_collapse_pass!(plan, steps)
          break unless merged
        end

        # Aggressive second pass — same fingerprint, ANY DAG shape.
        collapse_redundant_provisioning_clusters!(plan)
      end

      # Aggressive cluster collapse for identical-fingerprint provision_full_stack
      # steps regardless of dependency shape. The LLM often emits a redundant
      # parallel-branch DAG for what should be a single step (e.g. 8 steps with
      # the same template/region/instance_type for a 1-instance brief, branched
      # via deps=[1], deps=[1] sibling fan-out). The linear-chain mergeable?
      # check above can't fold those because each parent has multiple dependents.
      #
      # This pass groups provision_full_stack steps by fingerprint
      # (template_id + provider_region_id + provider_instance_type_id) and
      # collapses each group >1 into the earliest step. Count is capped to
      # brief.scale.initial when present so a 1-instance brief actually
      # produces a 1-instance plan even if the LLM hallucinated a tree of
      # 8 redundant steps. External dependencies that pointed at any of the
      # collapsed steps get repointed to the kept step; remaining steps are
      # renumbered to stay 1-contiguous.
      def collapse_redundant_provisioning_clusters!(plan)
        brief = extract_brief_safe
        target_count = Integer(brief&.dig("scale", "initial") || 0) rescue 0

        loop do
          steps = plan.steps.reload.order(:step_number).to_a
          pf_steps = steps.select { |s| (s.execution_config || {})["skill"] == "provision_full_stack" }

          groups = pf_steps.group_by do |s|
            inp = (s.execution_config || {})["inputs"] || {}
            [inp["template_id"], inp["provider_region_id"], inp["provider_instance_type_id"]]
          end

          duplicate_group = groups.values.find { |g| g.size > 1 }
          break unless duplicate_group

          collapse_group!(plan, duplicate_group, target_count)
        end
      end

      def collapse_group!(plan, group, target_count)
        keeper = group.first
        others = group[1..]

        # Pick the count: prefer the brief's scale.initial when set, else
        # sum the LLM-emitted counts. Floor at 1 so we never produce a no-op.
        sum = group.sum { |s| Integer(s.execution_config.dig("inputs", "count") || 1) rescue 1 }
        new_count = target_count.positive? ? target_count : sum
        new_count = 1 if new_count < 1

        cfg = (keeper.execution_config || {}).deep_dup
        cfg["inputs"] ||= {}
        cfg["inputs"]["count"] = new_count
        keeper.update!(execution_config: cfg)

        # Build remap: every collapsed step's number → keeper's number.
        remap = {}
        others.each { |o| remap[o.step_number] = keeper.step_number }
        others.each(&:destroy!)

        # Renumber remaining 1-contiguous + repoint dependencies. Drop any
        # self-loops (a step depending on itself after repointing) or
        # references to deleted step numbers.
        remaining = plan.steps.reload.order(:step_number).to_a
        renumber = {}
        remaining.each_with_index { |s, idx| renumber[s.step_number] = idx + 1 }

        remaining.each do |s|
          new_deps = Array(s.dependencies).map do |dep|
            dep = dep.to_i
            target = remap[dep] || dep
            renumber[target]
          end.compact.uniq
          new_number = renumber[s.step_number]
          new_deps.delete(new_number) # no self-loops
          s.update!(step_number: new_number, dependencies: new_deps)
        end
      end

      # Brief lookup helper that doesn't raise — used by the collapse pass
      # which runs after compose! so the brief is always present, but we
      # guard against the unlikely case of a mission whose configuration
      # was wiped between extract_brief! and rewrite_steps!.
      def extract_brief_safe
        cfg = mission.configuration
        return nil unless cfg.is_a?(Hash)
        brief = cfg["brief"] || cfg[:brief]
        brief.is_a?(Hash) ? brief : nil
      end

      def try_collapse_pass!(plan, steps)
        # Pre-compute fan-out so we don't mistakenly collapse a parent that
        # still has sibling branches depending on it.
        dependents = Hash.new { |h, k| h[k] = 0 }
        steps.each do |s|
          Array(s.dependencies).each { |d| dependents[d.to_i] += 1 }
        end

        steps.each_cons(2) do |a, b|
          next unless mergeable?(a, b, dependents)

          merge_step_pair!(plan, a, b)
          return true
        end
        false
      end

      # Two steps are mergeable when they target the same skill, the same
      # template/region/instance type, and B sits in a linear chain whose only
      # incoming edge is from A. Anything more complex (parallel branches,
      # fan-in dependencies) leaves the DAG alone — that means:
      #   - B depends only on A (not on multiple parents)
      #   - A has only one dependent (B), so merging doesn't reroute siblings
      def mergeable?(step_a, step_b, dependents)
        cfg_a = step_a.execution_config || {}
        cfg_b = step_b.execution_config || {}
        return false unless cfg_a["skill"].present? && cfg_a["skill"] == cfg_b["skill"]

        deps_b = Array(step_b.dependencies).map(&:to_i)
        return false unless deps_b == [step_a.step_number]

        # A must not also be a parent of any sibling branch — that would turn
        # the merge into "promote sibling onto a heavier-loaded A" which the
        # caller never asked for.
        return false unless dependents[step_a.step_number] == 1

        inputs_a = cfg_a["inputs"] || {}
        inputs_b = cfg_b["inputs"] || {}
        %w[template_id provider_region_id provider_instance_type_id].all? do |key|
          inputs_a[key] == inputs_b[key]
        end
      end

      def merge_step_pair!(plan, step_a, step_b)
        cfg_a = (step_a.execution_config || {}).deep_dup
        cfg_b = step_b.execution_config || {}

        inputs_a = cfg_a["inputs"] ||= {}
        count_a = Integer(inputs_a["count"] || 1) rescue 1
        count_b = Integer(cfg_b.dig("inputs", "count") || 1) rescue 1
        inputs_a["count"] = count_a + count_b

        step_a.update!(execution_config: cfg_a)

        b_number = step_b.step_number
        a_number = step_a.step_number
        step_b.destroy!

        # Renumber every step whose number is > b_number to keep the DAG
        # contiguous, and repoint any dependency that pointed at B onto A.
        plan.steps.reload.order(:step_number).each do |s|
          new_number = s.step_number > b_number ? s.step_number - 1 : s.step_number
          new_deps = Array(s.dependencies).map do |dep|
            dep = dep.to_i
            if dep == b_number
              a_number
            elsif dep > b_number
              dep - 1
            else
              dep
            end
          end.uniq

          if new_number != s.step_number || new_deps != Array(s.dependencies).map(&:to_i)
            s.update!(step_number: new_number, dependencies: new_deps)
          end
        end
      end

      def rewrite_step!(step, brief, renumber: {})
        original_config = step.execution_config.is_a?(Hash) ? step.execution_config.deep_stringify_keys : {}
        suggested = original_config["action"] || original_config["skill"] || step.description.to_s
        skill_name = map_action_to_skill(suggested) || DEFAULT_EXECUTOR

        on_failure = original_config["on_failure"]
        on_failure = "rollback" unless %w[rollback continue].include?(on_failure)

        # Strip our own envelope keys so we don't double-wrap on re-runs.
        inputs = original_config.except("skill", "action", "inputs", "on_failure")
        inputs.merge!(original_config["inputs"]) if original_config["inputs"].is_a?(Hash)
        inputs["brief"] = brief

        # Translate brief into concrete executor inputs. The LLM brief uses
        # human-readable region NAMES like "us-east-1"; the executors require
        # AR record UUIDs (template_id, provider_region_id, etc.). Resolve them
        # here so the persisted plan carries actionable IDs.
        merge_resolved_inputs!(inputs, brief, skill_name)

        # Renumber dependencies so they reference the post-pruning step
        # numbers; drop dependencies that pointed at advisory steps.
        new_deps = Array(step.dependencies).map { |dep| renumber[dep.to_i] }.compact
        new_step_number = renumber[step.step_number] || step.step_number

        step.update!(
          step_number: new_step_number,
          step_type: "provisioning_skill",
          dependencies: new_deps,
          execution_config: {
            "skill" => skill_name,
            "inputs" => inputs,
            "on_failure" => on_failure
          }
        )
      end

      # Translate a brief's human-readable values into the concrete UUIDs the
      # skill executors require. Best-effort lookups: when an exact name match
      # isn't found (e.g. brief says "us-east-1" but only a `local` region
      # exists), fall back to the account's first available record. Caches
      # within a single compose! invocation.
      #
      # `account_provider_override` (defaults to whatever resolve_provider_choice
      # picked in compose!) scopes the region+instance_type lookup to a single
      # System::Provider — that's how M2 BYOC routes a multi-provider account
      # to the operator-selected provider's catalog without leaking another
      # provider's regions in.
      def merge_resolved_inputs!(inputs, brief, skill_name, account_provider_override: @account_provider_override)
        return unless skill_name == "provision_full_stack" || skill_name == "scale_project"

        inputs["count"] ||= Integer(brief.dig("scale", "initial") || 1) rescue 1
        inputs["dry_run"] = false unless inputs.key?("dry_run")

        region = resolve_region_for_brief(brief, account_provider_override: account_provider_override)
        inputs["provider_region_id"] ||= region&.id

        instance_type = resolve_instance_type_for(region, account_provider_override: account_provider_override)
        inputs["provider_instance_type_id"] ||= instance_type&.id

        inputs["template_id"] ||= resolve_template(brief)&.id
      end

      def resolve_region_for_brief(brief, account_provider_override: nil)
        # Core mode: nil is the existing "no region resolved" shape (the
        # caller already does `region&.id`), so an early nil here needs no
        # new handling downstream.
        return nil unless defined?(::System::ProviderRegion)

        @region_cache ||= {}
        all_wanted = Array(brief["regions"] || brief[:regions]).map { |r| r.to_s.strip }.reject(&:empty?)
        wanted = all_wanted.first.to_s

        # This returns the FIRST region only, and that is now correct rather
        # than a silent narrowing: #merge_resolved_inputs! uses it to stamp an
        # initial provider_region_id, and #fan_out_regions! afterwards splits
        # the step across every region the brief names (IMP 019fe351-7d10).
        # The "only the first region is honoured" warning that used to live here
        # was removed with that change — it would now assert the extra regions
        # are dropped while the fan-out pass provisions them.

        cache_key = [account_provider_override&.id, wanted]
        return @region_cache[cache_key] if @region_cache.key?(cache_key)

        scope = ::System::ProviderRegion.where(account_id: account.id)
        scope = scope.where(provider_id: account_provider_override.id) if account_provider_override

        # Match region_code as well as name (IMP 019fe1e0-0b8a). region_code is
        # the canonical identifier — for Proxmox the adapter's own doc states
        # "regions model PVE nodes, so region_code IS the node name" — and a
        # brief or operator naturally writes that, not the display name. Matching
        # on name alone left a region findable only by a string nobody uses.
        match = wanted.empty? ? nil : match_region(scope, wanted)

        # The fallback stays — a sloppy region string should not hard-fail
        # composition — but it must not be SILENT. Landing on an arbitrary
        # region is a real placement decision the operator never made, and on a
        # multi-node cluster it is a wrong-node deployment that reads normal in
        # the plan. Warn only when there was an intent to contradict.
        if match.nil? && !wanted.empty?
          Rails.logger.warn(
            "[PlanComposerService] no region matching #{wanted.inspect} for account=#{account&.id} " \
              "(known: #{scope.map { |r| r.region_code.presence || r.name }.inspect}); " \
              "falling back to #{(scope.first&.region_code || scope.first&.name).inspect} — " \
              "placement will NOT be where the brief asked."
          )
        end

        @region_cache[cache_key] = match || scope.first
      end

      def resolve_instance_type_for(region, account_provider_override: nil)
        # Core mode: same nil-tolerant shape as #resolve_region_for_brief above
        # (caller already does `instance_type&.id`).
        return nil unless defined?(::System::ProviderInstanceType)

        @instance_type_cache ||= {}
        provider_id = region&.provider_id || account_provider_override&.id
        cache_key = provider_id
        return @instance_type_cache[cache_key] if @instance_type_cache.key?(cache_key)

        scope = ::System::ProviderInstanceType.where(account_id: account.id)
        scope = scope.where(provider_id: provider_id) if provider_id
        scope = scope.where(enabled: true) if scope.respond_to?(:where) && ::System::ProviderInstanceType.column_names.include?("enabled")
        # Prefer cheapest by hourly_price when present, else any
        ordered = scope.respond_to?(:order) ? scope.order(Arel.sql("hourly_price NULLS LAST")) : scope
        @instance_type_cache[cache_key] = ordered.first || ::System::ProviderInstanceType.where(account_id: account.id).first
      end

      # Core mode (IMP-589e181531a1): System::NodeTemplate is unavailable
      # with the extension absent. Guarding here rather than at each call
      # site is the more honest fix — nothing downstream can do anything real
      # without a template either way — and both existing callers already
      # tolerate nil (merge_resolved_inputs!'s `resolve_default_template&.id`,
      # attach_role_module_to_template!'s `return unless template`). The
      # latter is load-bearing: it's what keeps the sibling
      # ::System::NodeModule lookup in #attach_role_module_to_template!
      # unreached in core mode, without needing its own separate guard.
      # Match one brief region string against a scope of System::ProviderRegion.
      # region_code first — it is the canonical identifier (for Proxmox the
      # adapter states "regions model PVE nodes, so region_code IS the node
      # name") — then display name. Case- and whitespace-insensitive.
      def match_region(scope, wanted)
        needle = wanted.to_s.strip.downcase
        return nil if needle.empty?

        scope.detect { |r| r.region_code.to_s.downcase == needle || r.name.to_s.downcase == needle }
      end

      # EVERY region the brief names, resolved and de-duplicated, in brief order
      # (IMP 019fe351-7d10). Unlike #resolve_region_for_brief this does NOT fall
      # back to an arbitrary region: a name that resolves to nothing is skipped
      # and warned about, because substituting a region the operator never named
      # is exactly the silent misplacement this work exists to remove.
      def resolve_regions_for_brief(brief, account_provider_override: @account_provider_override)
        return [] unless defined?(::System::ProviderRegion)

        wanted = Array(brief["regions"] || brief[:regions]).map { |r| r.to_s.strip }.reject(&:empty?)
        return [] if wanted.empty?

        scope = ::System::ProviderRegion.where(account_id: account.id)
        scope = scope.where(provider_id: account_provider_override.id) if account_provider_override
        scope = scope.to_a

        resolved = wanted.filter_map do |name|
          match_region(scope, name).tap do |m|
            next if m

            Rails.logger.warn(
              "[PlanComposerService] brief region #{name.inspect} matches no region for " \
                "account=#{account&.id} (known: #{scope.map { |r| r.region_code.presence || r.name }.inspect}); " \
                "it will NOT be provisioned."
            )
          end
        end
        resolved.uniq(&:id)
      end

      # Split `total` instances across `n` regions, remainder to the earliest.
      # Never emits a zero share: with fewer instances than regions the caller
      # gets FEWER steps rather than steps that provision nothing.
      #   (4,2) => [2,2]   (3,2) => [2,1]   (5,3) => [2,2,1]   (1,3) => [1]
      def split_count_across(total, n)
        total = total.to_i
        n = n.to_i
        return [] if total <= 0 || n <= 0

        n = total if n > total
        base = total / n
        rem  = total % n
        Array.new(n) { |i| base + (i < rem ? 1 : 0) }
      end

      # The template the plan will actually provision from: the brief's
      # preferred_template when it resolves, else the oldest-template default
      # (IMP 019fe3a7-266d — the default alone picked ops-hub's "base", blank
      # boot_mode => cloud_init => no agent, while the step prose named the
      # right template; run 20260808a F3).
      def resolve_template(brief)
        resolve_template_for_brief(brief) || resolve_default_template
      end

      # Resolve the brief's preferred_template by NAME or id, case-insensitively.
      # Falls back to nil — loudly. Substituting a template the operator never
      # named is a real boot-mode decision they didn't make; the gate label
      # (plan_snapshot template_label) is what makes the fallback visible.
      def resolve_template_for_brief(brief)
        return nil unless defined?(::System::NodeTemplate)

        wanted = (brief["preferred_template"] || brief[:preferred_template]).to_s.strip
        return nil if wanted.empty?

        @template_cache ||= {}
        return @template_cache[wanted] if @template_cache.key?(wanted)

        needle = wanted.downcase
        scope = ::System::NodeTemplate.where(account_id: account.id).to_a
        match = scope.detect { |t| t.name.to_s.downcase == needle || t.id.to_s.downcase == needle }
        unless match
          Rails.logger.warn(
            "[PlanComposerService] brief preferred_template #{wanted.inspect} matches no template " \
              "for account=#{account&.id} (known: #{scope.map(&:name).inspect}); " \
              "falling back to the default template."
          )
        end
        @template_cache[wanted] = match
      end

      def resolve_default_template
        return nil unless defined?(::System::NodeTemplate)

        @default_template ||= ::System::NodeTemplate.where(account_id: account.id).order(created_at: :asc).first
      end

      # ----- M3 "Run My Code" helpers ---------------------------------------

      # Returns the role-module name (a `System::NodeModule#name`) for this
      # brief, or nil when the operator's runtime_hint explicitly maps to
      # "no module yet" (Slice A hasn't seeded a Ruby runtime, etc.).
      def role_module_name_for(brief)
        hint = brief["runtime_hint"].to_s.strip.downcase
        if hint.present? && RUNTIME_HINT_TO_MODULE.key?(hint)
          # Authoritative — even nil here means "operator explicitly named
          # an unsupported runtime; skip attachment".
          return RUNTIME_HINT_TO_MODULE[hint]
        end

        use_case = brief["use_case"].to_s.strip.downcase
        return ROLE_MODULE_FOR_USE_CASE[use_case] if ROLE_MODULE_FOR_USE_CASE.key?(use_case)

        DEFAULT_ROLE_MODULE
      end

      # Attach the resolved role module to the chosen NodeTemplate. Best-effort:
      # if Slice A hasn't seeded the named module yet, log and skip rather
      # than fail the whole compose. Idempotent via find_or_create_by!.
      def attach_role_module_to_template!(brief)
        # The CHOSEN template — attaching the workload module to the default
        # while provisioning from the brief's template would configure a
        # template the plan never uses.
        template = resolve_template(brief)
        return unless template

        module_name = role_module_name_for(brief)
        return if module_name.blank?

        node_module = ::System::NodeModule
                        .where(account_id: account.id)
                        .where("LOWER(name) = ?", module_name.downcase)
                        .first
        unless node_module
          Rails.logger.info(
            "[PlanComposerService] Role module '#{module_name}' not seeded for " \
              "account=#{account.id}; skipping template attachment"
          )
          return
        end

        return unless composition_allows?(template, node_module)

        ::System::TemplateModule.find_or_create_by!(
          node_template: template,
          node_module: node_module
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        Rails.logger.warn(
          "[PlanComposerService] Failed to attach role module '#{role_module_name_for(brief)}' " \
            "to template for account=#{account.id}: #{e.message}"
        )
      end

      # Every other System::TemplateModule writer runs the assignment through
      # System::TemplateCompositionAnalysis before creating the join and
      # refuses an addition that introduces an error-severity conflict (a
      # declared Conflicts: relation, or a second instance-variety module in
      # one category). This writer created the join unchecked, and it is the
      # one that can do the most damage: it always targets the account's
      # DEFAULT template, and additions_verdict diffs against a template's
      # CURRENT closure — so a collision landed here becomes permanent
      # baseline that every later assignment is then obliged to accept, and
      # TemplateExpansionService ships it to real nodes.
      #
      # Calling the extension's analysis directly is the sanctioned seam, not
      # a boundary break: core-purity bars core from naming a PRIVATE
      # extension, `system` is public, and this method is already unable to do
      # anything without it (NodeTemplate, NodeModule and TemplateModule are
      # all System::). The `defined?` guard is the same core-mode seam used by
      # cost_estimator_service.rb and topology_renderer_service.rb. Reusing the
      # analysis rather than reimplementing the rules core-side is deliberate:
      # the conflict vocabulary is extension domain knowledge and a core copy
      # would drift from the definition the other four writers enforce.
      #
      # Refusal is a SKIP, not a raise: attachment is best-effort by contract
      # (an unseeded role module is already logged and skipped), and the
      # mission plan is not the thing in conflict.
      def composition_allows?(template, node_module)
        unless defined?(::System::TemplateCompositionAnalysis)
          # Fail CLOSED. Skipping costs one module attachment; proceeding
          # unchecked is exactly the write this guard exists to prevent.
          Rails.logger.warn(
            "[PlanComposerService] Composition analysis unavailable; skipping role-module " \
              "attachment for account=#{account.id} rather than writing unchecked"
          )
          return false
        end

        verdict = ::System::TemplateCompositionAnalysis
                    .new(account)
                    .assignment_verdict(template: template, node_module: node_module)
        return true unless verdict.blocked?

        Rails.logger.warn(
          "[PlanComposerService] Refused role-module attachment for account=#{account.id}: " \
            "#{verdict.message}"
        )
        false
      rescue StandardError => e
        # The analysis resolves a dependency closure over catalog data this
        # service does not own, so it must not be able to take the mission
        # compose down with it — the attachment is best-effort, the plan is
        # not. Fail closed for the same reason as the branch above: an
        # unanswerable question is not permission to write unchecked.
        Rails.logger.warn(
          "[PlanComposerService] Composition analysis failed for account=#{account.id}; " \
            "skipping role-module attachment: #{e.class}: #{e.message}"
        )
        false
      end

      # Append a `deploy_app_code` step that depends on the last
      # `provision_full_stack` step in the plan. node_instance_id is filled
      # in at runtime by the runner from upstream step outputs — at compose
      # time the provision step hasn't executed yet.
      def append_deploy_app_code_step!(plan, brief)
        steps = plan.steps.reload.order(:step_number).to_a
        last_provision = steps.reverse.find do |s|
          (s.execution_config || {})["skill"].to_s == "provision_full_stack"
        end

        unless last_provision
          Rails.logger.warn(
            "[PlanComposerService] Mission #{mission.id}: brief carries repo_url " \
              "but plan has no provision_full_stack step; skipping deploy_app_code"
          )
          return
        end

        next_number = (steps.map(&:step_number).max || 0) + 1

        plan.steps.create!(
          step_number: next_number,
          step_type: "provisioning_skill",
          description: "Deploy #{brief['repo_url']} onto provisioned instance",
          dependencies: [last_provision.step_number],
          execution_config: {
            "skill" => "deploy_app_code",
            "inputs" => {
              "repo_url" => brief["repo_url"],
              "branch" => brief["branch"].presence || "main",
              "start_command" => brief["start_command"],
              "mission_id" => mission.id,
              "brief" => brief
            },
            # node_instance_id is unknown at compose time — the runner resolves
            # it at runtime from the upstream provision_full_stack step's
            # outputs (data.outputs.node_instance_ids, first instance).
            "depends_on_outputs" => {
              "node_instance_id" => {
                "from_step" => last_provision.step_number,
                "path" => "outputs.node_instance_ids",
                "select" => "first"
              }
            },
            "on_failure" => "rollback"
          }
        )
      end

      def map_action_to_skill(action)
        text = action.to_s
        return nil if text.strip.empty?

        if defined?(Ai::Tools::SemanticToolDiscoveryService)
          semantic = semantic_lookup(text)
          return semantic if semantic
        end

        STATIC_ACTION_MAP.each do |pattern, skill|
          return skill if text.match?(pattern)
        end
        nil
      end

      def semantic_lookup(query)
        discovery = Ai::Tools::SemanticToolDiscoveryService.new(account: account)
        results = discovery.discover(query: query, limit: 5)
        Array(results).each do |r|
          name = (r[:name] || r["name"]).to_s
          return name if ALLOWED_EXECUTORS.include?(name)
        end
        nil
      rescue StandardError => e
        Rails.logger.warn("[PlanComposerService] Semantic discovery failed: #{e.message}")
        nil
      end

      # ----- Cycle detection (mirrors GoalDecompositionService#has_dependency_cycle?)
      # Duplicated rather than monkey-patched to keep the dependency clean and
      # avoid mutating the plan as `validate` does there.
      def has_dependency_cycle?(plan)
        adjacency = plan.steps.each_with_object({}) do |step, h|
          h[step.step_number] = Array(step.dependencies).map(&:to_i)
        end

        visited = {}
        in_stack = {}
        adjacency.each_key do |node|
          return true if dfs_cycle?(node, adjacency, visited, in_stack)
        end
        false
      end

      def dfs_cycle?(node, adjacency, visited, in_stack)
        return false if visited[node]
        return true if in_stack[node]

        in_stack[node] = true
        Array(adjacency[node]).each do |dep|
          return true if dfs_cycle?(dep, adjacency, visited, in_stack)
        end
        in_stack[node] = false
        visited[node] = true
        false
      end
    end
  end
end
