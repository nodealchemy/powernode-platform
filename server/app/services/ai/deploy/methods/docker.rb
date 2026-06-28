# frozen_string_literal: true

module Ai
  module Deploy
    module Methods
      # Container / Docker-Swarm deploy: roll a swarm service to a new image, reusing the
      # EXISTING Devops swarm pipeline — create a Devops::SwarmDeployment(update) and enqueue
      # the worker Swarm::ServiceUpdateJob, which inspects the live service spec, swaps the
      # image, and monitors convergence (running == desired replicas). Serves a containerized
      # platform-self OR a managed project. All reused infra is CORE (no extension dep).
      #
      # Async by nature: deploy! initiates + records; the worker owns convergence and its own
      # failure handling. rollback! reuses Docker's PreviousSpec via ServiceManager#rollback_service.
      #
      # Target config: { "swarm_service_id" => <SwarmService id | service_name>,
      #                  "image" => "repo:tag" (optional; default = current repo + the ref) }.
      class Docker < Ai::Deploy::Method
        def self.key = :docker

        def self.available?
          [defined?(::Devops::SwarmService), defined?(::Devops::Docker::ServiceManager)].all?(&:present?)
        end

        def deploy!(target:, ref:, dry_run: true)
          service = resolve_service(target)
          return Ai::Deploy::Result.failure("no swarm service for target (set config swarm_service_id)") unless service

          image = target.config["image"].presence || derive_image(service, ref)
          command = "docker service update --image #{image} #{service.service_name}"

          if dry_run
            return Ai::Deploy::Result.dry(
              commands: [command],
              detail: "would roll #{service.service_name} on cluster #{service.cluster.name} to #{image}"
            )
          end

          deployment = service.cluster.swarm_deployments.create!(
            service: service, deployment_type: "update", status: "pending",
            desired_state: { "image" => image }, git_sha: ref, triggered_by: user
          )
          WorkerJobService.enqueue_job("Swarm::ServiceUpdateJob", args: [deployment.id], queue: "devops_high")

          Ai::Deploy::Result.ok(
            "rollout enqueued: #{service.service_name} -> #{image}",
            commands: [command], swarm_deployment_id: deployment.id, image: image, async: true
          )
        rescue StandardError => e
          Ai::Deploy::Result.failure("docker deploy failed: #{e.message}")
        end

        # The worker monitors convergence + its own failure handling, so be LENIENT: only
        # report unhealthy on a CONFIRMED failed swarm deployment — otherwise the orchestrator's
        # immediate post-deploy check would false-trigger a rollback on a still-converging deploy.
        def verify_health(target:, deploy_run:)
          dep_id = deploy_run.metadata["swarm_deployment_id"] || deploy_run.metadata[:swarm_deployment_id]
          return Ai::Deploy::Result.ok("no swarm deployment recorded") if dep_id.blank?

          deployment = ::Devops::SwarmDeployment.find_by(id: dep_id)
          return Ai::Deploy::Result.ok("swarm deployment not found") unless deployment

          if deployment.reload.status == "failed"
            Ai::Deploy::Result.failure("swarm deployment failed")
          else
            Ai::Deploy::Result.ok("swarm deployment #{deployment.status} (worker monitors convergence)")
          end
        end

        def rollback!(target:, deploy_run:)
          service = resolve_service(target)
          return Ai::Deploy::Result.failure("no swarm service to roll back") unless service

          result = ::Devops::Docker::ServiceManager.new(cluster: service.cluster, user: user).rollback_service(service)
          if result[:success]
            Ai::Deploy::Result.new(status: :rolled_back, detail: "rolled back #{service.service_name} to previous spec")
          else
            Ai::Deploy::Result.failure("rollback failed: #{result[:error]}")
          end
        end

        private

        def resolve_service(target)
          id = target.config["swarm_service_id"].presence
          return nil if id.blank?

          account.devops_swarm_services.find_by(id: id) ||
            account.devops_swarm_services.find_by(service_name: id)
        end

        def derive_image(service, ref)
          base = service.image.to_s.split(":").first
          ref.present? ? "#{base}:#{ref.to_s[0, 12]}" : service.image
        end
      end
    end
  end
end
