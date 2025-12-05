# frozen_string_literal: true

class Api::V1::AppFeaturesController < ApplicationController
  include AuditLogging
  
  # Authentication is handled by ApplicationController's before_action :authenticate_request
  before_action :set_app
  before_action :authorize_app_access
  before_action :set_feature, only: [:show, :update, :destroy, :enable_by_default, :disable_by_default, :duplicate]
  
  def index
    features = @app.app_features.includes(:app)

    # Apply filters
    features = features.by_type(params[:type]) if params[:type].present?
    features = features.enabled_by_default if params[:default_enabled] == 'true'
    features = features.disabled_by_default if params[:default_enabled] == 'false'
    features = features.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?

    # Apply sorting
    case params[:sort]
    when 'name'
      features = features.order(:name)
    when 'type'
      features = features.order(:feature_type, :name)
    when 'created_at'
      features = features.order(created_at: :desc)
    else
      features = features.order(:name)
    end

    render_success(
      data: features.map { |feature| feature_data(feature) }
    )
  end
  
  def show
    render_success(
      data: feature_data(@feature, detailed: true)
    )
  end
  
  def create
    @feature = @app.app_features.build(feature_params)

    if @feature.save
      log_audit_event('app_feature_created', {
        app_id: @app.id,
        feature_id: @feature.id,
        feature_name: @feature.name,
        feature_type: @feature.feature_type
      })

      render_success(
        data: feature_data(@feature, detailed: true),
        message: 'App feature created successfully',
        status: :created
      )
    else
      render_validation_error(@feature)
    end
  end
  
  def update
    if @feature.update(feature_params)
      log_audit_event('app_feature_updated', {
        app_id: @app.id,
        feature_id: @feature.id,
        changes: @feature.previous_changes.keys
      })

      render_success(
        data: feature_data(@feature, detailed: true),
        message: 'App feature updated successfully'
      )
    else
      render_validation_error(@feature)
    end
  end
  
  def destroy
    feature_name = @feature.name

    if @feature.destroy
      log_audit_event('app_feature_deleted', {
        app_id: @app.id,
        feature_name: feature_name
      })

      render_success(
        message: 'App feature deleted successfully'
      )
    else
      render_validation_error(@feature)
    end
  end
  
  def enable_by_default
    if @feature.enable_by_default!
      log_audit_event('app_feature_enabled_by_default', {
        app_id: @app.id,
        feature_id: @feature.id,
        feature_name: @feature.name
      })

      render_success(
        data: feature_data(@feature, detailed: true),
        message: 'App feature enabled by default'
      )
    else
      render_validation_error(@feature)
    end
  end
  
  def disable_by_default
    if @feature.disable_by_default!
      log_audit_event('app_feature_disabled_by_default', {
        app_id: @app.id,
        feature_id: @feature.id,
        feature_name: @feature.name
      })

      render_success(
        data: feature_data(@feature, detailed: true),
        message: 'App feature disabled by default'
      )
    else
      render_validation_error(@feature)
    end
  end
  
  def duplicate
    new_name = params[:name] || "#{@feature.name} (Copy)"
    duplicated_feature = @feature.duplicate(new_name)

    if duplicated_feature.persisted?
      log_audit_event('app_feature_duplicated', {
        app_id: @app.id,
        original_feature_id: @feature.id,
        new_feature_id: duplicated_feature.id,
        new_feature_name: duplicated_feature.name
      })

      render_success(
        data: feature_data(duplicated_feature, detailed: true),
        message: 'App feature duplicated successfully',
        status: :created
      )
    else
      render_validation_error(duplicated_feature)
    end
  end
  
  def types
    render_success(
      data: {
        types: AppFeature::FEATURE_TYPES.map do |type|
          {
            value: type,
            label: type.humanize,
            description: feature_type_description(type)
          }
        end
      }
    )
  end
  
  def dependencies
    feature_dependencies = @app.app_features.where.not(id: params[:exclude_id]).map do |feature|
      {
        id: feature.id,
        name: feature.name,
        slug: feature.slug,
        feature_type: feature.feature_type
      }
    end

    render_success(
      data: feature_dependencies
    )
  end
  
  def validate_dependencies
    feature_id = params[:feature_id]
    dependency_slugs = params[:dependencies] || []

    feature = @app.app_features.find_by(id: feature_id) if feature_id

    validation_errors = []

    dependency_slugs.each do |slug|
      unless @app.app_features.exists?(slug: slug)
        validation_errors << "Feature '#{slug}' does not exist"
      end
    end

    if feature && dependency_slugs.include?(feature.slug)
      validation_errors << "Feature cannot depend on itself"
    end

    # Check for circular dependencies
    if feature && would_create_circular_dependency?(feature, dependency_slugs)
      validation_errors << "Dependencies would create a circular reference"
    end

    render_success(
      data: {
        valid: validation_errors.empty?,
        errors: validation_errors
      }
    )
  end
  
  def usage_report
    usage_data = @app.app_features.includes(:used_in_plans).map do |feature|
      {
        id: feature.id,
        name: feature.name,
        slug: feature.slug,
        feature_type: feature.feature_type,
        usage_count: feature.usage_count,
        active_usage_count: feature.active_usage_count,
        subscriber_count: feature.subscriber_count,
        used_in_plans: feature.used_in_plans.map do |plan|
          {
            id: plan.id,
            name: plan.name,
            is_active: plan.is_active
          }
        end
      }
    end

    render_success(
      data: {
        app: {
          id: @app.id,
          name: @app.name
        },
        features: usage_data,
        summary: {
          total_features: usage_data.count,
          used_features: usage_data.count { |f| f[:usage_count] > 0 },
          unused_features: usage_data.count { |f| f[:usage_count] == 0 }
        }
      }
    )
  end
  
  private
  
  def set_app
    @app = current_account.apps.find_by(id: params[:app_id])
    render_error('App not found', status: :not_found) unless @app
  end
  
  def authorize_app_access
    return true if @app.account == current_account
    return true if current_user.has_permission?('apps.manage')
    
    render_error('Unauthorized to access this app', status: :forbidden)
    false
  end
  
  def set_feature
    @feature = @app.app_features.find_by(id: params[:id])
    render_error('App feature not found', status: :not_found) unless @feature
  end
  
  def feature_params
    params.require(:app_feature).permit(
      :name, :slug, :feature_type, :description, :default_enabled,
      dependencies: [], configuration: {}
    )
  end
  
  def feature_data(feature, detailed: false)
    data = {
      id: feature.id,
      name: feature.name,
      slug: feature.slug,
      feature_type: feature.feature_type,
      description: feature.description,
      default_enabled: feature.default_enabled,
      dependencies: feature.dependencies,
      created_at: feature.created_at,
      updated_at: feature.updated_at,
      has_dependencies: feature.has_dependencies?,
      usage_count: feature.usage_count
    }
    
    if detailed
      data.merge!(
        configuration: feature.configuration,
        dependency_features: feature.dependency_features.map { |dep| 
          { id: dep.id, name: dep.name, slug: dep.slug } 
        },
        dependent_features: feature.dependent_features_list.map { |dep| 
          { id: dep.id, name: dep.name, slug: dep.slug } 
        },
        used_in_plans: feature.used_in_plans.map { |plan|
          { id: plan.id, name: plan.name, is_active: plan.is_active }
        },
        active_usage_count: feature.active_usage_count,
        subscriber_count: feature.subscriber_count,
        validation_errors: feature.validate_for_plan(OpenStruct.new(features: []))
      )
      
      # Add feature-type specific data
      case feature.feature_type
      when 'quota'
        data[:quota_limit] = feature.quota_limit
        data[:quota_period] = feature.quota_period
        data[:quota_reset_day] = feature.quota_reset_day
      when 'permission'
        data[:required_permission] = feature.required_permission
      when 'integration'
        data[:integration_provider] = feature.integration_provider
        data[:integration_config] = feature.integration_config
      when 'api_access'
        data[:api_endpoints] = feature.api_endpoints
        data[:api_methods] = feature.api_methods
      when 'ui_component'
        data[:ui_component_name] = feature.ui_component_name
        data[:ui_component_props] = feature.ui_component_props
      end
    end
    
    data
  end
  
  def feature_type_description(type)
    descriptions = {
      'toggle' => 'Simple on/off feature that can be enabled or disabled',
      'quota' => 'Feature with usage limits that reset periodically',
      'permission' => 'Feature that requires specific user permissions',
      'integration' => 'Feature that integrates with external services',
      'api_access' => 'Feature that provides access to specific API endpoints',
      'ui_component' => 'Feature that enables specific UI components'
    }
    descriptions[type] || 'Custom feature type'
  end
  
  def would_create_circular_dependency?(feature, dependency_slugs)
    # Build dependency graph
    all_deps = {}
    @app.app_features.each do |f|
      next if f.id == feature.id
      all_deps[f.slug] = f.dependencies
    end
    all_deps[feature.slug] = dependency_slugs
    
    # Check for cycles using DFS
    visited = Set.new
    rec_stack = Set.new
    
    has_cycle_dfs(feature.slug, visited, rec_stack, all_deps)
  end
  
  def has_cycle_dfs(current_slug, visited, rec_stack, all_deps)
    return false if visited.include?(current_slug)
    
    visited.add(current_slug)
    rec_stack.add(current_slug)
    
    deps = all_deps[current_slug] || []
    deps.each do |dep_slug|
      if !visited.include?(dep_slug) && has_cycle_dfs(dep_slug, visited, rec_stack, all_deps)
        return true
      elsif rec_stack.include?(dep_slug)
        return true
      end
    end
    
    rec_stack.delete(current_slug)
    false
  end
  
end