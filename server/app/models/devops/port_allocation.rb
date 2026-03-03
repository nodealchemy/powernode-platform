# frozen_string_literal: true

module Devops
  class PortAllocation < ApplicationRecord
    self.table_name = "devops_port_allocations"

    STATUSES = %w[active released].freeze
    PROTOCOLS = %w[tcp udp].freeze

    # Associations
    belongs_to :account
    belongs_to :allocatable, polymorphic: true

    # Validations
    validates :port, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :protocol, presence: true, inclusion: { in: PROTOCOLS }
    validates :host_identifier, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :allocatable_type, presence: true
    validates :allocatable_id, presence: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :released, -> { where(status: "released") }
    scope :for_host, ->(host_id) { where(host_identifier: host_id) }
    scope :expired, -> { active.where("expires_at IS NOT NULL AND expires_at < ?", Time.current) }

    def release!
      update!(status: "released", released_at: Time.current)
    end

    def active?
      status == "active"
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end
  end
end
