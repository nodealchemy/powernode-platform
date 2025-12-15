# frozen_string_literal: true

class Api::V1::AppsController < ApplicationController
  include AuditLogging

  # Authentication is handled by ApplicationController's before_action :authenticate_request
  before_action :set_app, only: [ :show, :update, :destroy, :publish, :unpublish, :submit_for_review ]
  before_action :authorize_app_access, only: [ :show, :update, :destroy, :publish, :unpublish, :submit_for_review ]

  def index
    # For admin marketplace management, show all apps. Otherwise, show only account apps.
    has_admin_permission = current_user.permission_names.include?("admin.marketplace.manage")

    if has_admin_permission
      apps = App.includes(:app_plans, :app_features, :marketplace_listing, :account)
    else
      apps = current_account.apps.includes(:app_plans, :app_features, :marketplace_listing)
    end

    # Apply filters
    apps = apps.where(status: params[:status]) if params[:status].present?
    apps = apps.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

    # Apply sorting
    case params[:sort]
    when "name"
      apps = apps.order(:name)
    when "created_at"
      apps = apps.order(created_at: :desc)
    when "updated_at"
      apps = apps.order(updated_at: :desc)
    else
      apps = apps.order(created_at: :desc)
    end

    # Manual pagination
    page = params[:page]&.to_i || 1
    per_page = [ params[:per_page]&.to_i || 20, 100 ].min

    total_count = apps.count
    total_pages = (total_count / per_page.to_f).ceil
    offset = (page - 1) * per_page

    apps = apps.limit(per_page).offset(offset)

    render_success(
      data: apps.map { |app| app_data(app) },
      meta: {
        pagination: {
          current_page: page,
          total_pages: total_pages,
          total_count: total_count,
          per_page: per_page
        }
      }
    )
  end

  def show
    render_success(
      data: app_data(@app, detailed: true)
    )
  end

  def create
    @app = current_account.apps.build(app_params)
    @app.status = "draft"
    @app.version = "1.0.0"

    if @app.save
      log_audit_event("app_created", { app_id: @app.id, app_name: @app.name })

      render_success(
        data: app_data(@app, detailed: true),
        message: "App created successfully",
        status: :created
      )
    else
      render_validation_error(@app)
    end
  end

  def update
    if @app.update(app_params)
      log_audit_event("app_updated", { app_id: @app.id, changes: @app.previous_changes.keys })

      render_success(
        data: app_data(@app, detailed: true),
        message: "App updated successfully"
      )
    else
      render_validation_error(@app)
    end
  end

  def destroy
    app_name = @app.name

    if @app.destroy
      log_audit_event("app_deleted", { app_name: app_name })

      render_success(
        message: "App deleted successfully"
      )
    else
      render_validation_error(@app)
    end
  end

  def publish
    return render_error("App must be in review status to publish", status: :unprocessable_content) unless @app.under_review?

    if @app.publish!
      log_audit_event("app_published", { app_id: @app.id, app_name: @app.name })

      render_success(
        data: app_data(@app, detailed: true),
        message: "App published successfully"
      )
    else
      render_validation_error(@app)
    end
  end

  def unpublish
    return render_error("App must be published to unpublish", status: :unprocessable_content) unless @app.published?

    if @app.unpublish!
      log_audit_event("app_unpublished", { app_id: @app.id, app_name: @app.name })

      render_success(
        data: app_data(@app, detailed: true),
        message: "App unpublished successfully"
      )
    else
      render_validation_error(@app)
    end
  end

  def submit_for_review
    return render_error("App must be in draft status to submit for review", status: :unprocessable_content) unless @app.draft?

    if @app.submit_for_review!
      log_audit_event("app_submitted_for_review", { app_id: @app.id, app_name: @app.name })

      render_success(
        data: app_data(@app, detailed: true),
        message: "App submitted for review successfully"
      )
    else
      render_validation_error(@app)
    end
  end

  def analytics
    return render_error("App not found", status: :not_found) unless set_app
    return render_error("Unauthorized", status: :forbidden) unless authorize_app_access

    analytics_data = {
      subscription_count: @app.subscription_count,
      active_subscriptions: @app.active_subscriptions_count,
      total_revenue: @app.total_revenue,
      monthly_revenue: @app.monthly_revenue,
      average_rating: @app.average_rating,
      total_reviews: @app.total_reviews,
      download_count: @app.download_count,
      recent_activity: @app.recent_activity_summary
    }

    render_success(
      data: analytics_data
    )
  end

  private

  def set_app
    @app = current_account.apps.find_by(id: params[:id])
    render_error("App not found", status: :not_found) unless @app
  end

  def authorize_app_access
    return true if @app.account == current_account
    return true if current_user.has_permission?("apps.manage")

    render_error("Unauthorized to access this app", status: :forbidden)
    false
  end

  def app_params
    params.require(:app).permit(
      :name, :slug, :description, :short_description, :category, :icon, :homepage_url,
      :documentation_url, :support_url, :repository_url, :license, :privacy_policy_url,
      :terms_of_service_url, tags: [], configuration: {},
      metadata: {}
    )
  end

  def app_data(app, detailed: false)
    data = {
      id: app.id,
      name: app.name,
      slug: app.slug,
      description: app.description,
      short_description: app.short_description,
      category: app.category,
      icon: app.icon,
      status: app.status,
      version: app.version,
      tags: app.tags,
      created_at: app.created_at,
      updated_at: app.updated_at,
      published_at: app.published_at,
      homepage_url: app.homepage_url,
      documentation_url: app.documentation_url,
      support_url: app.support_url,
      account: app.account ? {
        id: app.account.id,
        name: app.account.name
      } : nil
    }

    if detailed
      data.merge!(
        repository_url: app.repository_url,
        license: app.license,
        privacy_policy_url: app.privacy_policy_url,
        terms_of_service_url: app.terms_of_service_url,
        configuration: app.configuration,
        metadata: app.metadata,
        plans_count: app.app_plans.count,
        features_count: app.app_features.count,
        subscriptions_count: app.subscription_count,
        average_rating: app.average_rating,
        total_reviews: app.total_reviews,
        total_revenue: app.total_revenue,
        plans: app.app_plans.active.map { |plan| plan_summary_data(plan) },
        features: app.app_features.map { |feature| feature_summary_data(feature) }
      )
    end

    data
  end

  def plan_summary_data(plan)
    {
      id: plan.id,
      name: plan.name,
      slug: plan.slug,
      price_cents: plan.price_cents,
      billing_interval: plan.billing_interval,
      is_active: plan.is_active,
      features_count: plan.features.length
    }
  end

  def feature_summary_data(feature)
    {
      id: feature.id,
      name: feature.name,
      slug: feature.slug,
      feature_type: feature.feature_type,
      default_enabled: feature.default_enabled
    }
  end
end
