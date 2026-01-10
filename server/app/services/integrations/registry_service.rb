# frozen_string_literal: true

module Integrations
  class RegistryService
    class RegistryError < StandardError; end
    class TemplateNotFoundError < RegistryError; end
    class InstanceNotFoundError < RegistryError; end
    class ValidationError < RegistryError; end

    class << self
      # ==================== Template Management ====================

      # List all available templates
      def list_templates(filters: {}, page: 1, per_page: 20)
        scope = Integration::Template.all

        scope = scope.where(integration_type: filters[:type]) if filters[:type].present?
        scope = scope.where(category: filters[:category]) if filters[:category].present?
        scope = scope.where(is_public: true) if filters[:public_only]
        scope = scope.featured if filters[:featured]
        scope = scope.active if filters[:active_only] != false

        scope.order(usage_count: :desc, name: :asc)
             .page(page)
             .per(per_page)
      end

      # Get template by ID or slug
      def find_template(identifier)
        template = if uuid?(identifier)
          Integration::Template.find_by(id: identifier)
        else
          Integration::Template.find_by(slug: identifier)
        end

        raise TemplateNotFoundError, "Template not found: #{identifier}" unless template

        template
      end

      # Create a new template (admin only)
      def create_template(attributes)
        template = Integration::Template.new(attributes)

        validate_template_schema!(template)

        template.save!
        template
      rescue ActiveRecord::RecordInvalid => e
        raise ValidationError, e.message
      end

      # Update template (admin only)
      def update_template(identifier, attributes)
        template = find_template(identifier)

        template.assign_attributes(attributes)
        validate_template_schema!(template)

        template.save!
        template
      rescue ActiveRecord::RecordInvalid => e
        raise ValidationError, e.message
      end

      # ==================== Instance Management ====================

      # List instances for an account
      def list_instances(account:, filters: {}, page: 1, per_page: 20)
        scope = Integration::Instance.where(account: account)

        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.joins(:template)
                     .where(integration_templates: { integration_type: filters[:type] }) if filters[:type].present?

        scope.includes(:template, :credential)
             .order(created_at: :desc)
             .page(page)
             .per(per_page)
      end

      # Find instance by ID
      def find_instance(account:, instance_id:)
        instance = Integration::Instance
          .where(account: account)
          .includes(:template, :credential)
          .find_by(id: instance_id)

        raise InstanceNotFoundError, "Instance not found: #{instance_id}" unless instance

        instance
      end

      # Install a template (create an instance)
      def install_template(account:, template_identifier:, attributes: {}, created_by: nil)
        template = find_template(template_identifier)

        instance = Integration::Instance.new(
          account: account,
          template: template,
          created_by_user: created_by,
          name: attributes[:name] || template.name,
          slug: attributes[:slug] || generate_slug(template.name, account),
          configuration: merge_configuration(template.default_configuration, attributes[:configuration]),
          status: "pending"
        )

        # Associate credential if provided
        if attributes[:credential_id].present?
          credential = Integration::Credential.find_by(id: attributes[:credential_id], account: account)
          raise ValidationError, "Invalid credential" unless credential

          instance.credential = credential
        end

        ActiveRecord::Base.transaction do
          instance.save!
          template.increment!(:usage_count)
        end

        instance
      rescue ActiveRecord::RecordInvalid => e
        raise ValidationError, e.message
      end

      # Uninstall an instance
      def uninstall_instance(account:, instance_id:)
        instance = find_instance(account: account, instance_id: instance_id)

        ActiveRecord::Base.transaction do
          instance.template.decrement!(:usage_count)
          instance.destroy!
        end

        true
      end

      # Update instance configuration
      def update_instance(account:, instance_id:, attributes:)
        instance = find_instance(account: account, instance_id: instance_id)

        if attributes[:configuration].present?
          attributes[:configuration] = merge_configuration(
            instance.configuration,
            attributes[:configuration]
          )
        end

        instance.update!(attributes.slice(:name, :configuration, :status))
        instance
      rescue ActiveRecord::RecordInvalid => e
        raise ValidationError, e.message
      end

      # Activate an instance
      def activate_instance(account:, instance_id:)
        instance = find_instance(account: account, instance_id: instance_id)

        # Validate configuration and credentials before activation
        executor = build_executor(instance)
        test_result = executor.test_connection

        unless test_result[:success]
          raise ValidationError, "Connection test failed: #{test_result[:error]}"
        end

        instance.update!(status: "active", activated_at: Time.current)
        instance
      end

      # Deactivate an instance
      def deactivate_instance(account:, instance_id:)
        instance = find_instance(account: account, instance_id: instance_id)
        instance.update!(status: "paused", deactivated_at: Time.current)
        instance
      end

      # ==================== Credential Management ====================

      # Create credentials for an account
      def create_credential(account:, attributes:, created_by: nil)
        credential = Integration::Credential.new(
          account: account,
          created_by_user: created_by,
          name: attributes[:name],
          credential_type: attributes[:credential_type],
          scopes: attributes[:scopes] || [],
          metadata: attributes[:metadata] || {}
        )

        ActiveRecord::Base.transaction do
          credential.save!

          if attributes[:credentials].present?
            Integrations::CredentialEncryptionService.encrypt(credential, attributes[:credentials])
          end
        end

        credential
      rescue ActiveRecord::RecordInvalid => e
        raise ValidationError, e.message
      end

      # Update credentials
      def update_credential(account:, credential_id:, attributes:)
        credential = Integration::Credential.find_by(id: credential_id, account: account)
        raise InstanceNotFoundError, "Credential not found: #{credential_id}" unless credential

        ActiveRecord::Base.transaction do
          credential.update!(attributes.slice(:name, :scopes, :metadata))

          if attributes[:credentials].present?
            Integrations::CredentialEncryptionService.encrypt(credential, attributes[:credentials])
          end
        end

        credential
      rescue ActiveRecord::RecordInvalid => e
        raise ValidationError, e.message
      end

      # Delete credentials
      def delete_credential(account:, credential_id:)
        credential = Integration::Credential.find_by(id: credential_id, account: account)
        raise InstanceNotFoundError, "Credential not found: #{credential_id}" unless credential

        # Check if credential is in use
        if Integration::Instance.where(credential: credential).exists?
          raise ValidationError, "Credential is in use by one or more integrations"
        end

        credential.destroy!
        true
      end

      # ==================== Discovery & Search ====================

      # Search templates by query
      def search_templates(query:, filters: {}, page: 1, per_page: 20)
        scope = Integration::Template.where(is_public: true)

        if query.present?
          scope = scope.where(
            "name ILIKE :q OR description ILIKE :q OR category ILIKE :q",
            q: "%#{query}%"
          )
        end

        scope = scope.where(integration_type: filters[:type]) if filters[:type].present?
        scope = scope.where(category: filters[:category]) if filters[:category].present?

        scope.order(usage_count: :desc)
             .page(page)
             .per(per_page)
      end

      # Get template categories
      def template_categories
        Integration::Template
          .where(is_public: true)
          .group(:category)
          .count
          .sort_by { |_, count| -count }
          .to_h
      end

      # Get integration types
      def integration_types
        Integration::Template::INTEGRATION_TYPES
      end

      private

      def uuid?(string)
        string.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end

      def generate_slug(name, account)
        base_slug = name.parameterize
        slug = base_slug
        counter = 1

        while Integration::Instance.exists?(account: account, slug: slug)
          slug = "#{base_slug}-#{counter}"
          counter += 1
        end

        slug
      end

      def merge_configuration(base, overrides)
        return base if overrides.blank?

        (base || {}).deep_merge(overrides || {})
      end

      def validate_template_schema!(template)
        errors = []

        if template.configuration_schema.present?
          unless valid_json_schema?(template.configuration_schema)
            errors << "Invalid configuration schema"
          end
        end

        if template.input_schema.present?
          unless valid_json_schema?(template.input_schema)
            errors << "Invalid input schema"
          end
        end

        if template.output_schema.present?
          unless valid_json_schema?(template.output_schema)
            errors << "Invalid output schema"
          end
        end

        raise ValidationError, errors.join(", ") if errors.any?
      end

      def valid_json_schema?(schema)
        return false unless schema.is_a?(Hash)

        # Basic JSON Schema validation
        schema.key?("type") || schema.key?("properties") || schema.key?("$ref")
      end

      def build_executor(instance)
        Integrations::ExecutionService.build_executor(instance)
      end
    end
  end
end
