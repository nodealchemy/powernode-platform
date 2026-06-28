# frozen_string_literal: true

require "open3"

module Ai
  module Deploy
    # The deploy safety envelope. Given a landed change (or an explicit target+ref) it runs:
    #   kill-switch  → resolve target+method → migration-safety gate → record DeployRun →
    #   method.deploy!(dry_run) → post-deploy health → auto-rollback on failure → audit.
    #
    # dry_run defaults to TRUE: a REAL deploy requires explicit opt-in (deploy config
    # auto_deploy:true / dry_run:false), so the safe default is to DESCRIBE the deploy
    # (the exact commands a method would run) without performing it. Every phase is audited.
    class Orchestrator
      def initialize(account:, user: nil, repository_path: nil)
        @account = account
        @user = user
        @repository_path = repository_path || default_repository_path
      end

      # Deploy for a fully-landed CampaignLand. Target/method/opt-in come from the land's
      # metadata["deploy"] merged over its campaign's configuration["deploy"]. Returns the
      # DeployRun. dry_run: nil → derive from opt-in config (default dry-run).
      def deploy_for_land(land, dry_run: nil)
        target = target_for_land(land)
        ref = land.try(:merged_sha).presence || land.try(:staged_sha).presence
        dry = dry_run.nil? ? !real_deploy_opted_in?(land) : dry_run
        deploy(target: target, ref: ref, base_ref: currently_deployed_ref,
               campaign: land.try(:campaign), campaign_land: land, dry_run: dry,
               allow_irreversible: deploy_config(land)["allow_irreversible"] == true)
      end

      # Core entry: deploy `ref` to `target`. Returns the Ai::DeployRun.
      def deploy(target:, ref:, base_ref: nil, campaign: nil, campaign_land: nil,
                 dry_run: true, allow_irreversible: false)
        method_class = Ai::Deploy::MethodRegistry.resolve(target)
        run = Ai::DeployRun.create!(
          account: @account, campaign: campaign, campaign_land: campaign_land,
          repository: target.repository, triggered_by: @user,
          target_kind: target.kind.to_s, environment: target.environment,
          method_key: (method_class&.key || "unresolved").to_s,
          ref: ref, base_ref: base_ref, dry_run: dry_run, status: "pending"
        )

        # 1. Kill-switch — never deploy while AI is suspended.
        if halted?
          run.skip!("kill-switch active (account ai_suspended)")
          return audited(run, "deploy.skipped")
        end

        # 2. Method must resolve.
        unless method_class
          run.block!("no available deploy method for #{target.label} (#{target.environment})")
          return audited(run, "deploy.blocked")
        end

        # 3. Migration-safety gate (when both refs + a repo are known).
        if base_ref.present? && ref.present? &&
           (report = migration_safety(base_ref, ref, allow_irreversible)) && !report.safe?
          run.block!("migration-safety: #{report.reasons.join('; ')}", "migration_safety" => report.to_h)
          return audited(run, "deploy.blocked")
        end

        # 4. Execute (or, in dry-run, describe).
        run.start!
        audit("deploy.initiated", run)
        method = method_class.new(account: @account, user: @user)
        result = method.deploy!(target: target, ref: ref, dry_run: dry_run)
        run.finish!(result)

        # 5. Post-deploy health + auto-rollback (real, succeeded deploys only).
        if result.succeeded? && !dry_run
          health = safe_health(method, target, run)
          unless health.succeeded?
            audit("deploy.unhealthy", run)
            rollback = safe_rollback(method, target, run)
            healed = rollback.rolled_back? || rollback.succeeded?
            run.mark_rolled_back!("post-deploy health failed: #{health.detail}",
                                  "health" => health.to_h, "rollback" => rollback.to_h) if healed
            run.fail!("post-deploy health failed + rollback failed: #{health.detail}",
                      "health" => health.to_h, "rollback" => rollback.to_h) unless healed
            return audited(run, healed ? "deploy.rolled_back" : "deploy.failed")
          end
        end

        audited(run, outcome_action(result))
      end

      private

      attr_reader :account, :user

      def halted?
        @account.respond_to?(:ai_suspended?) && @account.ai_suspended?
      end

      def migration_safety(base, target_ref, allow_irreversible)
        return nil unless @repository_path && Dir.exist?(@repository_path)

        Ai::Deploy::MigrationSafetyChecker
          .new(repository_path: @repository_path)
          .check(base_ref: base, target_ref: target_ref, allow_irreversible: allow_irreversible)
      rescue StandardError => e
        Rails.logger.warn("[Deploy::Orchestrator] migration-safety check failed: #{e.message}")
        nil
      end

      def safe_health(method, target, run)
        method.verify_health(target: target, deploy_run: run)
      rescue StandardError => e
        Ai::Deploy::Result.failure("health check raised: #{e.message}")
      end

      def safe_rollback(method, target, run)
        method.rollback!(target: target, deploy_run: run)
      rescue StandardError => e
        Ai::Deploy::Result.failure("rollback raised: #{e.message}")
      end

      def outcome_action(result)
        case result.status
        when :succeeded then "deploy.succeeded"
        when :dry_run then "deploy.dry_run"
        when :failed then "deploy.failed"
        when :skipped then "deploy.skipped"
        else "deploy.completed"
        end
      end

      def audited(run, action)
        audit(action, run)
        run
      end

      def audit(action, run)
        return unless defined?(::AuditLog)

        ::AuditLog.log_action(action: action, resource: run, account: @account, user: @user,
                              new_values: run.summary)
      rescue StandardError => e
        Rails.logger.warn("[Deploy::Orchestrator] audit #{action} failed: #{e.message}")
      end

      # ---- land → target/config resolution ----
      def target_for_land(land)
        cfg = deploy_config(land)
        repo = land.try(:repository)
        if repo && cfg["target"].to_s != "platform_self"
          Ai::Deploy::Target.new(kind: :project, repository: repo,
                                 environment: cfg["environment"] || "production", config: cfg)
        else
          Ai::Deploy::Target.new(kind: :platform_self,
                                 environment: cfg["environment"] || "production", config: cfg)
        end
      end

      def deploy_config(land)
        cfg = {}
        camp = land.try(:campaign)
        if camp&.configuration.is_a?(Hash) && camp.configuration["deploy"].is_a?(Hash)
          cfg = camp.configuration["deploy"]
        end
        if land.respond_to?(:metadata) && land.metadata.is_a?(Hash) && land.metadata["deploy"].is_a?(Hash)
          cfg = cfg.merge(land.metadata["deploy"])
        end
        cfg
      end

      def real_deploy_opted_in?(land)
        cfg = deploy_config(land)
        cfg["auto_deploy"] == true || cfg["dry_run"] == false
      end

      def currently_deployed_ref
        return nil unless @repository_path

        out, _err, status = Open3.capture3("git", "rev-parse", "HEAD", chdir: @repository_path)
        status.success? ? out.strip : nil
      rescue StandardError
        nil
      end

      def default_repository_path
        if defined?(Ai::Land::LandService) && Ai::Land::LandService.respond_to?(:default_repository_path)
          Ai::Land::LandService.default_repository_path
        else
          Rails.root.parent.to_s
        end
      end
    end
  end
end
