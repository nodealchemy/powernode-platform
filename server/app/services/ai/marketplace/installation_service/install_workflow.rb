# frozen_string_literal: true

module Ai
  module Marketplace
    class InstallationService
      module InstallWorkflow
        extend ActiveSupport::Concern

        # Install a template (creates workflow and subscription)
        # @param template_id [String] Template to install
        # @param custom_configuration [Hash] Custom configuration overrides
        # @param installation_notes [String] Optional installation notes
        # @return [Hash] Installation result with workflow and subscription
        def install(template_id:, custom_configuration: {}, installation_notes: nil)
          template = ::Ai::WorkflowTemplate.find(template_id)

          unless template.can_install?(account)
            return error_result("Template is not available for installation")
          end

          # Check if already installed
          existing = account.workflow_template_subscriptions
                           .where(subscribable: template)
                           .first

          if existing
            return error_result("Template is already installed")
          end

          ActiveRecord::Base.transaction do
            # Create workflow from template
            workflow = create_workflow_from_template(template, custom_configuration)

            unless workflow.persisted?
              raise InstallationError, workflow.errors.full_messages.join(", ")
            end

            # Create subscription
            subscription = template.subscribe_account(
              account_id: account.id,
              subscribed_by_user_id: user.id,
              subscription_notes: installation_notes
            )

            # Store workflow reference and configuration
            subscription.update!(
              configuration: custom_configuration,
              metadata: subscription.metadata.merge(
                "workflow_id" => workflow.id,
                "template_version" => template.version,
                "installed_by_email" => user.email
              )
            )

            # Increment template usage count
            template.increment!(:usage_count)

            {
              success: true,
              subscription: subscription,
              workflow: workflow,
              message: "Template installed successfully"
            }
          end
        rescue InstallationError => e
          error_result(e.message)
        rescue ActiveRecord::RecordInvalid => e
          error_result(e.record.errors.full_messages.join(", "))
        end

        # List all installations for the account
        # @param options [Hash] Filter and pagination options
        # @return [Hash] Installations with pagination
        def list_installations(options = {})
          subscriptions = account.workflow_template_subscriptions
                                 .where(subscribable_type: "Ai::WorkflowTemplate")
                                 .includes(:subscribable)
                                 .order(subscribed_at: :desc)

          # Filter by template category
          if options[:category].present?
            subscriptions = subscriptions.joins(
              "INNER JOIN ai_workflow_templates ON ai_workflow_templates.id = marketplace_subscriptions.subscribable_id"
            ).where("ai_workflow_templates.category = ?", options[:category])
          end

          # Pagination
          page = options[:page]&.to_i || 1
          per_page = [ options[:per_page]&.to_i || 25, 100 ].min

          total_count = subscriptions.count
          subscriptions = subscriptions.offset((page - 1) * per_page).limit(per_page)

          {
            installations: subscriptions.map { |sub| serialize_installation(sub) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: (total_count.to_f / per_page).ceil,
              total_count: total_count
            }
          }
        end

        # Get installation details
        # @param subscription_id [String] Subscription ID
        # @return [Hash] Installation details
        def get_installation(subscription_id)
          subscription = account.workflow_template_subscriptions.find(subscription_id)

          {
            success: true,
            installation: serialize_installation_detail(subscription)
          }
        rescue ActiveRecord::RecordNotFound
          error_result("Installation not found")
        end

        private

        def create_workflow_from_template(template, custom_configuration = {})
          workflow_data = template.workflow_definition.deep_symbolize_keys

          # Create workflow
          workflow = account.ai_workflows.create!(
            name: template.name,
            description: template.description,
            status: "draft",
            version: template.version,
            configuration: { enabled: true, from_template: true },
            creator: user
          )

          # Create nodes
          node_mapping = {}
          workflow_data[:nodes]&.each do |node_data|
            config = merge_configuration(node_data[:configuration], custom_configuration)
            config = { enabled: true } if config.blank?

            node = workflow.nodes.create!(
              node_id: node_data[:node_id],
              node_type: node_data[:node_type],
              name: node_data[:name],
              description: node_data[:description],
              configuration: config,
              position: node_data[:position]
            )
            node_mapping[node_data[:node_id]] = node
          end

          # Create edges
          workflow_data[:edges]&.each do |edge_data|
            source_node = node_mapping[edge_data[:source_node_id]]
            target_node = node_mapping[edge_data[:target_node_id]]

            next unless source_node && target_node

            edge_id = "#{edge_data[:source_node_id]}_to_#{edge_data[:target_node_id]}"

            workflow.edges.create!(
              edge_id: edge_id,
              source_node: source_node,
              target_node: target_node,
              edge_type: edge_data[:edge_type],
              condition: edge_data[:condition] || {},
              configuration: edge_data[:configuration] || {}
            )
          end

          # Create triggers
          workflow_data[:triggers]&.each do |trigger_data|
            workflow.triggers.create!(
              trigger_type: trigger_data[:trigger_type],
              name: trigger_data[:name],
              configuration: trigger_data[:configuration],
              is_active: trigger_data[:is_active]
            )
          end

          # Create variables
          workflow_data[:variables]&.each do |var_data|
            workflow.variables.create!(
              key: var_data[:key],
              value: var_data[:value],
              variable_type: var_data[:variable_type],
              description: var_data[:description],
              is_required: var_data[:is_required]
            )
          end

          workflow
        end

        def merge_configuration(default_config, *custom_configs)
          result = (default_config || {}).deep_dup

          custom_configs.each do |config|
            next if config.blank?
            result = result.deep_merge(config.deep_symbolize_keys)
          end

          result
        end
      end
    end
  end
end
