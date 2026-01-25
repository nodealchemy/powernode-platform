# frozen_string_literal: true

require "ostruct"

module AuditLogging
  extend ActiveSupport::Concern

  private

  def log_audit_event(action, resource = nil, **options)
    # Skip audit logging for index actions - they're just read operations
    return if action.to_s.end_with?(".index")

    # Extract resource from params if not provided
    resource ||= extract_resource_for_logging

    # Determine account for audit logging
    audit_account = if respond_to?(:current_worker) && current_worker&.active?
      # For worker requests, try to get account from resource or skip
      resource.respond_to?(:account) ? resource.account : nil
    else
      current_account || current_user&.account
    end

    # Use singleton instance of Audit::LoggingService
    # Note: Removed request_id and session_id as they're not in the AuditLog model schema
    Audit::LoggingService.instance.log(
      action: action.to_s,
      resource: resource,
      user: current_user,
      account: audit_account,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      source: (respond_to?(:current_worker) && current_worker&.active?) ? "worker" : "api",
      **options
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log audit event '#{action}': #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Re-raise in test environment to surface audit logging errors
    raise if Rails.env.test?
  end

  def log_resource_created(resource, **options)
    log_audit_event(
      "create",
      resource,
      new_values: resource_attributes_for_logging(resource),
      **options
    )
  end

  def log_resource_updated(resource, old_attributes = {}, **options)
    new_attributes = resource_attributes_for_logging(resource)

    log_audit_event(
      "update",
      resource,
      old_values: old_attributes,
      new_values: new_attributes,
      **options
    )
  end

  def log_resource_deleted(resource, **options)
    log_audit_event(
      "delete",
      resource,
      old_values: resource_attributes_for_logging(resource),
      **options
    )
  end

  def log_authentication_event(action, user = nil, **options)
    user ||= current_user

    Audit::LoggingService.instance.log_authentication(
      action: action.to_s,
      user: user,
      request: request,
      account: user&.account,
      **options
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log authentication event '#{action}': #{e.message}"
  end

  def log_admin_action(action, resource = nil, **options)
    resource ||= extract_resource_for_logging

    Audit::LoggingService.instance.log_admin_action(
      action: action.to_s,
      resource: resource,
      user: current_user,
      account: current_account || current_user&.account,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      source: "admin_panel",
      request_id: request.request_id,
      **options
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log admin action '#{action}': #{e.message}"
  end

  def log_security_event(action, resource = nil, threat_level: "medium", **options)
    resource ||= extract_resource_for_logging

    Audit::LoggingService.instance.log_security_event(
      action: action.to_s,
      resource: resource,
      user: current_user,
      account: current_account || current_user&.account,
      threat_level: threat_level,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      source: "api",
      request_id: request.request_id,
      **options
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log security event '#{action}': #{e.message}"
  end

  def log_data_access(action, resource = nil, data_classification: "internal", **options)
    resource ||= extract_resource_for_logging

    Audit::LoggingService.instance.log_data_access(
      action: action.to_s,
      resource: resource,
      user: current_user,
      account: current_account || current_user&.account,
      data_classification: data_classification,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      source: "api",
      request_id: request.request_id,
      **options
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log data access event '#{action}': #{e.message}"
  end

  def log_compliance_event(action, resource = nil, regulation:, **options)
    resource ||= extract_resource_for_logging

    Audit::LoggingService.instance.log_compliance_event(
      action: action.to_s,
      resource: resource,
      user: current_user,
      account: current_account || current_user&.account,
      regulation: regulation,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      source: "api",
      request_id: request.request_id,
      **options
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log compliance event '#{action}': #{e.message}"
  end

  # Convenience methods for common audit events
  def log_user_created(user, **options)
    log_resource_created(user, severity: "medium", **options)
  end

  def log_user_updated(user, old_attributes = {}, **options)
    log_resource_updated(user, old_attributes, severity: "medium", **options)
  end

  def log_user_deleted(user, **options)
    log_resource_deleted(user, severity: "high", **options)
  end

  def log_payment_processed(payment, **options)
    log_audit_event(
      "payment_completed",
      payment,
      new_values: {
        amount_cents: payment.amount_cents,
        status: payment.status,
        payment_method: payment.payment_method&.last4
      },
      data_classification: "confidential",
      severity: "high",
      **options
    )
  end

  def log_subscription_changed(subscription, old_status, new_status, **options)
    log_audit_event(
      "subscription_change",
      subscription,
      old_values: { status: old_status },
      new_values: { status: new_status },
      severity: "medium",
      **options
    )
  end

  def log_plan_changed(plan, changes = {}, **options)
    action = case
    when changes.key?("status") && changes["status"][1] == "active"
               "plan_activated"
    when changes.key?("status") && changes["status"][1] == "inactive"
               "plan_deactivated"
    when changes.key?("price_cents")
               "plan_price_updated"
    else
               "plan_updated"
    end

    log_audit_event(
      action,
      plan,
      old_values: changes.transform_values(&:first),
      new_values: changes.transform_values(&:last),
      severity: "medium",
      **options
    )
  end

  def log_api_access(action = "api_access", **options)
    log_audit_event(
      action,
      current_user || create_api_dummy_resource,
      data_classification: "internal",
      access_type: request.method&.downcase || "unknown",
      endpoint: "#{request.method} #{request.path}",
      severity: "low",
      **options
    )
  end

  def log_webhook_received(webhook_type, **options)
    log_audit_event(
      "webhook_received",
      create_webhook_dummy_resource(webhook_type),
      metadata: {
        webhook_type: webhook_type,
        payload_size: request.body.size,
        content_type: request.content_type
      }.merge(options[:metadata] || {}),
      severity: "medium",
      **options
    )
  end

  def log_failed_action(action, resource = nil, error_message = nil, **options)
    resource ||= extract_resource_for_logging

    log_audit_event(
      "#{action}_failed",
      resource,
      metadata: {
        error_message: error_message,
        failure_reason: options[:reason]
      }.merge(options[:metadata] || {}),
      severity: "high",
      **options
    )
  end

  private

  def extract_resource_for_logging
    # Try to extract resource from instance variables or params
    resource_candidates = [
      instance_variable_get(:@message),
      instance_variable_get(:@conversation),
      instance_variable_get(:@ai_agent),
      instance_variable_get(:@ai_provider),
      instance_variable_get(:@app),
      instance_variable_get(:@user),
      instance_variable_get(:@account),
      instance_variable_get(:@plan),
      instance_variable_get(:@subscription),
      instance_variable_get(:@payment),
      instance_variable_get(:@invoice),
      instance_variable_get(:@webhook),
      instance_variable_get(:@endpoint),
      instance_variable_get(:@feature),
      instance_variable_get(:@listing)
    ].compact.first

    # If no resource found, create a dummy based on controller
    resource_candidates || create_dummy_resource_from_controller
  end

  def create_dummy_resource_from_controller
    controller_name = self.class.name.demodulize.gsub("Controller", "").singularize

    ::OpenStruct.new(
      class: ::OpenStruct.new(name: controller_name),
      id: params[:id] || "unknown"
    )
  end

  def create_api_dummy_resource
    ::OpenStruct.new(
      class: ::OpenStruct.new(name: "API"),
      id: "#{request.method}:#{request.path}"
    )
  end

  def create_webhook_dummy_resource(webhook_type)
    ::OpenStruct.new(
      class: ::OpenStruct.new(name: "Webhook"),
      id: webhook_type.to_s
    )
  end

  def resource_attributes_for_logging(resource)
    return {} unless resource.respond_to?(:attributes)

    # Get safe attributes for logging (exclude sensitive data)
    safe_attributes = resource.attributes.except(
      "password_digest",
      "password",
      "encrypted_password",
      "reset_password_token",
      "confirmation_token",
      "api_secret",
      "access_token",
      "refresh_token"
    )

    # Include some computed attributes if available
    if resource.respond_to?(:status)
      safe_attributes["status"] = resource.status
    end

    if resource.respond_to?(:name)
      safe_attributes["name"] = resource.name
    end

    if resource.respond_to?(:email)
      safe_attributes["email"] = resource.email
    end

    safe_attributes.compact
  end

  def current_account
    # Try different ways to get current account
    return @current_account if defined?(@current_account)
    return current_user&.account if respond_to?(:current_user) && current_user
    return @account if defined?(@account)

    # Fallback to first account (for system operations)
    Account.first
  end
end
