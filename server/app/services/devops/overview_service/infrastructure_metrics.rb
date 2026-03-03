# frozen_string_literal: true

module Devops
  class OverviewService
    module InfrastructureMetrics
      extend ActiveSupport::Concern

      private

      def generate_infrastructure_metrics
        {
          containers: container_metrics,
          swarm: swarm_metrics,
          docker: docker_metrics
        }
      end

      def container_metrics
        containers = account.devops_container_instances

        total = containers.count
        active = containers.active.count
        completed = containers.completed.count
        failed = containers.failed.count
        finished = containers.finished.count

        {
          total: total,
          active: active,
          completed: completed,
          failed: failed,
          finished: finished,
          success_rate: finished > 0 ? (completed.to_f / finished * 100).round(1) : 0.0
        }
      end

      def swarm_metrics
        clusters = account.devops_swarm_clusters

        {
          clusters: clusters.count,
          connected: clusters.connected.count
        }
      end

      def docker_metrics
        hosts = account.devops_docker_hosts

        {
          hosts: hosts.count,
          connected: hosts.connected.count
        }
      end
    end
  end
end
