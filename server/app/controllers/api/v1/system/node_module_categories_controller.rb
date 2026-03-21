# frozen_string_literal: true

module Api
  module V1
    module System
      class NodeModuleCategoriesController < BaseController
        before_action :set_category, only: [:show, :update, :destroy]

        # GET /api/v1/system/node_module_categories
        def index
          authorize_permission!('system.modules.read')

          categories = current_account.system_node_module_categories
          categories = apply_filters(categories)
          categories = paginate(categories.includes(:parent, :children).by_position)

          render_success(
            categories: categories.map { |c| ::System::NodeModuleCategorySerializer.new(c).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/node_module_categories/:id
        def show
          authorize_permission!('system.modules.read')
          render_success(category: ::System::NodeModuleCategorySerializer.new(@category).as_json)
        end

        # POST /api/v1/system/node_module_categories
        def create
          authorize_permission!('system.modules.create')

          category = current_account.system_node_module_categories.build(category_params)

          if category.save
            render_success(category: ::System::NodeModuleCategorySerializer.new(category).as_json, status: :created)
          else
            render_validation_error(category)
          end
        end

        # PATCH/PUT /api/v1/system/node_module_categories/:id
        def update
          authorize_permission!('system.modules.update')

          if @category.update(category_params)
            render_success(category: ::System::NodeModuleCategorySerializer.new(@category).as_json)
          else
            render_validation_error(@category)
          end
        end

        # DELETE /api/v1/system/node_module_categories/:id
        def destroy
          authorize_permission!('system.modules.delete')

          if @category.node_modules.exists?
            render_error('Cannot delete category with existing modules', status: :unprocessable_entity)
          else
            @category.destroy
            render_success(message: 'Category deleted successfully')
          end
        end

        private

        def set_category
          @category = current_account.system_node_module_categories.find(params[:id])
        end

        def category_params
          params.require(:category).permit(
            :name, :description, :enabled, :public, :icon, :color, :position, :parent_id
          )
        end

        def apply_filters(categories)
          categories = categories.enabled if params[:enabled] == 'true'
          categories = categories.disabled if params[:enabled] == 'false'
          categories = categories.public_categories if params[:public] == 'true'
          categories = categories.root_categories if params[:root_only] == 'true'
          categories = categories.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
          categories
        end
      end
    end
  end
end
