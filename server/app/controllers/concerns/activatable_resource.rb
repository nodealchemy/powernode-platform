# frozen_string_literal: true

# ActivatableResource Concern
# Provides standardized activate/deactivate actions for API controllers
# Consolidates duplicate activation logic across controllers
#
# Usage:
#   class Api::V1::WebhooksController < ApplicationController
#     include ActivatableResource
#
#     activatable_resource :app_webhook,
#                          permission: "apps.update",
#                          serializer: :webhook_data,
#                          resource_label: "Webhook"
#   end
#
# The controller must have a before_action that sets @app_webhook (or the
# configured resource name) before the activate/deactivate actions.
#
module ActivatableResource
  extend ActiveSupport::Concern

  class_methods do
    # Configure activatable resource
    # @param resource_name [Symbol] Instance variable name (e.g., :app_webhook)
    # @param options [Hash] Configuration options
    # @option options [String] :permission Permission required for activation
    # @option options [Symbol] :active_field Field to toggle (default: :is_active)
    # @option options [Symbol] :serializer Method name to serialize resource
    # @option options [String] :activate_message Custom message for activation
    # @option options [String] :deactivate_message Custom message for deactivation
    # @option options [String] :resource_label Human-readable name for messages
    def activatable_resource(resource_name, **options)
      @activatable_config ||= {}
      @activatable_config[resource_name] = {
        permission: options[:permission],
        active_field: options[:active_field] || :is_active,
        serializer: options[:serializer],
        activate_message: options[:activate_message],
        deactivate_message: options[:deactivate_message],
        resource_label: options[:resource_label] || resource_name.to_s.humanize
      }
    end

    def activatable_config
      @activatable_config || {}
    end
  end

  # Activate the resource
  def activate
    resource_name, config = find_activatable_resource
    return render_error("No activatable resource configured", status: :internal_server_error) unless resource_name

    authorize_permission!(config[:permission]) if config[:permission]

    resource = instance_variable_get("@#{resource_name}")
    return render_not_found(config[:resource_label]) unless resource

    # Check if model has activate! method
    if resource.respond_to?(:activate!)
      resource.activate!
    else
      resource.update!(config[:active_field] => true)
    end

    render_activation_response(resource, config, activated: true)
  end

  # Deactivate the resource
  def deactivate
    resource_name, config = find_activatable_resource
    return render_error("No activatable resource configured", status: :internal_server_error) unless resource_name

    authorize_permission!(config[:permission]) if config[:permission]

    resource = instance_variable_get("@#{resource_name}")
    return render_not_found(config[:resource_label]) unless resource

    # Check if model has deactivate! method
    if resource.respond_to?(:deactivate!)
      resource.deactivate!
    else
      resource.update!(config[:active_field] => false)
    end

    render_activation_response(resource, config, activated: false)
  end

  private

  def find_activatable_resource
    self.class.activatable_config.find do |resource_name, _config|
      instance_variable_get("@#{resource_name}").present?
    end
  end

  def render_activation_response(resource, config, activated:)
    message = if activated
                config[:activate_message] || "#{config[:resource_label]} activated successfully"
    else
                config[:deactivate_message] || "#{config[:resource_label]} deactivated successfully"
    end

    data = if config[:serializer]
             send(config[:serializer], resource)
    else
             { id: resource.id, active: resource.send(config[:active_field]) }
    end

    render_success(data: data, message: message)
  end
end
