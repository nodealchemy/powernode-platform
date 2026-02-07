# frozen_string_literal: true

module Devops
  class SwarmService < ApplicationRecord
    self.table_name = "devops_swarm_services"

    include Auditable

    MODES = %w[replicated global].freeze

    belongs_to :cluster, class_name: "Devops::SwarmCluster"
    belongs_to :stack, class_name: "Devops::SwarmStack", optional: true
    has_many :deployments, class_name: "Devops::SwarmDeployment", foreign_key: "service_id", dependent: :nullify

    validates :docker_service_id, presence: true, uniqueness: { scope: :cluster_id }
    validates :service_name, presence: true
    validates :image, presence: true
    validates :mode, presence: true, inclusion: { in: MODES }

    scope :replicated, -> { where(mode: "replicated") }
    scope :global, -> { where(mode: "global") }
    scope :unhealthy, -> { where("running_replicas < desired_replicas AND mode = 'replicated'") }
    scope :for_stack, ->(stack_name) { where("labels->>'com.docker.stack.namespace' = ?", stack_name) }

    def replicated?
      mode == "replicated"
    end

    def global?
      mode == "global"
    end

    def health_percentage
      return 100.0 if global?
      return 0.0 if desired_replicas.zero?

      [(running_replicas.to_f / desired_replicas * 100).round(1), 100.0].min
    end

    def healthy?
      return true if global?

      running_replicas >= desired_replicas
    end

    def service_summary
      {
        id: id,
        docker_service_id: docker_service_id,
        service_name: service_name,
        image: image,
        mode: mode,
        desired_replicas: desired_replicas,
        running_replicas: running_replicas,
        health_percentage: health_percentage,
        ports: ports,
        stack_id: stack_id
      }
    end

    def service_details
      service_summary.merge(
        constraints: constraints,
        resource_limits: resource_limits,
        resource_reservations: resource_reservations,
        update_config: update_config,
        rollback_config: rollback_config,
        labels: labels,
        environment: environment,
        version: version,
        created_at: created_at,
        updated_at: updated_at
      )
    end
  end
end
