# frozen_string_literal: true

module Marketplace
  # Unified Subscription Orchestrator
  # Handles subscribing to any marketplace item type (apps, plugins, templates, integrations)
  class SubscriptionOrchestrator
    include ActiveModel::Model

    ITEM_TYPES = {
      "app" => "Marketplace::Definition",
      "plugin" => "PluginSystem::Definition",
      "template" => "Ai::WorkflowTemplate",
      "integration" => "PluginSystem::Definition"
    }.freeze

    attr_reader :account, :user, :errors

    def initialize(account:, user:)
      @account = account
      @user = user
      @errors = []
      @logger = Rails.logger
    end

    # Subscribe to a marketplace item
    def subscribe(item_type:, item_id:, options: {})
      @errors = []
      item = find_item(item_type, item_id)
      return failure("Item not found") unless item

      # Validate item is subscribable
      return failure("Item is not available for subscription") unless subscribable?(item, item_type)

      # Check if already subscribed
      if already_subscribed?(item)
        return failure("Already subscribed to this item")
      end

      # Create subscription based on type
      subscription = create_subscription(item, item_type, options)
      return failure(subscription.errors.full_messages.join(", ")) unless subscription.persisted?

      # Perform type-specific setup
      perform_type_specific_setup(subscription, item, item_type, options)

      @logger.info "[SUBSCRIPTION] Created subscription for #{item_type}: #{item.name} (Account: #{account.id})"

      success(subscription)
    rescue StandardError => e
      @logger.error "[SUBSCRIPTION] Failed to create subscription: #{e.message}"
      failure(e.message)
    end

    # Unsubscribe from a marketplace item
    def unsubscribe(subscription_id:, reason: nil)
      @errors = []
      subscription = account.subscriptions.find_by(id: subscription_id)
      return failure("Subscription not found") unless subscription

      if subscription.cancelled?
        return failure("Subscription is already cancelled")
      end

      unless subscription.cancel!(reason)
        return failure("Failed to cancel subscription")
      end

      # Perform type-specific cleanup
      perform_type_specific_cleanup(subscription)

      @logger.info "[SUBSCRIPTION] Cancelled subscription: #{subscription.id}"

      success(subscription)
    rescue StandardError => e
      @logger.error "[SUBSCRIPTION] Failed to cancel subscription: #{e.message}"
      failure(e.message)
    end

    # Get all subscriptions for the account
    def list_subscriptions(type: nil, status: nil)
      subscriptions = account_subscriptions
      subscriptions = subscriptions.for_type(type) if type.present?
      subscriptions = subscriptions.where(status: status) if status.present?
      subscriptions.includes(:subscribable).recent
    end

    # Check subscription status for an item
    def subscription_for(item)
      return nil unless item

      account_subscriptions.find_by(
        subscribable_type: item.class.name,
        subscribable_id: item.id
      )
    end

    # Check if account can subscribe to an item
    def can_subscribe?(item_type:, item_id:)
      item = find_item(item_type, item_id)
      return false unless item
      return false unless subscribable?(item, item_type)
      return false if already_subscribed?(item)
      true
    end

    private

    def account_subscriptions
      Marketplace::Subscription.where(account: account)
    end

    def find_item(item_type, item_id)
      klass = item_class(item_type)
      return nil unless klass

      klass.find_by(id: item_id)
    end

    def item_class(item_type)
      class_name = ITEM_TYPES[item_type.to_s]
      return nil unless class_name

      class_name.constantize
    rescue NameError
      nil
    end

    def subscribable?(item, item_type)
      case item_type.to_s
      when "app"
        item.published?
      when "plugin"
        item.status == "available" && !item.integration?
      when "template"
        item.published? && item.public?
      when "integration"
        item.status == "available" && item.integration?
      else
        false
      end
    end

    def already_subscribed?(item)
      account_subscriptions.exists?(
        subscribable_type: item.class.name,
        subscribable_id: item.id,
        status: %w[active paused]
      )
    end

    def create_subscription(item, item_type, options)
      subscription_params = {
        account: account,
        subscribable: item,
        status: "active",
        tier: options[:tier] || "standard",
        configuration: options[:configuration] || {},
        metadata: {
          subscribed_by_user_id: user.id,
          item_type: item_type,
          subscription_source: options[:source] || "marketplace"
        }
      }

      # For apps, also set legacy associations and plan
      if item_type.to_s == "app" && options[:plan_id].present?
        plan = item.plans.find_by(id: options[:plan_id])
        if plan
          subscription_params[:app_id] = item.id
          subscription_params[:app_plan_id] = plan.id
        end
      end

      Marketplace::Subscription.create(subscription_params)
    end

    def perform_type_specific_setup(subscription, item, item_type, options)
      case item_type.to_s
      when "app"
        setup_app_subscription(subscription, item, options)
      when "plugin"
        setup_plugin_subscription(subscription, item, options)
      when "template"
        setup_template_subscription(subscription, item, options)
      when "integration"
        setup_integration_subscription(subscription, item, options)
      end
    end

    def setup_app_subscription(subscription, app, options)
      # App subscriptions may need additional feature flags or permissions
      subscription.update_metadata("app_version", app.version)
      subscription.record_usage_metric("subscription_started", 1, { plan_id: subscription.app_plan_id })

      # Increment app subscription count
      app.record_metric("subscription", 1, { subscription_id: subscription.id }) if app.respond_to?(:record_metric)
    end

    def setup_plugin_subscription(subscription, plugin, options)
      # Record plugin version and capabilities
      subscription.update_metadata("plugin_version", plugin.version)
      subscription.update_metadata("capabilities", plugin.capabilities)

      # Update plugin statistics
      plugin.increment_install_count! if plugin.respond_to?(:increment_install_count!)
    end

    def setup_template_subscription(subscription, template, options)
      # Record template version
      subscription.update_metadata("template_version", template.version)
      subscription.update_metadata("difficulty_level", template.difficulty_level)

      # Increment template usage count
      template.increment!(:usage_count) if template.respond_to?(:usage_count)

      # If auto-create workflow is requested, create it
      if options[:create_workflow] && options[:workflow_name].present?
        create_workflow_from_template(subscription, template, options)
      end
    end

    def setup_integration_subscription(subscription, integration, options)
      # Similar to plugin setup
      subscription.update_metadata("integration_version", integration.version)
      subscription.update_metadata("integration_type", integration.manifest.dig("integration", "type"))

      # Update statistics
      integration.increment_install_count! if integration.respond_to?(:increment_install_count!)
    end

    def create_workflow_from_template(subscription, template, options)
      workflow = ::Ai::Workflow.create(
        account: account,
        name: options[:workflow_name],
        description: template.description,
        workflow_type: "template_based",
        nodes: template.workflow_nodes,
        edges: template.workflow_edges,
        variables: template.default_variables,
        status: "draft",
        created_by_user_id: user.id
      )

      if workflow.persisted?
        subscription.update_metadata("created_workflow_id", workflow.id)
        subscription.update_metadata("workflow_created_at", Time.current.iso8601)
      end

      workflow
    end

    def perform_type_specific_cleanup(subscription)
      case subscription.subscription_type
      when "app"
        cleanup_app_subscription(subscription)
      when "plugin"
        cleanup_plugin_subscription(subscription)
      when "template"
        cleanup_template_subscription(subscription)
      when "integration"
        cleanup_integration_subscription(subscription)
      end
    end

    def cleanup_app_subscription(subscription)
      # Log app unsubscription
      subscription.record_usage_metric("subscription_ended", 1)
    end

    def cleanup_plugin_subscription(subscription)
      # Plugin cleanup - could deactivate plugin resources
      subscription.record_usage_metric("subscription_ended", 1)
    end

    def cleanup_template_subscription(subscription)
      # Template subscriptions don't need special cleanup
      # Created workflows remain even after unsubscribing
      subscription.record_usage_metric("subscription_ended", 1)
    end

    def cleanup_integration_subscription(subscription)
      # Integration cleanup
      subscription.record_usage_metric("subscription_ended", 1)
    end

    def success(data)
      { success: true, data: data, errors: [] }
    end

    def failure(message)
      @errors << message
      { success: false, data: nil, errors: @errors }
    end
  end
end
