# frozen_string_literal: true

module Ai
  module Marketplace
    # Service for managing template installations and subscriptions
    #
    # Provides installation management including:
    # - Template installation with workflow creation
    # - Installation tracking and history
    # - Update checking and application
    # - Uninstallation
    # - Rating management
    #
    # Usage:
    #   service = Ai::Marketplace::InstallationService.new(account: current_account, user: current_user)
    #   result = service.install(template_id: 'uuid', custom_configuration: {})
    #
    class InstallationService
      attr_reader :account, :user

      class InstallationError < StandardError; end

      def initialize(account:, user:)
        @account = account
        @user = user
      end

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
        per_page = [options[:per_page]&.to_i || 25, 100].min

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

      # Rate a template
      # @param template_id [String] Template to rate
      # @param rating [Integer] Rating value (1-5)
      # @param feedback [Hash] Optional feedback data
      # @return [Hash] Rating result
      def rate_template(template_id:, rating:, feedback: {})
        template = ::Ai::WorkflowTemplate.find(template_id)

        unless rating.between?(1, 5)
          return error_result("Rating must be between 1 and 5")
        end

        # Check if user has installed this template
        subscription = account.workflow_template_subscriptions
                              .find_by(subscribable: template)

        unless subscription
          return error_result("You must install a template before rating it")
        end

        # Check if already rated
        existing_rating = subscription.metadata&.dig("rating")
        if existing_rating && !feedback[:allow_update]
          return error_result("You have already rated this template")
        end

        ActiveRecord::Base.transaction do
          # Update running average
          if existing_rating
            # Recalculate removing old rating
            current_total = template.rating * template.rating_count
            new_total = current_total - existing_rating + rating
            new_average = new_total / template.rating_count.to_f
            template.update!(rating: new_average.round(2))
          else
            # Add new rating
            current_total = template.rating * template.rating_count
            new_total = current_total + rating
            new_count = template.rating_count + 1
            new_average = new_total / new_count.to_f
            template.update!(
              rating: new_average.round(2),
              rating_count: new_count
            )
          end

          # Store rating in subscription metadata
          subscription.update!(
            metadata: subscription.metadata.merge(
              "rating" => rating,
              "rating_feedback" => feedback,
              "rated_at" => Time.current.iso8601
            )
          )

          {
            success: true,
            template_id: template.id,
            rating: rating,
            new_average: template.rating,
            total_ratings: template.rating_count,
            message: existing_rating ? "Rating updated successfully" : "Template rated successfully"
          }
        end
      rescue ActiveRecord::RecordNotFound
        error_result("Template not found")
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
              position: node_data[:position]
            )
          end
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

      def serialize_installation(subscription)
        template = subscription.subscribable
        workflow_id = subscription.metadata&.dig("workflow_id")

        {
          id: subscription.id,
          template_id: template&.id,
          template_name: template&.name,
          template_category: template&.category,
          installed_version: subscription.metadata&.dig("template_version"),
          installed_at: subscription.subscribed_at&.iso8601 || subscription.created_at.iso8601,
          workflow_id: workflow_id,
          has_update: template && subscription.metadata&.dig("template_version") != template.version
        }
      end

      def serialize_installation_detail(subscription)
        template = subscription.subscribable
        workflow_id = subscription.metadata&.dig("workflow_id")
        workflow = workflow_id ? account.ai_workflows.find_by(id: workflow_id) : nil

        serialize_installation(subscription).merge(
          template: template ? {
            id: template.id,
            name: template.name,
            description: template.description,
            category: template.category,
            difficulty_level: template.difficulty_level,
            version: template.version,
            rating: template.rating,
            rating_count: template.rating_count
          } : nil,
          workflow: workflow ? {
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            status: workflow.status,
            created_at: workflow.created_at.iso8601
          } : nil,
          custom_configuration: subscription.configuration,
          user_rating: subscription.metadata&.dig("rating"),
          installation_notes: subscription.subscription_notes
        )
      end

      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end
