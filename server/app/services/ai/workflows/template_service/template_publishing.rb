# frozen_string_literal: true

module Ai
  module Workflows
    class TemplateService
      module TemplatePublishing
        extend ActiveSupport::Concern

        # Publish a template to the marketplace
        # @param template [Ai::WorkflowTemplate] Template to publish
        # @param options [Hash] Publishing options
        # @return [Result] Result object
        def publish_template(template, options = {})
          validate_template_ownership!(template)

          # Validate template is ready for publishing
          validation = validate_for_publishing(template)
          return validation if validation.failure?

          template.assign_attributes(
            is_public: options[:is_public] || true,
            is_featured: options[:is_featured] || false,
            published_at: Time.current,
            version: bump_version(template.version, options[:version_bump] || "patch")
          )

          if template.save
            Result.success(template: template)
          else
            Result.failure(error: template.errors.full_messages.join(", "))
          end
        end

        # Update template version
        # @param template [Ai::WorkflowTemplate] Template to update
        # @param changes [Hash] Changes to apply
        # @param version_bump [String] Version bump type (major, minor, patch)
        # @return [Result] Result object
        def update_template_version(template, changes:, version_bump: "patch")
          validate_template_ownership!(template)

          new_version = bump_version(template.version, version_bump)

          template.assign_attributes(changes.merge(
            version: new_version,
            metadata: template.metadata.merge(
              "version_history" => (template.metadata["version_history"] || []) + [
                {
                  version: template.version,
                  updated_at: Time.current.iso8601,
                  updated_by: user.id
                }
              ]
            )
          ))

          if template.save
            Result.success(template: template)
          else
            Result.failure(error: template.errors.full_messages.join(", "))
          end
        end

        # Export template as JSON
        # @param template [Ai::WorkflowTemplate] Template to export
        # @return [Result] Result object with export data
        def export_template(template)
          {
            name: template.name,
            description: template.description,
            version: template.version,
            category: template.category,
            difficulty_level: template.difficulty_level,
            tags: template.tags,
            license: template.license,
            workflow_definition: template.workflow_definition,
            configuration_schema: template.metadata&.dig("configuration_schema"),
            exported_at: Time.current.iso8601,
            exported_by: user.email
          }

          Result.success(export_data: export_data)
        end

        # Import template from JSON
        # @param import_data [Hash] Imported template data
        # @return [Result] Result object with template
        def import_template(import_data)
          template = ::Ai::WorkflowTemplate.new(
            name: import_data["name"],
            description: import_data["description"],
            version: import_data["version"] || "1.0.0",
            category: import_data["category"] || "imported",
            difficulty_level: import_data["difficulty_level"] || "intermediate",
            tags: import_data["tags"] || [],
            license: import_data["license"] || "private",
            is_public: false,
            workflow_definition: import_data["workflow_definition"],
            account: account,
            created_by_user: user,
            author_name: user.full_name,
            author_email: user.email,
            metadata: {
              imported_at: Time.current.iso8601,
              original_exported_at: import_data["exported_at"],
              configuration_schema: import_data["configuration_schema"]
            }
          )

          if template.save
            Result.success(template: template)
          else
            Result.failure(error: template.errors.full_messages.join(", "))
          end
        end

        private

        # Validate template is ready for publishing
        # @param template [Ai::WorkflowTemplate] Template to validate
        # @return [Result] Validation result
        def validate_for_publishing(template)
          errors = []

          errors << "Template must have a name" if template.name.blank?
          errors << "Template must have a description" if template.description.blank?
          errors << "Template must have a workflow definition" if template.workflow_definition.blank?
          errors << "Template must have at least one node" if (template.workflow_definition&.dig("nodes") || []).empty?

          if errors.any?
            Result.failure(error: errors.join(", "))
          else
            Result.success
          end
        end

        # Bump version number
        # @param version [String] Current version
        # @param bump_type [String] Type of bump (major, minor, patch)
        # @return [String] New version
        def bump_version(version, bump_type)
          parts = (version || "1.0.0").split(".").map(&:to_i)
          parts = [ 1, 0, 0 ] if parts.length < 3

          case bump_type.to_s
          when "major"
            parts[0] += 1
            parts[1] = 0
            parts[2] = 0
          when "minor"
            parts[1] += 1
            parts[2] = 0
          else # patch
            parts[2] += 1
          end

          parts.join(".")
        end

        def validate_template_ownership!(template)
          unless template.account_id == account.id
            raise OwnershipError, "Template does not belong to this account"
          end
        end
      end
    end
  end
end
