# frozen_string_literal: true

module Devops
  class ContainerImageBuild < ApplicationRecord
    self.table_name = "devops_container_image_builds"

    STATUSES = %w[pending building completed failed].freeze
    TRIGGER_TYPES = %w[push cascade manual].freeze

    # Associations
    belongs_to :account
    belongs_to :container_template, class_name: "Devops::ContainerTemplate"
    belongs_to :triggered_by_build, class_name: "Devops::ContainerImageBuild", optional: true
    has_many :cascade_builds, class_name: "Devops::ContainerImageBuild",
             foreign_key: "triggered_by_build_id", dependent: :nullify

    # Validations
    validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :building, -> { where(status: "building") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :recent, -> { order(created_at: :desc) }

    def start!
      update!(status: "building", started_at: Time.current)
    end

    def complete!(image_tag:, build_log: nil)
      update!(
        status: "completed",
        image_tag: image_tag,
        build_log: build_log,
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def fail!(build_log: nil)
      update!(
        status: "failed",
        build_log: build_log,
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def build_summary
      {
        id: id,
        trigger_type: trigger_type,
        status: status,
        git_sha: git_sha,
        image_tag: image_tag,
        duration_ms: duration_ms,
        started_at: started_at,
        completed_at: completed_at,
        triggered_by_build_id: triggered_by_build_id,
        cascade_build_count: cascade_builds.count,
        created_at: created_at
      }
    end

    private

    def calculate_duration
      return nil unless started_at

      ((completed_at || Time.current) - started_at) * 1000
    end
  end
end
