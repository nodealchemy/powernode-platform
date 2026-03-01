# frozen_string_literal: true

module Api
  module V1
    module Marketing
      class EmailListsController < ApplicationController
        before_action :set_email_list, only: %i[show update destroy import subscribers add_subscriber remove_subscriber]

        # GET /api/v1/marketing/email_lists
        def index
          authorize_read!

          scope = current_user.account.marketing_email_lists
          scope = scope.by_type(params[:list_type]) if params[:list_type].present?
          scope = scope.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:list_summary),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/marketing/email_lists/:id
        def show
          authorize_read!

          render_success(email_list: @email_list.list_details)
        end

        # POST /api/v1/marketing/email_lists
        def create
          authorize_manage!

          email_list = current_user.account.marketing_email_lists.build(email_list_params)

          if email_list.save
            render_success({ email_list: email_list.list_details }, status: :created)
          else
            render_error(email_list.errors.full_messages, status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/marketing/email_lists/:id
        def update
          authorize_manage!

          if @email_list.update(email_list_params)
            render_success(email_list: @email_list.list_details)
          else
            render_error(@email_list.errors.full_messages, status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/marketing/email_lists/:id
        def destroy
          authorize_manage!

          @email_list.destroy!
          render_success(message: "Email list deleted successfully")
        end

        # POST /api/v1/marketing/email_lists/:id/import
        def import
          authorize_manage!

          subscribers_data = params.require(:subscribers).map do |s|
            s.permit(:email, :first_name, :last_name, :source, tags: [], custom_fields: {}).to_h.symbolize_keys
          end

          service = ::Marketing::EmailCampaignService.new(nil)
          result = service.import_subscribers(@email_list, subscribers_data)

          render_success(import_result: result)
        end

        # GET /api/v1/marketing/email_lists/:id/subscribers
        def subscribers
          authorize_read!

          scope = @email_list.email_subscribers
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:subscriber_summary),
            pagination: pagination_data(scope)
          )
        end

        # POST /api/v1/marketing/email_lists/:id/add_subscriber
        def add_subscriber
          authorize_manage!

          subscriber = @email_list.email_subscribers.build(subscriber_params)
          subscriber.status ||= @email_list.double_opt_in? ? "pending" : "subscribed"
          subscriber.source ||= "manual"
          subscriber.subscribed_at = Time.current unless @email_list.double_opt_in?

          if subscriber.save
            render_success({ subscriber: subscriber.subscriber_summary }, status: :created)
          else
            render_error(subscriber.errors.full_messages, status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/marketing/email_lists/:id/remove_subscriber
        def remove_subscriber
          authorize_manage!

          subscriber = @email_list.email_subscribers.find(params[:subscriber_id])
          subscriber.destroy!

          render_success(message: "Subscriber removed successfully")
        end

        private

        def set_email_list
          @email_list = current_user.account.marketing_email_lists.find(params[:id])
        end

        def email_list_params
          params.require(:email_list).permit(
            :name, :list_type, :double_opt_in,
            :welcome_email_subject, :welcome_email_body,
            dynamic_filter: {}
          )
        end

        def subscriber_params
          params.require(:subscriber).permit(
            :email, :first_name, :last_name, :source,
            tags: [],
            custom_fields: {},
            preferences: {}
          )
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [params[:per_page]&.to_i || 25, 100].min
          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        def authorize_read!
          return if current_user.has_permission?("marketing.email_lists.read")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_manage!
          return if current_user.has_permission?("marketing.email_lists.manage")

          render_error("Insufficient permissions", status: :forbidden)
        end
      end
    end
  end
end
