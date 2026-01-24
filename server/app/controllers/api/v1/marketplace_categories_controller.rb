# frozen_string_literal: true

module Api
  module V1
    class MarketplaceCategoriesController < ApplicationController
      before_action :authenticate_request
      before_action :require_read_permission, only: [:index, :show, :analytics]
      before_action :require_admin_permission, only: [:create, :update, :destroy, :activate, :deactivate, :reorder, :bulk_reorder]
      before_action :set_category, only: [:show, :update, :destroy, :activate, :deactivate, :analytics]

      # GET /api/v1/marketplace_categories
      def index
        @categories = MarketplaceCategory.includes(:parent, :children)
                                         .order(position: :asc, name: :asc)

        @categories = @categories.active if params[:active_only] == "true"
        @categories = @categories.root_categories if params[:root_only] == "true"

        if params[:parent_id].present?
          @categories = @categories.where(parent_id: params[:parent_id])
        end

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
        @category.position = MarketplaceCategory.where(parent_id: @category.parent_id).maximum(:position).to_i + 1

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
        if @category.children.any?
          return render_error("Cannot delete category with subcategories", status: :unprocessable_entity)
        end

        if @category.apps.any?
          return render_error("Cannot delete category with associated apps", status: :unprocessable_entity)
        end

        @category.destroy
        render_success(message: "Category deleted")
      end

      # POST /api/v1/marketplace_categories/:id/activate
      def activate
        @category.update!(status: "active")
        render_success(
          { category: serialize_category(@category) },
          message: "Category activated"
        )
      end

      # POST /api/v1/marketplace_categories/:id/deactivate
      def deactivate
        @category.update!(status: "inactive")
        render_success(
          { category: serialize_category(@category) },
          message: "Category deactivated"
        )
      end

      # POST /api/v1/marketplace_categories/:id/reorder
      def reorder
        new_position = params[:position].to_i

        if new_position < 1
          return render_error("Invalid position", status: :unprocessable_entity)
        end

        siblings = MarketplaceCategory.where(parent_id: @category.parent_id)
                                      .where.not(id: @category.id)
                                      .order(:position)

        # Reorder siblings
        siblings.each_with_index do |sibling, index|
          pos = index + 1
          pos += 1 if pos >= new_position
          sibling.update_column(:position, pos)
        end

        @category.update_column(:position, new_position)

        render_success(
          { category: serialize_category(@category) },
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
            MarketplaceCategory.where(id: category_id).update_all(position: index + 1)
          end
        end

        render_success(message: "Categories reordered")
      end

      # GET /api/v1/marketplace_categories/:id/analytics
      def analytics
        time_range = params[:range] || "30d"
        since = parse_time_range(time_range)

        apps_in_category = @category.all_descendant_app_ids

        analytics = {
          app_count: apps_in_category.count,
          total_installs: MarketplaceAppInstall.where(app_id: apps_in_category).count,
          installs_in_period: MarketplaceAppInstall.where(app_id: apps_in_category)
                                                   .where("created_at >= ?", since)
                                                   .count,
          total_reviews: MarketplaceAppReview.where(app_id: apps_in_category).count,
          average_rating: MarketplaceAppReview.where(app_id: apps_in_category).average(:rating)&.round(2),
          views_in_period: MarketplaceCategoryView.where(category: @category)
                                                  .where("viewed_at >= ?", since)
                                                  .count,
          top_apps: MarketplaceApp.where(id: apps_in_category)
                                  .order(install_count: :desc)
                                  .limit(5)
                                  .map { |a| { id: a.id, name: a.name, installs: a.install_count } }
        }

        render_success({
          category: serialize_category(@category),
          analytics: analytics,
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
          :name, :slug, :description, :icon, :color,
          :parent_id, :status, :featured,
          metadata: {}
        )
      end

      def serialize_category(category, include_details: false)
        data = {
          id: category.id,
          name: category.name,
          slug: category.slug,
          description: category.description,
          icon: category.icon,
          color: category.color,
          status: category.status,
          featured: category.featured,
          position: category.position,
          app_count: category.app_count,
          parent_id: category.parent_id,
          depth: category.depth,
          created_at: category.created_at
        }

        if include_details
          data[:children] = category.children.order(:position).map { |c| serialize_category(c) }
          data[:breadcrumb] = category.ancestors.map { |a| { id: a.id, name: a.name, slug: a.slug } }
          data[:metadata] = category.metadata
        end

        data
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
    end
  end
end
