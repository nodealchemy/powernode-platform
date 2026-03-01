# frozen_string_literal: true

module Ai
  class RoleProfile < ApplicationRecord
    self.table_name = "ai_role_profiles"

    # ==========================================
    # Constants
    # ==========================================
    ROLE_TYPES = %w[lead worker reviewer type_checker test_writer documentation_expert custom].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account, optional: true # nil = system profile

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true
    validates :role_type, presence: true, inclusion: { in: ROLE_TYPES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :system_profiles, -> { where(is_system: true) }
    scope :for_account, ->(account_id) { where(account_id: [account_id, nil]) }
    scope :by_role_type, ->(type) { where(role_type: type) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_slug, on: :create

    # ==========================================
    # Public Methods
    # ==========================================

    # Apply this profile's settings to a TeamRole
    def apply_to_role(team_role)
      updates = {}

      if system_prompt_template.present?
        metadata = team_role.context_access || {}
        metadata["system_prompt_template"] = system_prompt_template
        updates[:context_access] = metadata
      end

      if communication_style.present?
        constraints = team_role.constraints || []
        communication_style.each do |key, value|
          constraints << "communication_#{key}: #{value}"
        end
        updates[:constraints] = constraints.uniq
      end

      if quality_checks.present?
        capabilities = team_role.capabilities || []
        quality_checks.each do |check|
          capabilities << "quality_check:#{check['check']}" if check["check"]
        end
        updates[:capabilities] = capabilities.uniq
      end

      team_role.update!(updates) if updates.present?
      team_role
    end

    # Render system_prompt_template with variable substitution
    def generate_system_prompt(context = {})
      return nil if system_prompt_template.blank?

      result = system_prompt_template.dup
      context.each do |key, value|
        result.gsub!("{{#{key}}}", value.to_s)
      end
      result
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.to_s.parameterize
      self.slug = base_slug

      counter = 1
      while self.class.exists?(slug: self.slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end
