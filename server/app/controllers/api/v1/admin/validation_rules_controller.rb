# frozen_string_literal: true

class Api::V1::Admin::ValidationRulesController < ApplicationController
  before_action :authenticate_request
  before_action :require_read_permission, only: [ :index, :show ]
  before_action :require_write_permission, only: [ :create, :update, :destroy, :enable, :disable ]
  before_action :set_validation_rule, only: [ :show, :update, :destroy, :enable, :disable ]

  # GET /api/v1/admin/validation_rules
  def index
    rules = ValidationRule.all.order(created_at: :desc)

    # Filter by category if provided
    rules = rules.where(category: params[:category]) if params[:category].present?

    # Filter by severity if provided
    rules = rules.where(severity: params[:severity]) if params[:severity].present?

    # Filter by enabled status
    rules = rules.enabled if params[:enabled] == "true"
    rules = rules.disabled if params[:enabled] == "false"

    # Filter by auto_fixable
    rules = rules.auto_fixable if params[:auto_fixable] == "true"

    render_success({
      validation_rules: rules.map { |rule| serialize_validation_rule(rule) },
      meta: {
        total: rules.count,
        enabled_count: ValidationRule.enabled.count,
        disabled_count: ValidationRule.disabled.count,
        categories: ValidationRule.distinct.pluck(:category),
        severities: ValidationRule.distinct.pluck(:severity)
      }
    })
  rescue StandardError => e
    Rails.logger.error "Failed to list validation rules: #{e.message}"
    render_error("Failed to list validation rules", status: :internal_server_error)
  end

  # GET /api/v1/admin/validation_rules/:id
  def show
    render_success({
      validation_rule: serialize_validation_rule(@validation_rule, include_details: true)
    })
  rescue StandardError => e
    Rails.logger.error "Failed to get validation rule: #{e.message}"
    render_error("Failed to get validation rule", status: :internal_server_error)
  end

  # POST /api/v1/admin/validation_rules
  def create
    rule = ValidationRule.new(validation_rule_params)

    if rule.save
      render_success({
        validation_rule: serialize_validation_rule(rule),
        message: "Validation rule created successfully"
      }, status: :created)
    else
      render_validation_error(rule.errors)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to create validation rule: #{e.message}"
    render_error("Failed to create validation rule", status: :internal_server_error)
  end

  # PATCH/PUT /api/v1/admin/validation_rules/:id
  def update
    if @validation_rule.update(validation_rule_params)
      render_success({
        validation_rule: serialize_validation_rule(@validation_rule),
        message: "Validation rule updated successfully"
      })
    else
      render_validation_error(@validation_rule.errors)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to update validation rule: #{e.message}"
    render_error("Failed to update validation rule", status: :internal_server_error)
  end

  # DELETE /api/v1/admin/validation_rules/:id
  def destroy
    @validation_rule.destroy!

    render_success({
      message: "Validation rule deleted successfully"
    })
  rescue StandardError => e
    Rails.logger.error "Failed to delete validation rule: #{e.message}"
    render_error("Failed to delete validation rule", status: :internal_server_error)
  end

  # PATCH /api/v1/admin/validation_rules/:id/enable
  def enable
    if @validation_rule.update(enabled: true)
      render_success({
        validation_rule: serialize_validation_rule(@validation_rule),
        message: "Validation rule enabled successfully"
      })
    else
      render_validation_error(@validation_rule.errors)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to enable validation rule: #{e.message}"
    render_error("Failed to enable validation rule", status: :internal_server_error)
  end

  # PATCH /api/v1/admin/validation_rules/:id/disable
  def disable
    if @validation_rule.update(enabled: false)
      render_success({
        validation_rule: serialize_validation_rule(@validation_rule),
        message: "Validation rule disabled successfully"
      })
    else
      render_validation_error(@validation_rule.errors)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to disable validation rule: #{e.message}"
    render_error("Failed to disable validation rule", status: :internal_server_error)
  end

  private

  def set_validation_rule
    @validation_rule = ValidationRule.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Validation rule not found", status: :not_found)
  end

  def require_read_permission
    unless current_user.has_permission?("admin.validation_rules.read")
      render_error("Insufficient permissions to view validation rules", status: :forbidden)
    end
  end

  def require_write_permission
    unless current_user.has_permission?("admin.validation_rules.write")
      render_error("Insufficient permissions to manage validation rules", status: :forbidden)
    end
  end

  def validation_rule_params
    params.require(:validation_rule).permit(
      :name,
      :description,
      :category,
      :severity,
      :enabled,
      :auto_fixable,
      configuration: {}
    )
  end

  def serialize_validation_rule(rule, include_details: false)
    result = {
      id: rule.id,
      name: rule.name,
      description: rule.description,
      category: rule.category,
      severity: rule.severity,
      enabled: rule.enabled,
      auto_fixable: rule.auto_fixable,
      created_at: rule.created_at,
      updated_at: rule.updated_at
    }

    if include_details
      result.merge!({
        configuration: rule.configuration
      })
    end

    result
  end
end
