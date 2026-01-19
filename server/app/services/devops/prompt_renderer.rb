# frozen_string_literal: true

module Devops
  # DevOps-specific prompt renderer that extends the shared prompt renderer
  # with Git and CI/CD context (PR, commits, branches, diffs, etc.)
  class PromptRenderer
    class RenderError < StandardError; end
    class TemplateNotFoundError < StandardError; end

    attr_reader :template, :variables, :context

    # Initialize with template and optional variables
    # @param template [Shared::PromptTemplate, String] The template to render
    # @param variables [Hash] Variables to inject into the template
    # @param context [Hash] Additional context (e.g., pipeline run, repository)
    def initialize(template, variables: {}, context: {})
      @template = template
      @variables = variables.deep_stringify_keys
      @context = context.deep_stringify_keys
    end

    # Render the template with variables
    # @return [String] The rendered template
    def render
      template_content = extract_template_content
      liquid_template = parse_template(template_content)

      render_context = build_render_context
      liquid_template.render(render_context)
    rescue Liquid::SyntaxError => e
      raise RenderError, "Template syntax error: #{e.message}"
    rescue StandardError => e
      raise RenderError, "Failed to render template: #{e.message}"
    end

    # Extract variables used in the template
    # @return [Array<String>] List of variable names
    def extract_variables
      template_content = extract_template_content
      # Match {{ variable }} and {% variable %} patterns
      variable_pattern = /\{\{\s*(\w+(?:\.\w+)*)\s*\}\}|\{%\s*(?:if|for|unless)\s+(\w+)/

      variables = template_content.scan(variable_pattern).flatten.compact.uniq
      variables.map { |v| v.split(".").first }.uniq
    end

    # Validate the template syntax
    # @return [Hash] Validation result with :valid and :errors keys
    def validate
      template_content = extract_template_content
      Liquid::Template.parse(template_content)
      { valid: true, errors: [] }
    rescue Liquid::SyntaxError => e
      { valid: false, errors: [e.message] }
    end

    class << self
      # Render a template by ID with variables
      # @param template_id [String] The template ID
      # @param account [Account] The account to scope the template lookup
      # @param variables [Hash] Variables to inject
      # @param context [Hash] Additional context
      # @return [String] The rendered template
      def render_by_id(template_id, account:, variables: {}, context: {})
        template = account.shared_prompt_templates.for_devops.find(template_id)
        new(template, variables: variables, context: context).render
      rescue ActiveRecord::RecordNotFound
        raise TemplateNotFoundError, "Template not found: #{template_id}"
      end

      # Render a template by slug with variables
      # @param slug [String] The template slug
      # @param account [Account] The account to scope the template lookup
      # @param variables [Hash] Variables to inject
      # @param context [Hash] Additional context
      # @return [String] The rendered template
      def render_by_slug(slug, account:, variables: {}, context: {})
        template = account.shared_prompt_templates.for_devops.find_by!(slug: slug)
        new(template, variables: variables, context: context).render
      rescue ActiveRecord::RecordNotFound
        raise TemplateNotFoundError, "Template not found: #{slug}"
      end

      # Quick render a string template
      # @param content [String] The template content
      # @param variables [Hash] Variables to inject
      # @return [String] The rendered template
      def render_string(content, variables: {})
        new(content, variables: variables).render
      end
    end

    private

    def extract_template_content
      case template
      when Shared::PromptTemplate
        template.content
      when String
        template
      else
        raise RenderError, "Invalid template type: #{template.class}"
      end
    end

    def parse_template(content)
      Liquid::Template.parse(content)
    end

    def build_render_context
      # Start with provided variables
      ctx = variables.dup

      # Add template default variables if template is a model
      if template.is_a?(Shared::PromptTemplate) && template.variables.present?
        ctx = template.variables.deep_stringify_keys.merge(ctx)
      end

      # Add context information
      ctx["context"] = context

      # Add git context if available
      if context["repository"].present?
        ctx["repository"] = context["repository"]
        ctx["repo_name"] = context["repository"]["name"]
        ctx["repo_full_name"] = context["repository"]["full_name"]
      end

      # Add PR context if available
      if context["pull_request"].present?
        ctx["pr"] = context["pull_request"]
        ctx["pr_number"] = context["pull_request"]["number"]
        ctx["pr_title"] = context["pull_request"]["title"]
        ctx["pr_body"] = context["pull_request"]["body"]
      end

      # Add issue context if available
      if context["issue"].present?
        ctx["issue"] = context["issue"]
        ctx["issue_number"] = context["issue"]["number"]
        ctx["issue_title"] = context["issue"]["title"]
        ctx["issue_body"] = context["issue"]["body"]
      end

      # Add commit context if available
      if context["commit"].present?
        ctx["commit"] = context["commit"]
        ctx["commit_sha"] = context["commit"]["sha"]
        ctx["commit_message"] = context["commit"]["message"]
      end

      # Add branch context if available
      if context["branch"].present?
        ctx["branch"] = context["branch"]
      end

      # Add diff context if available
      if context["diff"].present?
        ctx["diff"] = context["diff"]
      end

      # Add timestamp
      ctx["timestamp"] = Time.current.iso8601
      ctx["date"] = Date.current.to_s

      ctx
    end
  end
end
