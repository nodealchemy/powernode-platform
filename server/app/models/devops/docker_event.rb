# frozen_string_literal: true

module Devops
  class DockerEvent < ApplicationRecord
    self.table_name = "devops_docker_events"

    include Auditable
    include AcknowledgeableEvent

    audit_account_via :docker_host

    SOURCE_TYPES = %w[host container image network volume].freeze

    belongs_to :docker_host, class_name: "Devops::DockerHost"

    validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }

    private

    def event_owner_attributes
      { docker_host_id: docker_host_id }
    end
  end
end
