# frozen_string_literal: true

module Ai
  module Concerns
    # PromptTemplateLookup provides a shared interface for resolving system prompts
    # from database-backed Shared::PromptTemplate records with inline fallbacks.
    #
    # Including services call:
    #   resolve_prompt_template("slug", account: @account, variables: { key: "val" }, fallback: FALLBACK)
    #
    # Resolution order:
    #   1. Active Shared::PromptTemplate matching (account_id OR system, slug, is_active)
    #   2. Fallback string rendered through Shared::PromptRenderer (Liquid)
    #   3. nil with a logger warning
    #
    module PromptTemplateLookup
      private

      def resolve_prompt_template(slug, account:, variables: {}, fallback: nil)
        string_vars = variables.transform_keys(&:to_s)

        # Try database-backed template first
        template = find_prompt_template(slug, account)
        if template
          return template.render(string_vars)
        end

        # Fall back to inline string with variable substitution
        return render_fallback_prompt(fallback, string_vars) if fallback.present?

        Rails.logger.warn("[PromptTemplateLookup] No template found for slug=#{slug} and no fallback provided")
        nil
      rescue StandardError => e
        Rails.logger.warn("[PromptTemplateLookup] Template resolution failed for slug=#{slug}: #{e.message}")
        fallback.present? ? render_fallback_prompt(fallback, variables.transform_keys(&:to_s)) : nil
      end

      def find_prompt_template(slug, account)
        # Prefer account-specific template, then system template
        scope = Shared::PromptTemplate.where(slug: slug, is_active: true)

        scope.where(account_id: account&.id).order(version: :desc).first ||
          scope.system_templates.order(version: :desc).first
      end

      # Render a fallback string, using Liquid if available, otherwise simple substitution
      def render_fallback_prompt(fallback, variables)
        renderer = Shared::PromptRenderer.new(fallback, variables: variables)
        renderer.render
      rescue StandardError
        # Liquid gem unavailable or render failed — apply simple {{ var }} substitution
        result = fallback.dup
        variables.each { |key, value| result.gsub!("{{ #{key} }}", value.to_s) }
        result
      end
    end
  end
end
