# frozen_string_literal: true

module Ai
  module CodeFactory
    class RiskContract < ApplicationRecord
      self.table_name = "ai_code_factory_risk_contracts"

      STATUSES = %w[draft active archived].freeze
      RISK_TIERS = %w[low standard high critical].freeze

      belongs_to :account
      belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
      belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

      has_many :review_states, class_name: "Ai::CodeFactory::ReviewState",
               foreign_key: "risk_contract_id", dependent: :destroy
      has_many :harness_gaps, class_name: "Ai::CodeFactory::HarnessGap",
               foreign_key: "risk_contract_id", dependent: :nullify
      has_many :ralph_loops, class_name: "Ai::RalphLoop",
               foreign_key: "risk_contract_id", dependent: :nullify

      validates :name, presence: true, length: { maximum: 255 }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :version, numericality: { only_integer: true, greater_than: 0 }

      scope :active, -> { where(status: "active") }
      scope :for_repository, ->(repo_id) { where(repository_id: repo_id) }
      scope :recent, -> { order(created_at: :desc) }

      before_validation :set_defaults, on: :create

      def activate!
        update!(status: "active", activated_at: Time.current)
      end

      def archive!
        update!(status: "archived")
      end

      def tier_for_file(path)
        return nil if risk_tiers.blank?

        matched_tier = nil
        matched_priority = -1

        risk_tiers.each do |tier_config|
          tier_name = tier_config["tier"]
          priority = RISK_TIERS.index(tier_name) || 0
          patterns = tier_config["patterns"] || []

          patterns.each do |pattern|
            if File.fnmatch(pattern, path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
              if priority > matched_priority
                matched_tier = tier_config
                matched_priority = priority
              end
            end
          end
        end

        matched_tier
      end

      def highest_tier_for_files(paths)
        highest = nil
        highest_priority = -1

        paths.each do |path|
          tier = tier_for_file(path)
          next unless tier

          priority = RISK_TIERS.index(tier["tier"]) || 0
          if priority > highest_priority
            highest = tier
            highest_priority = priority
          end
        end

        highest
      end

      private

      def set_defaults
        self.status ||= "draft"
        self.version ||= 1
        self.risk_tiers ||= []
        self.merge_policy ||= {}
        self.docs_drift_rules ||= {}
        self.evidence_requirements ||= {}
        self.remediation_config ||= {}
        self.preflight_config ||= {}
        self.metadata ||= {}
      end
    end
  end
end
