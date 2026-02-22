# frozen_string_literal: true

module Ai
  module Marketplace
    class InstallationService
      module UpdateAndUninstall
        extend ActiveSupport::Concern

        # Uninstall a template (removes subscription, optionally workflow)
        # @param subscription_id [String] Subscription to remove
        # @param delete_workflow [Boolean] Whether to also delete the created workflow
        # @return [Hash] Uninstallation result
        def uninstall(subscription_id:, delete_workflow: false)
          subscription = account.workflow_template_subscriptions.find(subscription_id)

          workflow_id = subscription.metadata&.dig("workflow_id")

          ActiveRecord::Base.transaction do
            # Optionally delete the created workflow
            if delete_workflow && workflow_id
              workflow = account.ai_workflows.find_by(id: workflow_id)
              workflow&.destroy
            end

            # Decrement template usage count
            template = subscription.subscribable
            template&.decrement!(:usage_count) if template.respond_to?(:usage_count)

            subscription.destroy

            {
              success: true,
              deleted_workflow: delete_workflow && workflow_id.present?,
              message: "Template uninstalled successfully"
            }
          end
        rescue ActiveRecord::RecordNotFound
          error_result("Installation not found")
        end

        # Check for available updates
        # @return [Array<Hash>] Available updates
        def check_for_updates
          subscriptions = account.workflow_template_subscriptions
                                 .where(subscribable_type: "Ai::WorkflowTemplate")
                                 .includes(:subscribable)

          updates = subscriptions.filter_map do |subscription|
            template = subscription.subscribable
            next unless template.is_a?(::Ai::WorkflowTemplate)

            installed_version = subscription.metadata&.dig("template_version")
            next unless installed_version && template.version != installed_version

            {
              subscription_id: subscription.id,
              template_id: template.id,
              template_name: template.name,
              current_version: installed_version,
              latest_version: template.version,
              changes: template.metadata&.dig("changelog", template.version),
              workflow_id: subscription.metadata&.dig("workflow_id")
            }
          end

          {
            updates_available: updates,
            total_count: updates.size
          }
        end

        # Apply update to a single installation
        # @param subscription_id [String] Subscription to update
        # @param preserve_customizations [Boolean] Whether to preserve custom config
        # @return [Hash] Update result
        def apply_update(subscription_id:, preserve_customizations: true)
          subscription = account.workflow_template_subscriptions.find(subscription_id)
          template = subscription.subscribable

          unless template.is_a?(::Ai::WorkflowTemplate)
            return error_result("Invalid subscription type")
          end

          installed_version = subscription.metadata&.dig("template_version")
          if installed_version == template.version
            return error_result("Template is already up to date")
          end

          workflow_id = subscription.metadata&.dig("workflow_id")
          workflow = workflow_id ? account.ai_workflows.find_by(id: workflow_id) : nil

          ActiveRecord::Base.transaction do
            if workflow
              # Update existing workflow
              update_workflow_from_template(
                workflow,
                template,
                preserve_customizations ? subscription.configuration : {}
              )
            else
              # Create new workflow if missing
              workflow = create_workflow_from_template(template, subscription.configuration)
            end

            # Update subscription metadata
            subscription.update!(
              metadata: subscription.metadata.merge(
                "template_version" => template.version,
                "updated_at" => Time.current.iso8601,
                "updated_by_email" => user.email,
                "previous_version" => installed_version
              )
            )

            {
              success: true,
              subscription: subscription,
              workflow: workflow,
              previous_version: installed_version,
              new_version: template.version,
              message: "Template updated successfully"
            }
          end
        rescue ActiveRecord::RecordNotFound
          error_result("Installation not found")
        rescue ActiveRecord::RecordInvalid => e
          error_result(e.record.errors.full_messages.join(", "))
        end

        # Apply updates to all installations
        # @param preserve_customizations [Boolean] Whether to preserve custom config
        # @return [Hash] Bulk update results
        def apply_all_updates(preserve_customizations: true)
          updates = check_for_updates[:updates_available]

          results = {
            total_attempted: updates.size,
            successful: 0,
            failed: 0,
            details: []
          }

          updates.each do |update|
            result = apply_update(
              subscription_id: update[:subscription_id],
              preserve_customizations: preserve_customizations
            )

            if result[:success]
              results[:successful] += 1
              results[:details] << { template: update[:template_name], status: "updated" }
            else
              results[:failed] += 1
              results[:details] << { template: update[:template_name], status: "failed", error: result[:error] }
            end
          end

          results
        end

        private

        def update_workflow_from_template(workflow, template, custom_configuration = {})
          workflow_data = template.workflow_definition.deep_symbolize_keys

          # Update workflow attributes
          workflow.update!(
            description: template.description,
            version: template.version
          )

          # Update nodes - preserve existing custom configurations
          existing_nodes = workflow.nodes.index_by(&:node_id)

          workflow_data[:nodes]&.each do |node_data|
            existing_node = existing_nodes[node_data[:node_id]]

            if existing_node
              # Preserve customizations
              merged_config = merge_configuration(
                node_data[:configuration],
                custom_configuration,
                existing_node.configuration
              )

              existing_node.update!(
                name: node_data[:name],
                description: node_data[:description],
                configuration: merged_config,
                position: node_data[:position]
              )
            else
              # Create new node
              workflow.nodes.create!(
                node_id: node_data[:node_id],
                node_type: node_data[:node_type],
                name: node_data[:name],
                description: node_data[:description],
                configuration: node_data[:configuration] || { enabled: true },
                position: node_data[:position],
                is_start_node: node_data[:node_type] == "start",
                is_end_node: node_data[:node_type] == "end"
              )
            end
          end

          workflow
        end
      end
    end
  end
end
