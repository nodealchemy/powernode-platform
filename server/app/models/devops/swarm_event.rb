# frozen_string_literal: true

module Devops
  class SwarmEvent < ApplicationRecord
    self.table_name = "devops_swarm_events"

    include Auditable

    audit_account_via :cluster
    include AcknowledgeableEvent

    SOURCE_TYPES = %w[node service task cluster stack].freeze

    belongs_to :cluster, class_name: "Devops::SwarmCluster"

    validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }

    private

    def event_owner_attributes
      { cluster_id: cluster_id }
    end
  end
end
