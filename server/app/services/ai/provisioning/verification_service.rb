# frozen_string_literal: true

module Ai
  module Provisioning
    # Phase-4 verification for infrastructure missions (F2, IMP 019fe4c4-c7c4).
    #
    # Replaces the M2 stub that marked every mission healthy. Observed live
    # (dryrun 20260809a): the stub blessed — in 0.23s — a plan whose rna step
    # had recorded a provisioning failure and whose "running" instance was a
    # phantom the provider had never seen. Presence in the DB is never proof;
    # the protocol's infrastructure-truth oracle is live provider state.
    #
    # Checks, in three layers:
    #   1. PLAN   — the mission references a composed plan at all.
    #   2. STEPS  — every executed step is `completed`, recorded NO failures
    #      in `metadata.last_outputs.failures` (the executor records partial
    #      failures there and still returns success — see
    #      ProvisionFullStackExecutor), and produced exactly the instances it
    #      was asked for (inputs.count vs outputs.node_instance_ids).
    #   3. LIVE   — every produced instance is reconciled against the live
    #      provider through the `provision_verifier` extension seam: the row
    #      exists, carries provider identity, the provider reports it running,
    #      and it sits in the region the step declared. Core mode has no
    #      provider substrate; the absence is REPORTED in the checks rather
    #      than silently skipped, so a reader can tell "verified" from
    #      "unverifiable".
    #
    # Returns { healthy: Boolean, checks: [{ name:, ok:, detail: }, ...] }.
    # The caller (internal verify endpoint) fails the phase on unhealthy —
    # verification that cannot block is theater.
    class VerificationService
      def initialize(account:, mission:)
        @account = account
        @mission = mission
      end

      def verify
        plan = resolve_plan
        unless plan
          return result([ check("plan", false, "mission has no composed plan to verify") ])
        end

        checks = []
        expectations = []
        steps = plan.steps.order(:step_number).to_a
        removed = removed_instance_ids(steps)

        steps.each do |step|
          cfg = step.execution_config.is_a?(Hash) ? step.execution_config.deep_stringify_keys : {}
          next if cfg["skill"].blank?

          outs = last_outputs(step)
          prefix = "step_#{step.step_number}"

          checks << check("#{prefix}_status", step.status.to_s == "completed",
                          "status=#{step.status}")

          failures = Array(outs["failures"])
          checks << check("#{prefix}_failures", failures.empty?,
                          failures.empty? ? "no recorded failures" : "recorded failures: #{failures.inspect[0, 300]}")

          if removal_scaling?(step_inputs(cfg))
            checks << removal_check(prefix, outs, step_inputs(cfg))
            next
          end

          ids = Array(outs.dig("outputs", "node_instance_ids")).map(&:to_s)
          expected = declared_instance_count(cfg)
          if expected.positive? || ids.any?
            checks << check("#{prefix}_count", ids.size == expected,
                            "provisioned #{ids.size}/#{expected} instances")
            region_id = cfg.dig("inputs", "provider_region_id")
            live = ids.reject { |id| removed.include?(id) }
            live.each { |id| expectations << { node_instance_id: id, provider_region_id: region_id } }
          end
        end

        checks.concat(reconcile(expectations))
        checks.concat(reconcile_absent(removed.to_a))
        result(checks)
      end

      private

      def resolve_plan
        plan_id = @mission&.configuration&.dig("plan", "plan_id")
        return nil if plan_id.blank?

        ::Ai::GoalPlan.find_by(id: plan_id)
      end

      # How many instances the step ASKED for.
      #
      # `count` is what the initial provisioning skill declares. An adaptation
      # is APPENDED onto this same live plan (IMP-8c37b9e5ccd5), so the re-run
      # walks its steps too — and a `scale_project` step declares its instances
      # as `target_count`, the delta of NEW instances, which is exactly what
      # lands in `outputs.node_instance_ids`. Reading only `count` scored every
      # post-adapt re-run "provisioned 2/0 instances" and failed a mission whose
      # scale-out had in fact succeeded.
      #
      # Never take this from the OUTPUTS side (the executor also reports a
      # `count` there): verification compares what was asked against what was
      # produced, and sourcing both from the executor is self-certification.
      #
      # The fallback is scoped to ADDITIVE scaling. `target_count` means
      # "instances to create" only for an additive strategy; the scaling skill's
      # other arms (a vertical resize, a rolling upgrade) still take a
      # target_count but create nothing and return an empty node_instance_ids,
      # so an unscoped fallback would expect N and see 0 — failing that step,
      # and therefore the mission, permanently and unfixably.
      def declared_instance_count(cfg)
        inputs = step_inputs(cfg)
        declared = inputs["count"]
        if declared.blank? && additive_scaling?(inputs)
          declared = inputs["target_count"]
        end
        declared.to_i
      end

      def step_inputs(cfg)
        cfg["inputs"].is_a?(Hash) ? cfg["inputs"] : {}
      end

      def additive_scaling?(inputs)
        inputs["scaling_strategy"].to_s ==
          ::Ai::Provisioning::AdaptationProposerService::SCALE_OUT_STRATEGY
      end

      def removal_scaling?(inputs)
        inputs["scaling_strategy"].to_s ==
          ::Ai::Provisioning::AdaptationProposerService::REMOVAL_STRATEGY
      end

      # A removal's success is that the victims are GONE — with their peers,
      # membership mirrors and volumes — never that N instances exist.
      #
      # Grading it with the creation oracle above would fail `step_N_count`
      # PERMANENTLY (a removal returns an empty node_instance_ids by
      # construction), the mission would verify unhealthy forever, and since
      # the adaptation lane settles on verification, every later adaptation on
      # that mission could never settle. One removal would poison the whole
      # evolution loop, so the branch is explicit rather than emergent from
      # "expected == 0 and no ids".
      #
      # The oracle is the executor's post-teardown ground-truth sweep, recorded
      # as `outputs.orphans`: it re-reads the peer / volume / instance rows
      # after the teardown instead of trusting that the teardown returned
      # success. Empty means the zero-orphan invariant held.
      def removal_check(prefix, outs, inputs)
        outputs = outs["outputs"].is_a?(Hash) ? outs["outputs"] : {}
        removed = Array(outputs["removed_node_instance_ids"])
        floor_reached = outputs["floor_reached"] == true
        rail = outputs["prefix_enforced"]

        detail = "removed #{removed.size} instance(s), " \
                 "#{Array(outputs['detached_sdwan_peer_ids']).size} peer(s), " \
                 "#{Array(outputs['deleted_storage_volume_ids']).size} volume(s); " \
                 "prefix rail #{rail.present? ? "enforced (#{rail})" : 'NOT MEASURED (mission declares none)'}"
        detail += "; at floor" if floor_reached

        # Absence of a sweep is not a clean sweep. `Array(nil)` is empty, so a
        # step whose outputs never carried the key reads exactly like one that
        # swept and found nothing — the opposite of the fail-closed rule
        # #reconcile applies to a reconciler that cannot answer.
        unless outputs.key?("orphans")
          return check("#{prefix}_removal", false, "#{detail}; no orphan sweep recorded — unverifiable")
        end

        orphans = Array(outputs["orphans"])
        if orphans.any?
          return check("#{prefix}_removal", false, "#{detail}; ORPHANS: #{orphans.inspect[0, 300]}")
        end

        # A removal that removed nothing is only healthy when the floor is why.
        # Otherwise the step asked for capacity to go away and none did, which
        # no orphan list would ever show.
        if removed.empty? && !floor_reached && inputs["target_count"].to_i.positive?
          return check("#{prefix}_removal", false,
                       "#{detail}; asked to remove #{inputs['target_count']} and removed none, " \
                       "with no floor to explain it")
        end

        check("#{prefix}_removal", true, detail)
      end

      # Instances a removal step took out, across the whole plan.
      #
      # A victim was recorded by the step that CREATED it, and those ids are
      # what reach the live reconciler. Left in, a SUCCESSFUL scale-in makes
      # the reconciler report a terminated instance as not-running — so the
      # mission verifies unhealthy forever, blamed on the creating step rather
      # than the removing one. Collected up front because the removal step
      # comes after the step whose expectations it invalidates.
      def removed_instance_ids(steps)
        steps.flat_map { |step|
          outs = last_outputs(step)
          Array(outs.dig("outputs", "removed_node_instance_ids"))
        }.map(&:to_s).to_set
      end

      def last_outputs(step)
        meta = step.metadata.is_a?(Hash) ? step.metadata : {}
        out = meta["last_outputs"] || meta[:last_outputs] || {}
        out.is_a?(Hash) ? out.deep_stringify_keys : {}
      end

      def reconcile(expectations)
        return [] if expectations.empty?

        reconciler = ::Powernode::ExtensionRegistry.provider(:provision_verifier)
        unless reconciler
          # Core mode: no provider substrate to ask. Healthy-but-annotated —
          # a reader must be able to tell "verified" from "unverifiable".
          return [ check("live_reconciliation", true,
                         "no provision_verifier registered (core mode) — " \
                         "#{expectations.size} instance(s) not live-verified") ]
        end

        Array(reconciler.reconcile_instances(account: @account, expectations: expectations)).map do |r|
          r = r.is_a?(Hash) ? r : {}
          check("instance_#{r[:node_instance_id] || r['node_instance_id']}",
                r[:ok].nil? ? r["ok"] == true : r[:ok] == true,
                (r[:detail] || r["detail"]).to_s)
        end
      rescue StandardError => e
        # A reconciler that cannot answer must not bless (fail-closed) — the
        # whole point is that silence and health are different things.
        [ check("live_reconciliation", false, "reconciler error: #{e.class}: #{e.message[0, 200]}") ]
      end

      # The other half of the removal oracle: the victims' absence, confirmed
      # against the live provider rather than taken from the executor that
      # reported removing them. A row marked terminated over a guest the
      # hypervisor still runs is the F2 phantom inverted — invisible to the
      # platform, alive on the bill — and self-certification is exactly what
      # #reconcile exists to refuse.
      #
      # A verifier that answers presence but not absence is treated the way
      # core mode is: healthy, and SAID to be unverified. Failing there would
      # make every removal unhealthy on any deployment whose extension module
      # is a version behind core's, which is the routine state during a
      # rolling platform deploy.
      def reconcile_absent(ids)
        return [] if ids.empty?

        reconciler = ::Powernode::ExtensionRegistry.provider(:provision_verifier)
        unless reconciler.respond_to?(:reconcile_absent_instances)
          return [ check("removal_reconciliation", true,
                         "verifier cannot check absence — #{ids.size} removed instance(s) " \
                         "not live-verified") ]
        end

        expectations = ids.map { |id| { node_instance_id: id } }
        Array(reconciler.reconcile_absent_instances(account: @account, expectations: expectations)).map do |r|
          r = r.is_a?(Hash) ? r : {}
          check("removed_instance_#{r[:node_instance_id] || r['node_instance_id']}",
                r[:ok].nil? ? r["ok"] == true : r[:ok] == true,
                (r[:detail] || r["detail"]).to_s)
        end
      rescue StandardError => e
        [ check("removal_reconciliation", false, "reconciler error: #{e.class}: #{e.message[0, 200]}") ]
      end

      def check(name, ok, detail)
        { name: name, ok: ok == true, detail: detail }
      end

      def result(checks)
        { healthy: checks.all? { |c| c[:ok] }, checks: checks }
      end
    end
  end
end
