# frozen_string_literal: true

module Shared
  # Renders prompt templates with variable substitution using Liquid templating
  # Used by both AI Workflows and CI/CD Pipelines for prompt rendering.
  #
  # Example usage:
  #   renderer = Shared::PromptRenderer.new(template, variables: { name: "John" })
  #   result = renderer.render
  #
  # Supports:
  #   - Liquid templating with filters
  #   - Default values for missing variables
  #   - Error handling with fallback to raw content
  #
  class PromptRenderer
    class RenderError < StandardError; end

    attr_reader :template, :variables, :options

    # Initialize the renderer
    #
    # @param template [Shared::PromptTemplate, String] Template object or raw content
    # @param variables [Hash] Variables to substitute
    # @param options [Hash] Additional options
    def initialize(template, variables: {}, **options)
      @template = template
      @variables = normalize_variables(variables)
      @options = options
    end

    # Render the template with variables
    #
    # @return [String] Rendered content
    def render
      content = template_content
      return content if content.blank?

      # Apply variable defaults from template definition
      merged_variables = apply_defaults

      # Parse and render using Liquid
      liquid_template = Liquid::Template.parse(content)
      liquid_template.render(merged_variables, strict_variables: strict_mode?)
    rescue Liquid::Error => e
      handle_render_error(e)
    end

    # Validate template syntax without rendering
    #
    # @return [Hash] Validation result with :valid and :errors keys
    def validate
      content = template_content
      return { valid: true, errors: [] } if content.blank?

      Liquid::Template.parse(content)
      { valid: true, errors: [] }
    rescue Liquid::SyntaxError => e
      { valid: false, errors: [e.message] }
    end

    # Extract variable names from template
    #
    # @return [Array<String>] List of variable names
    def extract_variables
      content = template_content
      return [] if content.blank?

      # Match {{ variable }} and {% if variable %} patterns
      variable_pattern = /\{\{[^}]*\}\}|\{%[^%]*%\}/
      matches = content.scan(variable_pattern)

      variables = matches.flat_map do |match|
        # Extract variable names from the match
        match.scan(/\b[a-z_][a-z0-9_]*\b/i)
      end

      # Filter out Liquid keywords
      liquid_keywords = %w[if else elsif endif unless for endfor case when endcase assign capture endcapture]
      variables.uniq.reject { |v| liquid_keywords.include?(v.downcase) }
    end

    # Preview render with sample data
    #
    # @param sample_variables [Hash] Sample values for preview
    # @return [String] Preview rendered content
    def preview(sample_variables = {})
      preview_vars = variables.merge(normalize_variables(sample_variables))
      self.class.new(template, variables: preview_vars, **options).render
    end

    private

    def template_content
      case template
      when String
        template
      when ->(t) { t.respond_to?(:content) }
        template.content
      else
        template.to_s
      end
    end

    def variable_definitions
      return [] unless template.respond_to?(:variables) && template.variables.is_a?(Array)

      template.variables
    end

    def normalize_variables(vars)
      return {} unless vars.is_a?(Hash)

      vars.stringify_keys
    end

    def apply_defaults
      merged = {}

      # Apply defaults from template variable definitions
      variable_definitions.each do |var_def|
        name = var_def["name"] || var_def[:name]
        default = var_def["default"] || var_def[:default]
        next unless name

        merged[name.to_s] = default if default.present?
      end

      # Overlay provided variables
      merged.merge(variables)
    end

    def strict_mode?
      options.fetch(:strict, false)
    end

    def handle_render_error(error)
      Rails.logger.error "[PromptRenderer] Render error: #{error.message}"

      if options[:raise_on_error]
        raise RenderError, "Failed to render template: #{error.message}"
      else
        # Return raw content as fallback
        template_content
      end
    end
  end
end
