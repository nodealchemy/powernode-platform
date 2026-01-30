# frozen_string_literal: true

module Api
  module V1
    class MarketplaceCategoriesController < ApplicationController
      before_action :authenticate_request
      before_action :require_read_permission, only: [:index, :show, :analytics]
      before_action :require_admin_permission, only: [:create, :update, :destroy, :activate, :deactivate, :reorder, :bulk_reorder]
      before_action :set_category, only: [:show, :update, :destroy, :activate, :deactivate, :reorder, :analytics]

      # GET /api/v1/marketplace_categories
      def index
        @categories = MarketplaceCategory.order(sort_order: :asc, name: :asc)

        @categories = @categories.active if params[:active_only] == "true"

        render_success({
          categories: @categories.map { |c| serialize_category(c) }
        })
      end

      # GET /api/v1/marketplace_categories/:id
      def show
        render_success({ category: serialize_category(@category, include_details: true) })
      end

      # POST /api/v1/marketplace_categories
      def create
        @category = MarketplaceCategory.new(category_params)
        @category.sort_order = MarketplaceCategory.maximum(:sort_order).to_i + 1

        if @category.save
          render_success({ category: serialize_category(@category) }, status: :created)
        else
          render_error(@category.errors.full_messages.join(", "), status: :unprocessable_entity)
        end
      end

      # PATCH/PUT /api/v1/marketplace_categories/:id
      def update
        if @category.update(category_params)
          render_success({ category: serialize_category(@category) })
        else
          render_error(@category.errors.full_messages.join(", "), status: :unprocessable_entity)
        end
      end

      # DELETE /api/v1/marketplace_categories/:id
      def destroy
        if apps_table_exists? && @category.apps.any?
          return render_error("Cannot delete category with associated apps", status: :unprocessable_entity)
        end

        @category.destroy
        render_success(message: "Category deleted")
      end

      # POST /api/v1/marketplace_categories/:id/activate
      def activate
        @category.update!(is_active: true)
        render_success(
          { category: serialize_category(@category) },
          message: "Category activated"
        )
      end

      # POST /api/v1/marketplace_categories/:id/deactivate
      def deactivate
        @category.update!(is_active: false)
        render_success(
          { category: serialize_category(@category) },
          message: "Category deactivated"
        )
      end

      # POST /api/v1/marketplace_categories/:id/reorder
      def reorder
        new_sort_order = params[:position].to_i

        if new_sort_order < 1
          return render_error("Invalid position", status: :unprocessable_entity)
        end

        @category.update_column(:sort_order, new_sort_order)

        render_success(
          { category: serialize_category(@category.reload) },
          message: "Category reordered"
        )
      end

      # POST /api/v1/marketplace_categories/bulk_reorder
      def bulk_reorder
        order = params[:order] || []

        if order.empty?
          return render_error("Order array is required", status: :unprocessable_entity)
        end

        ActiveRecord::Base.transaction do
          order.each_with_index do |category_id, index|
            MarketplaceCategory.where(id: category_id).update_all(sort_order: index + 1)
          end
        end

        render_success(message: "Categories reordered")
      end

      # GET /api/v1/marketplace_categories/:id/analytics
      def analytics
        time_range = params[:range] || "30d"

        analytics_data = {
          app_count: apps_table_exists? ? @category.total_apps_count : 0,
          total_installs: 0,
          installs_in_period: 0,
          total_reviews: 0,
          average_rating: apps_table_exists? ? @category.average_app_rating : 0.0
        }

        render_success({
          category: serialize_category(@category),
          analytics: analytics_data,
          time_range: time_range
        })
      end

      private

      def require_read_permission
        return if current_user.has_permission?("marketplace.read")
        render_error("Insufficient permissions", status: :forbidden)
      end

      def require_admin_permission
        return if current_user.has_permission?("marketplace.admin")
        render_error("Insufficient permissions", status: :forbidden)
      end

      def set_category
        @category = MarketplaceCategory.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error("Category not found", status: :not_found)
      end

      def category_params
        params.require(:category).permit(
          :name, :slug, :description, :icon, :is_active, :sort_order
        )
      end

      def serialize_category(category, include_details: false)
        {
          id: category.id,
          name: category.name,
          slug: category.slug,
          description: category.description,
          icon: category.icon,
          is_active: category.is_active,
          sort_order: category.sort_order,
          created_at: category.created_at
        }
      end

      def parse_time_range(range)
        case range
        when "7d" then 7.days.ago
        when "30d" then 30.days.ago
        when "90d" then 90.days.ago
        when "1y" then 1.year.ago
        else 30.days.ago
        end
      end

      def apps_table_exists?
        ActiveRecord::Base.connection.table_exists?("apps")
      end
    end
  end
end
