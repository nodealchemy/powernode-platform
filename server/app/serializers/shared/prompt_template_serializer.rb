# frozen_string_literal: true

module Shared
  class PromptTemplateSerializer
    def initialize(template, options = {})
      @template = template
      @options = options
    end

    def as_json
      {
        id: @template.id,
        name: @template.name,
        slug: @template.slug,
        description: @template.description,
        category: @template.category,
        domain: @template.domain,
        content: @template.content,
        variables: @template.variables || {},
        is_active: @template.is_active,
        is_system: @template.is_system,
        version: @template.version,
        usage_count: @template.usage_count,
        variable_names: @template.extract_variables,
        created_by_name: @template.created_by&.name,
        parent_template_id: @template.parent_template_id,
        created_at: @template.created_at,
        updated_at: @template.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(template, options = {})
      new(template, options).as_json
    end

    def self.serialize_collection(templates, options = {})
      templates.map { |template| serialize(template, options) }
    end
  end
end
