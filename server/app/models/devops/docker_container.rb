# frozen_string_literal: true

module Devops
  class DockerContainer < ApplicationRecord
    self.table_name = "devops_docker_containers"

    include Auditable

    audit_account_via :docker_host

    STATES = %w[created running paused restarting exited removing dead].freeze

    belongs_to :docker_host, class_name: "Devops::DockerHost"
    has_many :docker_activities, class_name: "Devops::DockerActivity", foreign_key: "container_id", dependent: :nullify

    validates :docker_container_id, presence: true
    validates :docker_container_id, uniqueness: { scope: :docker_host_id }
    validates :name, presence: true
    validates :image, presence: true
    validates :state, presence: true, inclusion: { in: STATES }

    # IMP-8880bc817ea3 — container lifecycle seam. Every record create/destroy
    # path (ContainerManager create/remove, both discovery syncs + their stale
    # sweeps, the DockerHost dependent: :destroy cascade) funnels through this
    # model, so one wire point covers the whole enumeration — see
    # Devops::ContainerLifecycleRegistry for the call-site map and the handler
    # contract. Post-commit so handlers see durable state; the registry
    # swallows handler errors, so these can never break container lifecycle.
    after_create_commit { ContainerLifecycleRegistry.notify(:created, self) }
    after_destroy_commit { ContainerLifecycleRegistry.notify(:removed, self) }

    scope :running, -> { where(state: "running") }
    scope :stopped, -> { where(state: %w[exited created dead]) }
    scope :by_state, ->(state) { where(state: state) }
    scope :recent, -> { order(created_at: :desc) }

    def running?
      state == "running"
    end

    def exited?
      state == "exited"
    end

    def paused?
      state == "paused"
    end

    def stopped?
      %w[exited created dead].include?(state)
    end

    def container_summary
      {
        id: id,
        docker_container_id: docker_container_id,
        name: name,
        image: image,
        state: state,
        status_text: status_text,
        ports: ports,
        started_at: started_at,
        created_at: created_at
      }
    end

    def container_details
      container_summary.merge(
        image_id: image_id,
        mounts: mounts,
        networks: networks,
        labels: labels,
        environment: environment,
        command: command,
        restart_policy: restart_policy,
        restart_count: restart_count,
        size_rw: size_rw,
        finished_at: finished_at,
        last_seen_at: last_seen_at,
        docker_host_id: docker_host_id,
        updated_at: updated_at
      )
    end
  end
end
