# frozen_string_literal: true

module Devops
  # AI configuration for DevOps pipelines
  # Stores model settings, parameters, and provider configuration
  class AiConfig < ApplicationRecord
    self.table_name = "devops_ai_configs"

    # ============================================
    # Constants
    # ============================================
    STATUSES = %w[active inactive archived].freeze
    CONFIG_TYPES = %w[chat completion embedding code_review code_generation custom].freeze
    PROVIDERS = %w[openai anthropic google azure cohere custom].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :account_id }
    validates :config_type, presence: true, inclusion: { in: CONFIG_TYPES }
    validates :provider, presence: true
    validates :model, presence: true, length: { maximum: 100 }
    validates :status, presence: true, inclusion: { in: STATUSES }

    validates :max_tokens, numericality: { greater_than: 0, less_than_or_equal_to: 100_000 }, allow_nil: true
    validates :temperature, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0 }, allow_nil: true
    validates :top_p, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true
    validates :frequency_penalty, numericality: { greater_than_or_equal_to: -2.0, less_than_or_equal_to: 2.0 }, allow_nil: true
    validates :presence_penalty, numericality: { greater_than_or_equal_to: -2.0, less_than_or_equal_to: 2.0 }, allow_nil: true
    validates :timeout_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 300 }, allow_nil: true

    validate :ensure_single_default_per_type, if: :is_default?

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(status: "active", is_active: true) }
    scope :inactive, -> { where(status: "inactive").or(where(is_active: false)) }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(config_type) { where(config_type: config_type) }
    scope :by_provider, ->(provider) { where(provider: provider) }
    scope :default_configs, -> { where(is_default: true) }
    scope :recently_used, -> { where.not(last_used_at: nil).order(last_used_at: :desc) }

    # ============================================
    # Instance Methods
    # ============================================

    def active?
      status == "active" && is_active?
    end

    def can_use?
      active?
    end

    def make_default!
      transaction do
        account.devops_ai_configs
               .where(config_type: config_type, is_default: true)
               .where.not(id: id)
               .update_all(is_default: false)

        update!(is_default: true)
      end
    end

    def record_usage!(tokens_used: 0)
      increment!(:total_requests)
      increment!(:total_tokens, tokens_used) if tokens_used.positive?
      update_column(:last_used_at, Time.current)
    end

    def usage_stats
      {
        total_requests: total_requests,
        total_tokens: total_tokens,
        last_used_at: last_used_at,
        average_tokens_per_request: total_requests.positive? ? (total_tokens.to_f / total_requests).round(2) : 0
      }
    end

    # #37: resolve the model dynamically when the config is "auto"/blank — an
    # explicit model string is honored as a pin. Resolution stays within the
    # config's own provider (a config is provider-specific): embedding configs
    # pick a text_embedding model; code/chat configs prefer a reasoning-tier
    # model; otherwise the provider's default. No hardcoded model names.
    def resolved_model
      return model if model.present? && !auto_model?

      resolve_devops_model
    end

    def model_params
      {
        model: resolved_model,
        max_tokens: max_tokens,
        temperature: temperature,
        top_p: top_p,
        frequency_penalty: frequency_penalty,
        presence_penalty: presence_penalty
      }.compact
    end

    def full_configuration
      {
        provider: provider,
        model_params: model_params,
        system_prompt: system_prompt,
        settings: settings,
        timeout_seconds: timeout_seconds
      }
    end

    private

    # Sentinel values that mean "resolve a model at runtime" rather than pin one.
    AUTO_MODELS = %w[auto default].freeze

    def auto_model?
      AUTO_MODELS.include?(model.to_s.strip.downcase)
    end

    # Resolve a model within THIS config's provider — a config is provider-specific,
    # so the model always matches the provider whose credential the devops flow uses
    # (no cross-provider fallback). Code/chat configs route through the one shared
    # resolver (Ai::AgentModelSelector, provider-constrained); embedding configs pick
    # a text_embedding model directly (the selector's agent profiles assume chat).
    # Returns nil when the declared provider isn't set up, so the caller surfaces a
    # missing model rather than emitting the "auto" sentinel or a blank string.
    def resolve_devops_model
      prov = config_provider
      return nil unless prov

      if config_type == "embedding"
        embedding_model_for(prov) || prov.default_model.presence
      else
        ::Ai::AgentModelSelector.recommend(account: account, agent_type: selector_agent_type, provider: prov)[:model].presence ||
          prov.default_model.presence
      end
    end

    # The config's own active provider (no cross-provider fallback).
    def config_provider
      ::Ai::Provider.where(account_id: account_id, provider_type: provider, is_active: true).first
    end

    # Map the DevOps config_type to the selector's nearest agent_type profile.
    def selector_agent_type
      %w[code_review code_generation].include?(config_type) ? "code_assistant" : "assistant"
    end

    # First text_embedding-capable model id in the provider's catalog.
    def embedding_model_for(prov)
      entry = Array(prov.supported_models).find do |m|
        m.is_a?(Hash) && Array(m["capabilities"]).include?("text_embedding")
      end
      ::Ai::ModelTiers.id_for(entry) if entry
    end

    def ensure_single_default_per_type
      return unless is_default? && is_default_changed?

      existing_default = account.devops_ai_configs
                                 .where(config_type: config_type, is_default: true)
                                 .where.not(id: id)
                                 .exists?

      return unless existing_default

      # Auto-unset the other default instead of erroring
      account.devops_ai_configs
             .where(config_type: config_type, is_default: true)
             .where.not(id: id)
             .update_all(is_default: false)
    end
  end
end
