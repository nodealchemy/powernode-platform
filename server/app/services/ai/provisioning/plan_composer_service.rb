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

      # The NodeTemplate config key that declares which SDWAN network the
      # template's instances join (IMP-cdc1d0703e5a). Aliased from
      # Shared::SdwanNetworkResolution rather than restated, so the stamping in
      # #merge_resolved_inputs!, the compose-time check, the
      # `provision_prerequisites` extension seam, and the direct provisioning
      # resolver all read ONE definition (IMP-8e1ac4a09e82) — a plain data key
      # travelling through that seam, not a reference to the extension.
      #
      # The opt-out sentinel is deliberately NOT aliased alongside it: with the
      # bucketing moved to Shared::, nothing in this class reads it, and a
      # second name for a value whose whole purpose is one shared vocabulary is
      # how the two resolvers drifted apart to begin with.
      NETWORK_CONFIG_KEY = ::Shared::SdwanNetworkResolution::NETWORK_CONFIG_KEY

      # The skills whose composed inputs are RESOLVED FROM THE TEMPLATE —
      # template_id, region, instance type, and the three-arm `network_id`.
      # #merge_resolved_inputs!'s own gate, named rather than inlined so the
      # set has one definition.
      #
      # IMP-1fc00ac8547a: this is a NAME LIST, and a name list cannot say when
      # it is incomplete. `provision_cluster` is the standing example — it is
      # in ALLOWED_EXECUTORS, STATIC_ACTION_MAP matches any brief saying
      # "cluster", and its executor DECLARES the same four inputs
      # `provision_full_stack` does (template_id, count, provider_region_id,
      # provider_instance_type_id) — yet it is absent here, so a step naming
      # it composes with NONE of them.
      #
      # It is deliberately NOT added. Membership here is not free: the
      # fan-out pass (FAN_OUT_SKILLS), the redundant-cluster collapse and
      # #wire_docker_provision_steps! all key on `provision_full_stack` by
      # name, so a normalized-but-unfanned `provision_cluster` step would
      # stop failing loudly at dispatch and start silently landing the whole
      # count in one region, merging with its twin into double the instances,
      # and leaving a docker leg unwired — real resources, quietly wrong,
      # which is worse than the missing-input failure it replaces. Adding it
      # is its own change, with those three passes.
      #
      # #record_unnormalized_inputs! is the backstop that makes the gap
      # visible in the meantime: it reads each composed step's DECLARED
      # requirements and reports any this list should have covered, so an
      # omission is loud rather than latent.
      TEMPLATE_RESOLVING_SKILLS = %w[provision_full_stack scale_project].freeze

      # The input keys #merge_resolved_inputs! knows how to resolve. Must
      # track the stamping in that method — it is the "could the composer have
      # supplied this?" half of #record_unnormalized_inputs!, and a key the
      # composer cannot resolve is never that method's business to report.
      #
      # Deliberately NOT derived by reflection: the stamping is a sequence of
      # `||=` against differently-shaped resolvers, not a table, and a scan
      # that inferred these names would report whatever the parser happened to
      # match rather than what the method actually resolves.
      NORMALIZED_INPUT_KEYS = %w[
        count
        dry_run
        provider_region_id
        provider_instance_type_id
        template_id
        network_id
        with_storage_gb
        mission_id
        name_prefix
      ].freeze

      # The skills that CREATE INSTANCES FROM A NODE TEMPLATE, and therefore
      # take their fabric membership from that template's `sdwan_network_id`
      # declaration (IMP-883a1f6f89d0). This is what #check_network_declaration
      # scopes on, and it is deliberately NOT the same set as the one above.
      #
      # The tempting shortcut is "whatever #merge_resolved_inputs! stamps",
      # since stamping is how a composed plan usually carries the fabric. But
      # stamping is not the only way an instance joins one: provision_cluster
      # takes an explicit template_id and creates its nodes through the fleet
      # tool, and the extension's provision-time resolver reads the TEMPLATE's
      # config for each node — no stamped network_id is involved. Gating on the
      # stamp would have gone silent on exactly the plan shape nothing else
      # catches: the prerequisite seam only speaks for overlay-REQUIRING skills
      # (docker_provision), and at run time a broken declaration on that path is
      # an error log on the substrate, not an operator-visible failure.
      #
      # So the two sets answer two different questions and the overlap is a
      # coincidence of the current skill catalog, not an invariant. Any new
      # executor that stands up instances from a template belongs here whether
      # or not the composer stamps its inputs.
      TEMPLATE_PROVISIONING_SKILLS = %w[provision_full_stack scale_project provision_cluster].freeze

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

        # Deterministic synthesis for RECOGNIZED provisioning scenarios
        # (IMP 019fe7f0; subsumes the F-1 runtime-leg guard IMP 019fe76e and
        # the docker dedup IMP 019fe7e0). The brief fully determines the plan
        # — scale.initial, regions, preferred template/provider, runtime
        # demand — yet the LLM decomposition produced a differently broken
        # DAG for the SAME brief on consecutive runs (dryrun c–f: 0 docker
        # steps, then 6 for 3 instances, then 18 instances for a 3-instance
        # brief). Synthesizing from the brief removes the variance at the
        # root instead of patching one dimension of it per incident.
        #
        # Gated on the SAME predicate ComposerRouter routes with, so the
        # synthesis triggers on exactly the recognized set; every production
        # entry point reaches this service through that router. The LLM
        # decompose + rewrite pipeline below stays as the fallback for
        # direct instantiation with an unrecognized brief, and its passes
        # still serve compact_existing_plan! on cached plans.
        if ::Ai::Missions::ComposerRouter.deterministic_provisioning?(brief)
          plan = synthesize_plan!(goal, brief)
        else
          plan = decompose_goal!(goal)
          return plan unless plan

          rewrite_steps!(plan, brief)
        end

        # Compose-time prerequisite validation (IMP 019fe647): the rewritten
        # plan's skills are final here, so ask the extension whether they can
        # actually run against the chosen template (e.g. docker_provision
        # needs an SDWAN overlay). Issues surface as the SAME clarification
        # shape resolve_provider_choice uses — every caller already renders
        # it — instead of runtime step failures the review gate never saw
        # coming. NOTE: the un-persisted plan is deliberately abandoned here;
        # no pointer is written, so a corrected retry recomposes fresh.
        # IMP-cdc1d0703e5a: a template that DECLARES a network but supplies an
        # unusable value would silently compose bare compute. Checked here, next
        # to the prerequisite seam and before any pointer is persisted, so the
        # un-persisted plan is abandoned the same way (a corrected retry
        # recomposes fresh). Runs first because its diagnosis is the specific
        # one — the seam would report the generic "no network resolves"
        # for the same template, and only when the plan has an overlay-requiring
        # skill at all. IMP-94728a788498: also covers the account-default arm —
        # a configured default that could never resolve fails loud here too.
        # IMP-883a1f6f89d0: takes the composed PLAN, because "would this plan
        # provision against that template" is a question about the plan, not
        # about the brief — see #check_network_declaration.
        network_clarification = check_network_declaration(brief, plan)
        return network_clarification if network_clarification

        # IMP-94728a788498: the checker receives the composer's OWN three-arm
        # resolution (template explicit → account default → networkless), so
        # writer and checker agree by construction — the checker must not
        # recompute the resolution from the template alone and disagree.
        prereq_clarification = check_plan_prerequisites(
          skills: plan.steps.reload.filter_map { |s| (s.execution_config || {})["skill"].presence },
          template_id: resolve_template(brief)&.id,
          network_id: resolved_network_id(resolve_template(brief))
        )
        return prereq_clarification if prereq_clarification

        attach_role_module_to_template!(brief)
        append_deploy_app_code_step!(plan, brief) if brief["repo_url"].present?

        # IMP-1fc00ac8547a: the plan's steps are final here — including the
        # appended deploy_app_code leg — so this is the only point at which
        # "did every composed step get the inputs it declares?" can be asked
        # of the whole plan. Records rather than refuses; see the method.
        record_unnormalized_inputs!(plan)

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

        # IMP-1fc00ac8547a: this is the operator-facing READ path — every
        # deep-link view of a cached plan lands here — and it is the only
        # place plans composed BEFORE the audit existed can be seen. Auditing
        # on compose alone would leave exactly those plans silent forever.
        # Idempotent: re-stamping an already-stamped step writes the same
        # hash.
        record_unnormalized_inputs!(plan)
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

      # ----- Deterministic synthesis (recognized provisioning scenarios) ----
      #
      # Build the plan the brief specifies — nothing more, nothing less:
      #
      #   * provision_full_stack steps whose counts sum to scale.initial,
      #     split across every region the brief names (remainder to the
      #     earliest, never a zero share; no/unresolvable regions → one
      #     full-count step on the existing fallback resolution),
      #   * when the brief demands container-runtime work, one wired
      #     docker_provision step PER INSTANCE, depending only on its own
      #     provision step (the same shape wire_docker_provision_steps!
      #     repairs LLM output into).
      #
      # The run-d/e/f defect classes are impossible by construction here:
      # counts sum to the brief's total, the runtime leg exists iff demanded,
      # and there is no independent docker step-set to duplicate.
      def synthesize_plan!(goal, brief)
        plan = create_synthesized_plan!(goal)

        regions = resolve_regions_for_brief(brief)
        total = begin
          Integer(brief.dig("scale", "initial") || 1)
        rescue ArgumentError, TypeError
          1
        end
        total = 1 if total < 1

        shares = regions.empty? ? [total] : split_count_across(total, regions.size)

        provision_steps = shares.each_with_index.map do |share, idx|
          inputs = { "count" => share }
          inputs["provider_region_id"] = regions[idx].id if regions[idx]
          inputs["brief"] = brief
          merge_resolved_inputs!(inputs, brief, "provision_full_stack")

          plan.steps.create!(
            step_number: idx + 1,
            step_type: "provisioning_skill",
            description: synthesized_provision_description(brief, regions[idx], share),
            dependencies: [],
            execution_config: { "skill" => "provision_full_stack", "inputs" => inputs,
                                "on_failure" => "rollback" }
          )
        end

        synthesize_docker_legs!(plan, brief, provision_steps)
        plan
      end

      def create_synthesized_plan!(goal)
        latest_version = Ai::GoalPlan.for_goal(goal.id).maximum(:version) || 0
        Ai::GoalPlan.create!(
          account: account,
          goal: goal,
          agent: goal.agent,
          status: "draft",
          version: latest_version + 1,
          plan_data: { "composer" => "deterministic_synthesis" }
        )
      end

      def synthesized_provision_description(brief, region, share)
        target = brief["use_case"].presence || brief["intent"].presence || "workload"
        where = region ? " in #{region.region_code.presence || region.name}" : ""
        "Provision #{share} instance(s)#{where} for: #{target.to_s.truncate(120)}"
      end

      # One docker_provision step per instance, wired via the runner's
      # cross-step mechanism and depending only on its own provision step —
      # so one region's docker failure neither blocks nor implicates the
      # other's leg. Numbered after every provision step.
      def synthesize_docker_legs!(plan, brief, provision_steps)
        return unless brief_demands_runtime?(brief)

        next_number = provision_steps.map { |s| s.step_number.to_i }.max.to_i
        targets = provision_steps.flat_map do |p|
          count = (p.execution_config.dig("inputs", "count") || 1).to_i
          Array.new([count, 1].max) { |idx| [p, idx] }
        end

        targets.each_with_index do |(p, idx), i|
          next_number += 1
          plan.steps.create!(
            step_number: next_number,
            step_type: "provisioning_skill",
            description: "Docker provision · instance #{i + 1} of #{targets.size}",
            dependencies: [p.step_number.to_i],
            execution_config: {
              "skill" => "docker_provision",
              "inputs" => { "brief" => brief },
              "depends_on_outputs" => {
                "node_instance_id" => {
                  "from_step" => p.step_number.to_i,
                  "path" => "outputs.node_instance_ids",
                  "select" => idx
                }
              },
              "on_failure" => "rollback"
            }
          )
        end
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
        # AFTER the fan-out and BEFORE the wiring: append the runtime leg the
        # decomposition nondeterministically omits, so the wiring pass fans +
        # wires an appended step exactly as it would an LLM-emitted one.
        ensure_runtime_leg!(plan, brief)
        # AFTER the fan-out — docker wiring maps onto the FINAL provision-step
        # layout (per-region siblings included), not the pre-split step.
        wire_docker_provision_steps!(plan)
      end

      # Brief signals that the operator's stated intent includes container-
      # runtime work. Deliberately narrow: an explicit runtime_hint of docker,
      # or docker/container language in the use_case/intent the extractor
      # carried over verbatim.
      RUNTIME_LEG_SIGNALS = /\b(docker|containers?[- ]?|container-runtime)/i

      # Deterministic decomposition-completeness pass (F-1, IMP 019fe76e-6a43).
      # Run 20260809c's decomposition emitted docker_provision steps; run
      # 20260809d's — identical objective, use case naming 'the
      # container-runtime handshake' — emitted none, and the handshake leg
      # simply didn't exist. Whether a requirement the brief STATES appears in
      # the plan is not the LLM's decision (same closed-set philosophy as
      # IMP-019fe47a): when the brief demands runtime work and the plan has no
      # docker step, append one depending on every provision step;
      # #wire_docker_provision_steps! then fans it per-instance.
      def ensure_runtime_leg!(plan, brief)
        return unless brief_demands_runtime?(brief)

        steps = plan.steps.reload.to_a
        return if steps.any? { |s| (s.execution_config || {})["skill"].to_s == "docker_provision" }

        provision_numbers = steps
                            .select { |s| FAN_OUT_SKILLS.include?((s.execution_config || {})["skill"].to_s) }
                            .map { |s| s.step_number.to_i }
        if provision_numbers.empty?
          Rails.logger.warn(
            "[PlanComposerService] brief demands container-runtime work but the plan has " \
              "no provision step to hang a docker leg on; leaving the plan as decomposed"
          )
          return
        end

        next_number = steps.map { |s| s.step_number.to_i }.max.to_i + 1
        plan.steps.create!(
          step_number: next_number,
          step_type: "provisioning_skill",
          description: "Docker provision",
          dependencies: provision_numbers,
          execution_config: { "skill" => "docker_provision", "inputs" => {},
                              "on_failure" => "rollback" }
        )
        Rails.logger.info(
          "[PlanComposerService] decomposition omitted the runtime leg the brief demands — " \
            "appended docker_provision step #{next_number} (deps #{provision_numbers.inspect})"
        )
      end

      def brief_demands_runtime?(brief)
        return false unless brief.is_a?(Hash)
        return true if brief["runtime_hint"].to_s.casecmp?("docker")

        [ brief["use_case"], brief["intent"] ].any? { |t| t.to_s.match?(RUNTIME_LEG_SIGNALS) }
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

      # Compose-time prerequisite check via the `provision_prerequisites`
      # extension seam (IMP 019fe647). Returns a clarification Hash when the
      # checker reports issues, nil otherwise. Core mode (no checker) is a
      # no-op, and a BROKEN checker fails OPEN with a warning — prerequisite
      # advice must never be the thing that blocks all composition.
      # `network_id` is the composer's resolved three-arm answer
      # (IMP-94728a788498) — nil means "nothing resolves for this plan".
      # An older checker without the kwarg raises ArgumentError, which the
      # rescue below already treats as fail-open (a mismatched half-deploy
      # degrades to no compose-time validation, never to a hard block).
      def check_plan_prerequisites(skills:, template_id:, network_id: nil)
        checker = ::Powernode::ExtensionRegistry.provider(:provision_prerequisites)
        return nil unless checker

        issues = Array(checker.check(account: account, template_id: template_id,
                                     skills: Array(skills).uniq,
                                     network_id: network_id))
        return nil if issues.empty?

        Rails.logger.warn(
          "[PlanComposerService] compose-time prerequisites unmet for mission=#{mission&.id}: " \
            "#{issues.inspect[0, 400]}"
        )
        {
          clarification_needed: true,
          message: "This plan has unmet prerequisites: #{issues.join('; ')}",
          prerequisite_issues: issues
        }
      rescue StandardError => e
        Rails.logger.warn(
          "[PlanComposerService] prerequisite check failed (#{e.class}: #{e.message[0, 150]}); " \
            "proceeding without compose-time validation"
        )
        nil
      end

      # Wire docker_provision steps to the instances their predecessors will
      # create (F-a, IMP 019fe5d6-f429). The LLM decomposition emits ONE
      # docker step depending on the provision steps, with no inputs — but
      # DockerProvisionExecutor takes a single node_instance_id, and instance
      # ids do not exist at compose time. Observed live (dryrun 20260809b):
      # the unwired step raised 'missing required input: node_instance_id' and
      # the handshake leg never ran.
      #
      # Rewrite: each unwired docker step becomes ONE STEP PER INSTANCE —
      # for every provision step with count k, k docker siblings wired via the
      # runner's cross-step mechanism (`depends_on_outputs`, integer `select`
      # indexing into that step's outputs.node_instance_ids) and depending
      # ONLY on their own provision step, so one region's docker failure
      # neither blocks nor implicates the other's leg. Mirrors the fan-out
      # pattern: first sibling reuses the original row, downstream dependents
      # are repointed onto all siblings.
      # Keep at most ONE unwired docker_provision step (IMP 019fe7e0). Extra
      # ones the decomposition emitted are redundant — the fan produces one
      # docker step per instance from a single template. Already-wired docker
      # steps (explicit id / depends_on_outputs) are deliberate and untouched;
      # downstream dependents are repointed off any dropped step onto the
      # survivor so the DAG stays connected.
      def collapse_redundant_docker_steps!(plan)
        unwired = plan.steps.reload.order(:step_number).select do |s|
          cfg = s.execution_config.is_a?(Hash) ? s.execution_config : {}
          cfg["skill"].to_s == "docker_provision" &&
            cfg["depends_on_outputs"].blank? &&
            (cfg["inputs"] || {})["node_instance_id"].blank?
        end
        return if unwired.size < 2

        survivor = unwired.first
        redundant = unwired.drop(1)
        redundant_numbers = redundant.map { |s| s.step_number.to_i }

        plan.steps.reload.each do |other|
          deps = Array(other.dependencies).map(&:to_i)
          next if (deps & redundant_numbers).empty?

          repointed = deps.map { |d| redundant_numbers.include?(d) ? survivor.step_number.to_i : d }
          other.update!(dependencies: repointed.uniq) unless other.id == survivor.id
        end
        redundant.each(&:destroy!)
        Rails.logger.info(
          "[PlanComposerService] collapsed #{redundant.size} redundant docker_provision step(s) " \
            "into ##{survivor.step_number} before fan-out (IMP 019fe7e0)"
        )
      end

      def wire_docker_provision_steps!(plan)
        # Collapse redundant unwired docker steps FIRST (IMP 019fe7e0):
        # the LLM decomposition sometimes emits more than one docker_provision
        # step, and fanning each independently produced N-docker × M-instance
        # duplicates (dryrun-20260809e: 2 emitted × 3 instances = 6 steps,
        # every instance covered twice). One unwired docker step is all the
        # fan needs — it produces exactly one per provisioned instance.
        collapse_redundant_docker_steps!(plan)

        steps = plan.steps.reload.order(:step_number).to_a
        provision_steps = steps.select do |s|
          FAN_OUT_SKILLS.include?((s.execution_config || {})["skill"].to_s)
        end
        next_number = steps.map { |s| s.step_number.to_i }.max.to_i

        steps.each do |step|
          cfg = step.execution_config.is_a?(Hash) ? step.execution_config.deep_stringify_keys : {}
          next unless cfg["skill"].to_s == "docker_provision"
          # Already wired (an explicit id or an existing mapping is a
          # deliberate compose-time choice) — leave it alone.
          next if cfg["depends_on_outputs"].present?
          next if (cfg["inputs"] || {})["node_instance_id"].present?

          if provision_steps.empty?
            Rails.logger.warn(
              "[PlanComposerService] docker_provision step #{step.step_number} has no provision step " \
                "to wire node_instance_id from; leaving it unwired"
            )
            next
          end

          origin_number = step.step_number.to_i
          targets = provision_steps.flat_map do |p|
            count = (Integer((p.execution_config.dig("inputs", "count") || 1)) rescue 1)
            Array.new([ count, 1 ].max) { |idx| [ p, idx ] }
          end

          sibling_numbers = []
          targets.each_with_index do |(p, idx), i|
            sib_cfg = cfg.deep_dup
            sib_cfg["depends_on_outputs"] = {
              "node_instance_id" => {
                "from_step" => p.step_number.to_i,
                "path" => "outputs.node_instance_ids",
                "select" => idx
              }
            }
            description = "#{step.description.presence || 'Docker provision'} · instance #{i + 1} of #{targets.size}"

            if i.zero?
              step.update!(description: description,
                           dependencies: [ p.step_number.to_i ],
                           execution_config: sib_cfg)
            else
              next_number += 1
              plan.steps.create!(
                step_number: next_number,
                step_type: step.step_type,
                description: description,
                dependencies: [ p.step_number.to_i ],
                execution_config: sib_cfg
              )
              sibling_numbers << next_number
            end
          end

          plan.steps.reload.each do |other|
            deps = Array(other.dependencies).map(&:to_i)
            next unless deps.include?(origin_number)
            next if sibling_numbers.include?(other.step_number.to_i)
            next if other.id == step.id

            other.update!(dependencies: (deps + sibling_numbers).uniq)
          end

          Rails.logger.info(
            "[PlanComposerService] wired docker_provision step #{origin_number} into " \
              "#{targets.size} per-instance step(s) across provision steps " \
              "#{provision_steps.map(&:step_number).inspect}"
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
        return unless TEMPLATE_RESOLVING_SKILLS.include?(skill_name.to_s)

        inputs["count"] ||= Integer(brief.dig("scale", "initial") || 1) rescue 1
        inputs["dry_run"] = false unless inputs.key?("dry_run")

        region = resolve_region_for_brief(brief, account_provider_override: account_provider_override)
        inputs["provider_region_id"] ||= region&.id

        instance_type = resolve_instance_type_for(region, account_provider_override: account_provider_override)
        inputs["provider_instance_type_id"] ||= instance_type&.id

        template = resolve_template(brief)
        inputs["template_id"] ||= template&.id

        # IMP-975976497370: the fabric comes from the template THIS STEP will
        # provision from, which is not always the brief's.
        #
        # The `||=` above deliberately preserves a template_id the step already
        # carried, and #rewrite_step! merges an LLM decomposition's own `inputs`
        # hash in before calling this — so a decomposition emitting
        # `inputs: { template_id: X }` reaches here with X pinned while the brief
        # names Y. Reading the declaration off Y then placed the instance on a
        # network its own template never declared. (Not reachable on the
        # deterministic path: #synthesize_plan! builds `inputs` fresh per step,
        # so template_id is always nil there and the two resolutions agree.)
        #
        # Correct-by-construction rather than skip-on-disagreement: refusing to
        # stamp when they differ would silently compose bare compute, which is
        # the exact degradation IMP-cdc1d0703e5a removed.
        effective_template = template_for_step(inputs["template_id"], brief_template: template)

        # IMP-cdc1d0703e5a: fabric + storage footprint. Without these two keys
        # every composed provision/scale-out arrived as BARE COMPUTE — no SDWAN
        # peer, no volume — even though the actuator side is fully built
        # (ProvisionFullStackExecutor enrolls a peer per instance for
        # `network_id` and provisions a per-instance volume for
        # `with_storage_gb`; ScaleProjectExecutor#run_provision threads both
        # onward and reports the ids). It also made
        # AdaptationProposerService::FOOTPRINT_KEYS — which already lists both
        # and carries them from the original plan onto a composed scale-out —
        # inert, because the source plan never held the keys.
        #
        # Both use ||= deliberately: an explicitly-authored input (a
        # hand-written plan_data, MissionComposer output, an operator-supplied
        # value) must always win, which also makes this a pure add with nothing
        # to backfill.
        # IMP-94728a788498: three-arm resolution — template explicit →
        # account default → networkless. See #resolved_network_id.
        network_id = resolved_network_id(effective_template)
        inputs["network_id"] ||= network_id if network_id

        # No NodeTemplate storage key exists and nothing else on the platform
        # declares a volume size, so the honest writer is the operator's own
        # utterance: IntentCaptureService captures `storage_gb` on the brief.
        # Inventing a template key with no writer would produce a field that is
        # correct in shape and inert in production.
        # RULING (IMP-b439270dab0d): the step's OWN declaration outranks the
        # brief, which is what the paragraph above always claimed — "an
        # explicitly-authored input ... must always win" — and what the code
        # did not do. `||=` only protected the ADVERTISED key, so a step
        # carrying the alias (storage_gb: 500) had the brief's value stamped
        # over the advertised key, and the published read order then let the
        # brief beat the step's own explicit declaration.
        #
        # Reading through the shared resolver also brings present? semantics
        # here: a blank `with_storage_gb: ""` falls through to the step's alias
        # rather than blocking the stamp, and an explicit 0 stays 0 because 0
        # is present — a legitimate "no storage" the brief must not overwrite.
        declared = ::Shared::StorageSizeResolution.from_inputs(inputs)
        declared = brief_storage_gb(brief) if declared.blank?
        inputs["with_storage_gb"] = declared if declared.present?

        # F3 (IMP 019fe4c4-e813): naming provenance. The charter's dryrun-
        # prefix never reached the substrate — VMs came out template-named
        # and prefix-targeted teardown/audit missed every artifact. Thread
        # the mission's marker into the executor (which prefixes node names,
        # from which instance names derive) and stamp mission_id so created
        # nodes/instances are provenance-queryable regardless of naming.
        inputs["mission_id"] ||= mission&.id
        prefix = provenance_name_prefix
        inputs["name_prefix"] ||= prefix if prefix
      end

      # Report composed steps that DECLARE an input the normalization above
      # could have resolved, and did not get it (IMP-1fc00ac8547a).
      #
      # THE DEFECT THIS EXISTS FOR IS SILENCE, not the missing value.
      # #merge_resolved_inputs! gates on a name list, so a skill added to the
      # composer's reachable set and not to that list composes with none of
      # its declared inputs and nothing says so — the step simply dies at
      # dispatch, one layer away from the decision that broke it.
      # `provision_cluster` is in exactly that state (see
      # TEMPLATE_RESOLVING_SKILLS), and a deterministic composer for
      # `relocate_workload` (offer 019ff49b-a8e5) would arrive the same way:
      # correct-looking in isolation, missing keys nobody remembers are
      # stamped elsewhere.
      #
      # Requirements come from the executor's DECLARED descriptor, read
      # through SkillCompositionRunner's slug->executor seam — the same
      # resolution dispatch uses, and the same one AdaptationProposerService
      # checks bindability with. Core names no executor, and a newly added
      # skill is covered the moment it declares its inputs.
      #
      # RECORDS, deliberately, rather than raising or refusing the compose:
      #
      #   * A raise would abort the whole compose from a private helper. Both
      #     production callers (Internal::Ai::ProvisioningController and
      #     Ai::Missions::PlanCompositionActions) treat a raise as a failed
      #     composition, so one step's missing template_id would destroy a
      #     plan whose remaining steps are entirely correct.
      #   * Refusing via the `clarification_needed` shape the two neighbouring
      #     checks return would make this a GATE. It is a diagnostic: it fires
      #     on plans that are already broken at dispatch (BaseSkillExecutor
      #     raises "missing required input" on nil, the runner fails the step
      #     and rolls back), and converting an existing dispatch-time failure
      #     into a compose-time refusal changes what callers render for plans
      #     that compose today. That is a separate decision from making the
      #     omission visible, which is what this task is.
      #   * #validate_plan, the other candidate sink, has NO production caller.
      #     Recording there would be visible only to specs, which is the inert
      #     half of "loud".
      #
      # So: an operator sees `Rails.logger.error`, and the omission is stamped
      # onto the step, which PlanSnapshotService serves on the plan DAG the
      # operator's plan-review surface reads.
      #
      # A key wired through `depends_on_outputs` is SUPPLIED, not omitted —
      # docker_provision's and deploy_app_code's `node_instance_id` cannot
      # exist at compose time by construction. Unresolvable requirements (nil,
      # not []) mean "cannot tell what this needs", which is core mode with no
      # executors loaded; reporting there would fire on every step of every
      # plan in a supported configuration.
      #
      # Presence is judged by DISPATCH's oracle — BaseSkillExecutor rejects an
      # input only when it is nil — so a legitimately blank or zero value is
      # not reported as missing.
      def record_unnormalized_inputs!(plan)
        plan.steps.reload.each do |step|
          # Per step, so one unreadable row cannot blind the audit for the
          # rest of the plan.
          begin
            cfg = step.execution_config.is_a?(Hash) ? step.execution_config.deep_stringify_keys : {}
            skill = cfg["skill"].to_s
            next if skill.empty?

            required = ::Ai::Provisioning::SkillCompositionRunner.required_inputs_for(skill)
            next if required.nil?

            inputs = cfg["inputs"].is_a?(Hash) ? cfg["inputs"] : {}
            wired = cfg["depends_on_outputs"].is_a?(Hash) ? cfg["depends_on_outputs"].keys.map(&:to_s) : []

            omitted = (required.map(&:to_s) & NORMALIZED_INPUT_KEYS) - wired
            omitted = omitted.reject { |key| inputs.key?(key) && !inputs[key].nil? }
            next if omitted.empty?

            # Two different causes, and naming the wrong one costs the
            # diagnostic its meaning: a skill this method knows is off the
            # allowlist was never normalized at all, while one ON the
            # allowlist was normalized and the resolver simply found no
            # record (an account with no templates/regions — core mode).
            cause = if TEMPLATE_RESOLVING_SKILLS.include?(skill)
                      "normalization ran for #{skill} but resolved no record for them"
                    else
                      "#{skill} is not in TEMPLATE_RESOLVING_SKILLS, so normalization never ran"
                    end
            Rails.logger.error(
              "[PlanComposerService] step #{step.step_number} (#{skill}) composed without " \
                "#{omitted.join(', ')} — the skill declares these required and the composer " \
                "resolves them; #{cause} (mission=#{mission&.id}, plan=#{plan.id})"
            )
            step.update!(execution_config: cfg.merge("unnormalized_inputs" => omitted))
          rescue StandardError => e
            # Never let a diagnostic be the thing that breaks composition.
            Rails.logger.warn(
              "[PlanComposerService] normalization audit failed for step " \
                "#{step.step_number} (#{e.class}: #{e.message[0, 150]})"
            )
          end
        end
      end

      # What the chosen template says about fabric attachment, as
      # `[state, value]` where state is :absent, :opt_out, :usable or :unusable.
      #
      # This reads exactly the key the compose-time prerequisite checker reads
      # (`NodeTemplate.config["sdwan_network_id"]`), so the composer and that
      # checker agree BY CONSTRUCTION rather than by two components computing
      # the same thing two different ways.
      #
      # The :absent/:opt_out/:unusable split is the whole design decision (see
      # #check_network_declaration). A template that says NOTHING about
      # a network has no opinion — with IMP-94728a788498 that now falls through
      # to the ACCOUNT default rather than straight to networkless; a template
      # that DECLARES the key and supplies something that could never be an id
      # asked for fabric and did not get it.
      #
      # The bucketing ITSELF — why a null/blank key is :absent rather than an
      # opt-out or a failure, why `false` stays :absent, why the "none"
      # sentinel exists — is documented once on Shared::SdwanNetworkResolution
      # and deliberately not restated here (IMP-8e1ac4a09e82). Two copies of
      # that rationale, one per resolver, is the drift this extraction removes.
      #
      # Composer-specific: a :usable id is NOT existence-checked. Core cannot
      # check existence without naming the extension, and it does not need to —
      # ProvisionFullStackExecutor fails the whole step with "sdwan network not
      # found" before provisioning anything, so a dead id is already loud, just
      # at run time rather than compose time. For plans whose skills REQUIRE an
      # overlay the `provision_prerequisites` seam catches it at compose time
      # as well.
      #
      # Core purity: a plain Hash read off a record core already resolved via
      # #resolve_template — no new `System::`/`Sdwan::` constant reference.
      def template_network_declaration(template)
        ::Shared::SdwanNetworkResolution.classify_config(template&.config)
      end

      # What the ACCOUNT says about default fabric attachment
      # (IMP-94728a788498), as the same `[state, value]` shape. Reads
      # `Account#default_sdwan_network_setting` — DB-driven config
      # (Account#settings jsonb), settable through the existing
      # account-settings surface; no env var, seed, or hardcoded id.
      #
      # Identical bucketing to the template arm, from the same classifier —
      # the semantics live on Shared::SdwanNetworkResolution, not here.
      # Composer-specific: :opt_out on THIS arm means "explicitly no default"
      # and resolves like :absent (there is no further arm for it to beat),
      # and :unusable fails LOUD at compose time when the resolution actually
      # reaches this arm — a configured default that could never resolve,
      # silently composing bare compute, is the exact defect class this arm
      # exists to avoid reintroducing.
      def account_network_default
        ::Shared::SdwanNetworkResolution.classify_account_default(account)
      end

      # Three-arm resolution (IMP-94728a788498): template explicit → account
      # default → networkless. Returns the network id to stamp, or nil for a
      # networkless plan. The template's :opt_out beats the default; the
      # template's :unusable resolves to nil here because compose! has
      # already failed loud on it (#check_network_declaration runs first),
      # and an :unusable account default likewise never reaches stamping.
      # The template a step actually provisions from: its own pinned
      # template_id when it has one, else the brief's (IMP-975976497370).
      #
      # ONE definition, used by both the stamping in #merge_resolved_inputs! and
      # the compose-time gate in #check_network_declaration — the two must agree
      # about which record they are reading, and two hand-written resolutions is
      # how they stop agreeing.
      #
      # Guarded on `defined?` and account-scoped like the other resolvers, so
      # core mode (no system extension) and a cross-account id both fall back to
      # the brief's template rather than raising.
      def template_for_step(template_id, brief_template:)
        id = template_id.to_s
        return brief_template if id.empty? || id == brief_template&.id.to_s
        return brief_template unless defined?(::System::NodeTemplate)

        @step_template_cache ||= {}
        @step_template_cache[id] ||=
          ::System::NodeTemplate.find_by(account_id: account.id, id: id) || brief_template
      end

      def resolved_network_id(template)
        state, network_id = template_network_declaration(template)
        return network_id if state == :usable
        return nil unless state == :absent

        account_state, account_value = account_network_default
        account_state == :usable ? account_value : nil
      end

      # The per-instance volume size the operator asked for, as a positive
      # Integer, or nil. Tolerates string/symbol keys and a stringified size
      # (a hand-authored plan_data supplies either).
      #
      # `to_i` deliberately, NOT `Integer()`: IntentCaptureService normalises
      # this same field with `to_i`, and a reader that parses more strictly
      # than its writer is the seam mismatch this whole task is about — a
      # brief carrying "50.7" would satisfy the writer and silently resolve to
      # NO VOLUME here, which is precisely the silent degradation being fixed.
      #
      # Non-positive is treated as "no volume" rather than passed through. This
      # was once the ONLY screen — the executor guarded on `blank?`, which does
      # not screen a 0 — and it is now the first of three that agree
      # (IMP-33fa6c51f05d added ProvisionFullStackExecutor#storage_requested?;
      # CostEstimatorService#declared_gb clamps the same way for the quote).
      # Note this screens what the composer ADDS: `merge_resolved_inputs!` uses
      # `||=` and 0 is truthy in Ruby, so a hand-authored non-positive already
      # on the step survives composition — which is why the executor needs its
      # own guard and does not merely inherit this one.
      def brief_storage_gb(brief)
        return nil unless brief.is_a?(Hash)

        raw = brief["storage_gb"] || brief[:storage_gb]
        return nil if raw.blank?
        return nil unless raw.respond_to?(:to_i)

        value = raw.to_i
        value if value.positive?
      end

      # THE DESIGN DECISION (IMP-cdc1d0703e5a), stated once here because the
      # silent default it replaces is what produced the defect this method
      # exists to close.
      #
      # Networkless missions stay LEGAL AND SILENT. A brief whose template
      # declares no network composes bare compute with no noise — that is a
      # real, supported topology (core mode and the local_qemu path both run it,
      # and a workload with no container-runtime leg legitimately needs no
      # fabric peer), so warning about it would train operators to ignore the
      # warning.
      #
      # But a template that DECLARES `sdwan_network_id` and supplies a value
      # that could never be an id asked for the fabric and would silently get
      # bare compute — plan rows that read completely normal at the review gate,
      # which is exactly how the original defect survived. That fails LOUD at
      # compose time, via the same clarification shape #resolve_provider_choice
      # and #check_plan_prerequisites already use (every caller renders it).
      #
      # Deliberately NOT a hard failure for "no network resolved at all": that
      # would block every pure-compute provision on an account with no SDWAN
      # network. The narrow, skill-aware prerequisite seam stays authoritative
      # for "this plan's skills REQUIRE an overlay"; this only catches the
      # misconfigurations that seam cannot see, because it fires regardless of
      # which skills the plan contains.
      #
      # IMP-94728a788498 extends the same decision to the ACCOUNT arm: when
      # the template has no opinion and the resolution falls through to the
      # account default, a configured default that could never be an id fails
      # LOUD here too — but ONLY when the default is actually the resolving
      # arm. A template that decided for itself (:usable or :opt_out) never
      # consults the default, and letting a broken account setting block those
      # plans would turn one bad key into an account-wide provisioning outage.
      #
      # Writers: `NodeTemplate.config[NETWORK_CONFIG_KEY]` is operator-supplied
      # via `system_create_template` / `system_update_template`; the account
      # default is operator-supplied via the account-settings surface
      # (Account::DEFAULT_SDWAN_NETWORK_SETTING). With the account arm, fabric
      # membership is now the account's default posture — a single DB-driven
      # setting covers every template an operator has not individually
      # configured.
      # IMP-883a1f6f89d0 scopes all of the above TO THE PLAN. The check used to
      # run unconditionally, so one template carrying a broken declaration
      # failed EVERY compose on the account — including plans that provision
      # nothing (a runbook, a CVE triage, an attribution) and would never have
      # consulted a network declaration. That is the account-wide provisioning
      # outage the account arm above already refuses to cause, arriving by the
      # other door.
      #
      # The narrower condition was already written down two comments up, at the
      # call site: the prerequisite seam reports its generic failure "only when
      # the plan has an overlay-requiring skill at all". Core cannot ask which
      # skills require an overlay — that is the extension's knowledge — but it
      # does not need to. It can ask the strictly-prior question it owns
      # outright: does this plan stand up instances from a node template at all?
      # See TEMPLATE_PROVISIONING_SKILLS for why that is deliberately NOT the
      # same set as "whatever #merge_resolved_inputs! stamps" — provision_cluster
      # provisions from the template without a stamped network_id, and gating on
      # the stamp would go silent on the one shape nothing else catches.
      #
      # Ordering note (why the plan is available here and this is not merely
      # moved): compose! has already synthesized or decomposed-and-rewritten the
      # plan by this point — its steps are persisted and carry their final
      # skills, which is what the next block reads for the prerequisite seam.
      # Nothing after this call adds a template-provisioning step either
      # (#attach_role_module_to_template! attaches a module,
      # #append_deploy_app_code_step! appends a deploy_app_code step), so the
      # answer here is the final one.
      #
      # NARROWED TO THE STEPS' OWN TEMPLATES (IMP-975976497370). This comment
      # used to say the opposite — that matching on a step's template_id "would
      # disagree with the writer, which is the failure mode this whole design
      # keeps refusing". That reasoning was sound and its premise is now false:
      # the writer (#merge_resolved_inputs!) resolves the STEP's template too,
      # so reading the brief's here is what would disagree with it. The gate and
      # the stamp share one resolver (#template_for_step) rather than two
      # hand-written rules, because a gate that validates a record no step will
      # use can both miss a real misconfiguration and fail loud about a template
      # nothing provisions from.
      def check_network_declaration(brief, plan)
        return nil unless plan_provisions_from_template?(plan)

        step_templates(brief, plan).each do |template|
          issue = network_declaration_issue(template)
          return issue if issue
        end

        nil
      end

      # The distinct templates this plan's template-provisioning steps will
      # actually provision from. A step that pins none inherits the brief's, so
      # a plan whose steps are all unpinned yields exactly what the old
      # brief-only check read.
      def step_templates(brief, plan)
        brief_template = resolve_template(brief)

        ids = plan.steps.filter_map do |step|
          cfg = step.execution_config
          next unless cfg.is_a?(Hash)
          next unless TEMPLATE_PROVISIONING_SKILLS.include?((cfg["skill"] || cfg[:skill]).to_s)

          inputs = cfg["inputs"] || cfg[:inputs]
          inputs.is_a?(Hash) ? (inputs["template_id"] || inputs[:template_id]) : nil
        end

        return [ brief_template ].compact if ids.empty?

        ids.uniq
           .map { |id| template_for_step(id, brief_template: brief_template) }
           .compact.uniq
      end

      def network_declaration_issue(template)
        state, raw = template_network_declaration(template)

        case state
        when :unusable
          Rails.logger.warn(
            "[PlanComposerService] template #{template.name.inspect} declares #{NETWORK_CONFIG_KEY} " \
              "as #{raw.inspect[0, 120]}, which is not a usable network id (mission=#{mission&.id}); " \
              "refusing to compose bare compute for a plan that asked for the fabric."
          )
          {
            clarification_needed: true,
            message: "Template #{template.name.inspect} declares #{NETWORK_CONFIG_KEY}, but its value " \
                     "is not a usable network id, so every instance this plan provisions would come up " \
                     "with no SDWAN peer. Set a valid #{NETWORK_CONFIG_KEY} on the template, or remove " \
                     "the key entirely to provision bare compute deliberately.",
            network_declaration_issue: {
              template_id: template.id,
              template_name: template.name,
              key: NETWORK_CONFIG_KEY
            }
          }
        when :absent
          account_state, account_raw = account_network_default
          return nil unless account_state == :unusable

          Rails.logger.warn(
            "[PlanComposerService] account #{account&.id} configures " \
              "#{::Account::DEFAULT_SDWAN_NETWORK_SETTING} as #{account_raw.inspect[0, 120]}, " \
              "which is not a usable network id (mission=#{mission&.id}); refusing to compose " \
              "bare compute for a plan that would resolve its network from the account default."
          )
          {
            clarification_needed: true,
            message: "This account configures #{::Account::DEFAULT_SDWAN_NETWORK_SETTING}, but its " \
                     "value is not a usable network id, so every instance this plan provisions would " \
                     "come up with no SDWAN peer. Set a valid #{::Account::DEFAULT_SDWAN_NETWORK_SETTING} " \
                     "in the account settings, or remove it to provision bare compute deliberately.",
            network_declaration_issue: {
              key: ::Account::DEFAULT_SDWAN_NETWORK_SETTING,
              scope: "account"
            }
          }
        end
      end

      # Does this plan contain a step that stands up instances from a node
      # template, and therefore takes their fabric membership from the
      # declaration under check (IMP-883a1f6f89d0)?
      #
      # Reads the persisted steps rather than the brief: the brief's shape does
      # not decide which executors the plan ended up with (the LLM fallback maps
      # actions to skills, and the collapse/fan-out/runtime-leg passes add and
      # remove steps), and by this point the steps are final.
      def plan_provisions_from_template?(plan)
        plan.steps.reload.any? do |step|
          cfg = step.execution_config
          next false unless cfg.is_a?(Hash)

          TEMPLATE_PROVISIONING_SKILLS.include?((cfg["skill"] || cfg[:skill]).to_s)
        end
      end

      # Explicit configuration.name_prefix wins; a dryrun run id derives the
      # charter's blast-radius prefix; anything else means no prefix opinion.
      # The derivation lives on the mission (`Ai::Mission#provenance_name_prefix`)
      # because a scale-in reads the SAME marker to decide what it is allowed
      # to terminate — see that method for why there must be exactly one copy.
      def provenance_name_prefix
        mission&.provenance_name_prefix
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
