# frozen_string_literal: true

module Mcp
  class NativePromptProvider
    PAGE_SIZE = 50

    def initialize(account:)
      @account = account
    end

    # List all available prompts with optional pagination
    #
    # @param cursor [String, nil] Pagination cursor (offset)
    # @return [Hash] { prompts: [...], nextCursor: String|nil }
    def list_prompts(cursor: nil)
      offset = cursor.to_i

      templates = @account.shared_prompt_templates
                          .active
                          .latest_versions
                          .order(:name)
                          .offset(offset)
                          .limit(PAGE_SIZE + 1)

      has_more = templates.size > PAGE_SIZE
      prompts = templates.first(PAGE_SIZE).map { |t| template_to_prompt(t) }

      next_cursor = has_more ? (offset + PAGE_SIZE).to_s : nil

      { prompts: prompts, nextCursor: next_cursor }
    end

    # Get a specific prompt by name (slug) and render with arguments
    #
    # @param name [String] Prompt template slug
    # @param arguments [Hash] Variables to render the prompt with
    # @return [Hash] { description:, messages: [{ role:, content: }] }
    # @raise [ArgumentError] if prompt not found or validation fails
    def get_prompt(name:, arguments: {})
      template = @account.shared_prompt_templates
                         .active
                         .find_by(slug: name)

      raise ArgumentError, "Prompt not found: #{name}" unless template

      # Validate required variables
      validation_errors = template.validate_variables(arguments || {})
      if validation_errors.any?
        raise ArgumentError, validation_errors.join("; ")
      end

      # Render the template
      rendered = template.render(arguments || {})

      {
        description: template.description,
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: rendered
            }
          }
        ]
      }
    end

    private

    def template_to_prompt(template)
      prompt = {
        name: template.slug,
        description: template.description || template.name
      }

      # Map variable definitions to MCP arguments
      args = template.variable_definitions.map do |var_def|
        arg = {
          name: var_def[:name],
          description: var_def[:description],
          required: var_def[:required] || false
        }
        arg
      end

      prompt[:arguments] = args if args.any?
      prompt
    end
  end
end
