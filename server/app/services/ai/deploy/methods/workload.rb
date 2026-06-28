# frozen_string_literal: true

module Ai
  module Deploy
    module Methods
      # Managed-project deploy (the primary purpose): deploy a registered project
      # (Devops::GitRepository) by triggering its configured deploy Pipeline, reusing the
      # CORE Devops pipeline machinery. The pipeline's deploy step performs the actual
      # rollout (container/k8s/webhook per the project's config); the Ai::DevopsBridge::
      # DeploymentGuardian assesses post-deploy health for the auto-rollback decision.
      #
      # Target config: { "pipeline_id" => <Devops::Pipeline id, optional> }. Without an
      # explicit pipeline, the first active deploy pipeline for the repo is used. If the
      # project has no deploy pipeline, the method reports that (operator configures one).
      class Workload < Ai::Deploy::Method
        def self.key = :workload

        def self.available?
          [defined?(::Devops::Pipeline), defined?(::Ai::DevopsBridge::DeploymentGuardian)].all?(&:present?)
        end

        def self.supports?(target) = target.project?

        def deploy!(target:, ref:, dry_run: true)
          return Ai::Deploy::Result.failure("workload deploys projects only") unless target.project?

          pipeline = resolve_deploy_pipeline(target)
          return Ai::Deploy::Result.failure("no deploy pipeline configured for #{target.label}") unless pipeline

          if dry_run
            return Ai::Deploy::Result.dry(
              commands: ["trigger deploy pipeline '#{pipeline.name}' @ #{ref}"],
              detail: "would trigger deploy pipeline #{pipeline.name} for #{target.label} at #{ref} (#{target.environment})"
            )
          end

          run = pipeline.trigger_run!(
            trigger_type: "deploy",
            trigger_context: { "ref" => ref, "environment" => target.environment, "source" => "ai_deploy" },
            triggered_by: user
          )
          Ai::Deploy::Result.ok(
            "triggered deploy pipeline #{pipeline.name} (run ##{run.run_number})",
            commands: ["trigger deploy pipeline #{pipeline.name}"],
            pipeline_run_id: run.id, pipeline_id: pipeline.id, async: true
          )
        rescue StandardError => e
          Ai::Deploy::Result.failure("workload deploy failed: #{e.message}")
        end

        # Health via the DeploymentGuardian. Auto-rollback only when the guardian explicitly
        # recommends it; a guardian error or inconclusive read is treated as healthy (don't
        # roll back a deploy on a monitoring hiccup).
        def verify_health(target:, deploy_run:)
          run = pipeline_run_from(deploy_run)
          return Ai::Deploy::Result.ok("no pipeline run to assess") unless run

          rec = ::Ai::DevopsBridge::DeploymentGuardian.new(account: account).recommend_action(pipeline_run: run)
          if rec[:recommendation].to_s == "rollback"
            Ai::Deploy::Result.failure("guardian recommends rollback: #{rec[:reason]}")
          else
            Ai::Deploy::Result.ok("guardian: #{rec[:recommendation]} (confidence #{rec[:confidence]})")
          end
        rescue StandardError => e
          Ai::Deploy::Result.ok("health inconclusive (not rolling back): #{e.message}")
        end

        def rollback!(target:, deploy_run:)
          pipeline = resolve_deploy_pipeline(target)
          unless pipeline.respond_to?(:matches_trigger?) && pipeline.matches_trigger?("rollback")
            return Ai::Deploy::Result.failure("no rollback pipeline configured for #{target.label}")
          end

          run = pipeline.trigger_run!(trigger_type: "rollback",
                                      trigger_context: { "source" => "ai_deploy_rollback" }, triggered_by: user)
          Ai::Deploy::Result.new(status: :rolled_back, detail: "triggered rollback pipeline run ##{run.run_number}")
        rescue StandardError => e
          Ai::Deploy::Result.failure("rollback failed: #{e.message}")
        end

        private

        def resolve_deploy_pipeline(target)
          return nil unless target.project? && target.repository

          pipelines = target.repository.devops_pipelines
          pipelines = pipelines.active if pipelines.respond_to?(:active)

          if (explicit = target.config["pipeline_id"].presence)
            pipelines.find_by(id: explicit) || account.devops_pipelines.find_by(id: explicit)
          else
            pipelines.to_a.find { |p| p.matches_trigger?("deploy") } || pipelines.first
          end
        rescue StandardError
          nil
        end

        def pipeline_run_from(deploy_run)
          id = deploy_run.metadata["pipeline_run_id"] || deploy_run.metadata[:pipeline_run_id]
          id.present? ? ::Devops::PipelineRun.find_by(id: id) : nil
        end
      end
    end
  end
end
