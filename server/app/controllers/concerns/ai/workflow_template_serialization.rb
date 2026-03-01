# frozen_string_literal: true

module Ai
  module WorkflowTemplateSerialization
    extend ActiveSupport::Concern

    private

    def serialize_template(template)
      {
        id: template.id,
        name: template.name,
        slug: template.slug,
        description: template.description,
        category: template.category,
        difficulty_level: template.difficulty_level,
        visibility: template.visibility,
        version: template.version,
        tags: template.tags,
        install_count: template.install_count,
        rating: template.rating,
        rating_count: template.rating_count,
        is_featured: template.is_featured,
        created_at: template.created_at.iso8601,
        created_by: template.created_by_user ? { id: template.created_by_user.id, name: template.created_by_user.full_name } : nil,
        can_install: template.can_install?(current_user&.account),
        can_edit: template.can_edit?(current_user, current_user&.account)
      }
    end

    def serialize_template_detail(template)
      serialize_template(template).merge(
        template_data: template.workflow_definition,
        configuration_schema: template.metadata&.dig("configuration_schema") || {},
        license: template.license,
        updated_at: template.updated_at.iso8601,
        can_delete: template.can_delete?(current_user, current_user&.account),
        can_publish: template.can_publish?(current_user, current_user&.account)
      )
    end
  end
end
