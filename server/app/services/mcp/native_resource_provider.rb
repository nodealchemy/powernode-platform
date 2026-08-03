# frozen_string_literal: true

module Mcp
  class NativeResourceProvider
    PAGE_SIZE = 50
    # completion/complete caps values at 100 per spec; fetch one page + 1 so
    # the caller can compute hasMore without a count query.
    COMPLETION_FETCH_LIMIT = 101

    def initialize(account:)
      @account = account
    end

    # List all available resources with optional pagination
    #
    # @param cursor [String, nil] Pagination cursor ("type:offset" format)
    # @return [Hash] { resources: [...], nextCursor: String|nil }
    def list_resources(cursor: nil)
      type_filter, offset = parse_cursor(cursor)
      all_resources = []

      resource_types.each do |type, config|
        next if type_filter && type != type_filter

        items = fetch_items(type, config, offset: type_filter ? offset : 0)
        all_resources.concat(items[:resources])
      end

      # Paginate
      if all_resources.size > PAGE_SIZE
        next_cursor = build_next_cursor(all_resources, offset)
        all_resources = all_resources.first(PAGE_SIZE)
      end

      { resources: all_resources, nextCursor: next_cursor }
    end

    # Read a specific resource by URI
    #
    # @param uri [String] Resource URI (e.g., "powernode://kb/articles/my-slug")
    # @return [Hash] { contents: [{ uri:, mimeType:, text: }] }
    # @raise [ArgumentError] if URI is invalid or resource not found
    def read_resource(uri:)
      parsed = parse_uri(uri)
      raise ArgumentError, "Invalid resource URI: #{uri}" unless parsed

      content = fetch_content(parsed[:type], parsed[:identifier])
      raise ArgumentError, "Resource not found: #{uri}" unless content

      {
        contents: [
          {
            uri: uri,
            mimeType: content[:mime_type],
            text: content[:text]
          }
        ]
      }
    end

    # List parameterized URI templates for all native resource types
    # (MCP resources/templates/list — present in every supported revision,
    # 2024-11-05 through 2026-07-28).
    #
    # @return [Hash] { resourceTemplates: [...] }
    def list_resource_templates(cursor: nil)
      { resourceTemplates: resource_types.values.map { |config| config[:template] } }
    end

    # Complete values for a resource template variable (completion/complete
    # with ref/resource). The uri_template must match one of the templates
    # returned by #list_resource_templates.
    #
    # @return [Array<String>] candidate values (uncapped; caller applies the
    #   spec's 100-value limit and hasMore accounting)
    def complete_uri_template(uri_template:, value: "")
      config = resource_types.values.find { |c| c[:template][:uriTemplate] == uri_template }
      return [] unless config

      config[:complete].call(value.to_s)
    end

    private

    def resource_types
      {
        "kb/articles" => {
          scope: -> { KnowledgeBase::Article.for_account(@account.id).published },
          to_resource: ->(article) {
            {
              uri: "powernode://kb/articles/#{article.slug}",
              name: article.title,
              description: article.excerpt,
              mimeType: "text/plain"
            }
          },
          template: {
            uriTemplate: "powernode://kb/articles/{slug}",
            name: "kb-article",
            title: "Knowledge Base Article",
            description: "Published knowledge base article, addressed by slug",
            mimeType: "text/plain"
          },
          complete: ->(prefix) {
            KnowledgeBase::Article.for_account(@account.id).published
              .where("slug ILIKE ?", "#{sanitize_like(prefix)}%")
              .order(:slug).limit(COMPLETION_FETCH_LIMIT).pluck(:slug)
          }
        },
        "ai/agents" => {
          scope: -> { ::Ai::Agent.for_account(@account.id).where(status: "active") },
          to_resource: ->(agent) {
            {
              uri: "powernode://ai/agents/#{agent.id}",
              name: agent.name,
              description: agent.description,
              mimeType: "application/json"
            }
          },
          template: {
            uriTemplate: "powernode://ai/agents/{id}",
            name: "ai-agent",
            title: "AI Agent",
            description: "Active AI agent definition, addressed by agent id",
            mimeType: "application/json"
          },
          complete: ->(prefix) {
            ::Ai::Agent.for_account(@account.id).where(status: "active")
              .where("id::text ILIKE ?", "#{sanitize_like(prefix)}%")
              .order(:id).limit(COMPLETION_FETCH_LIMIT).pluck(:id).map(&:to_s)
          }
        },
        "ai/prompts" => {
          scope: -> { ::Shared::PromptTemplate.for_account(@account.id).active },
          to_resource: ->(template) {
            {
              uri: "powernode://ai/prompts/#{template.slug}",
              name: template.name,
              description: template.description,
              mimeType: "text/plain"
            }
          },
          template: {
            uriTemplate: "powernode://ai/prompts/{slug}",
            name: "ai-prompt",
            title: "Prompt Template",
            description: "Active shared prompt template, addressed by slug",
            mimeType: "text/plain"
          },
          complete: ->(prefix) {
            ::Shared::PromptTemplate.for_account(@account.id).active
              .where("slug ILIKE ?", "#{sanitize_like(prefix)}%")
              .order(:slug).limit(COMPLETION_FETCH_LIMIT).pluck(:slug)
          }
        }
      }
    end

    def sanitize_like(value)
      ActiveRecord::Base.sanitize_sql_like(value.to_s)
    end

    def fetch_items(type, config, offset: 0)
      scope = config[:scope].call
      items = scope.offset(offset).limit(PAGE_SIZE + 1)

      {
        resources: items.first(PAGE_SIZE).map { |item| config[:to_resource].call(item) },
        has_more: items.size > PAGE_SIZE
      }
    end

    def fetch_content(type, identifier)
      case type
      when "kb/articles"
        article = KnowledgeBase::Article.for_account(@account.id).published.find_by(slug: identifier)
        return nil unless article
        { text: article.content, mime_type: "text/plain" }
      when "ai/agents"
        agent = ::Ai::Agent.for_account(@account.id).where(status: "active").find_by(id: identifier)
        return nil unless agent
        { text: agent_to_json(agent), mime_type: "application/json" }
      when "ai/prompts"
        template = ::Shared::PromptTemplate.for_account(@account.id).active.find_by(slug: identifier)
        return nil unless template
        { text: template.content, mime_type: "text/plain" }
      end
    end

    def parse_uri(uri)
      match = uri&.match(%r{\Apowernode://(.+?)/([^/]+)\z})
      return nil unless match

      # Handle nested types like "kb/articles" vs simple types like "ai/agents"
      full_path = match[1] + "/" + match[2]

      resource_types.each_key do |type|
        prefix = "powernode://#{type}/"
        if uri.start_with?(prefix)
          identifier = uri.delete_prefix(prefix)
          return { type: type, identifier: identifier } if identifier.present?
        end
      end

      nil
    end

    def parse_cursor(cursor)
      return [nil, 0] if cursor.blank?

      parts = cursor.split(":", 2)
      [parts[0], parts[1].to_i]
    end

    def build_next_cursor(resources, current_offset)
      "all:#{current_offset + PAGE_SIZE}"
    end

    def agent_to_json(agent)
      {
        id: agent.id,
        name: agent.name,
        description: agent.description,
        model: agent.model,
        status: agent.status,
        system_prompt: agent.system_prompt,
        created_at: agent.created_at.iso8601
      }.to_json
    end

  end
end
