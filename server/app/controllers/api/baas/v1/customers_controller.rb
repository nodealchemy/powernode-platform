# frozen_string_literal: true

module Api
  module BaaS
    module V1
      class CustomersController < Api::BaaS::BaseController
        before_action :require_customers_scope

        # GET /api/baas/v1/customers
        def index
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.list_customers(
            status: params[:status],
            email: params[:email],
            page: params[:page],
            per_page: params[:per_page]
          )

          if result[:success]
            render_success(result[:customers], meta: { pagination: result[:pagination] })
          else
            render_error(result[:error])
          end
        end

        # GET /api/baas/v1/customers/:id
        def show
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.get_customer(params[:id])

          if result[:success]
            render_success(result[:customer])
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/baas/v1/customers
        def create
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.create_customer(customer_params)

          if result[:success]
            render_success(result[:customer], status: :created)
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # PATCH /api/baas/v1/customers/:id
        def update
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.update_customer(params[:id], customer_params)

          if result[:success]
            render_success(result[:customer])
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # DELETE /api/baas/v1/customers/:id
        def destroy
          customer = current_tenant.customers.find_by(external_id: params[:id])
          return render_error("Customer not found", status: :not_found) unless customer

          if customer.has_active_subscriptions?
            return render_error("Cannot delete customer with active subscriptions")
          end

          customer.archive!
          render_success(message: "Customer archived")
        end

        private

        def require_customers_scope
          require_scope("customers")
        end

        def customer_params
          params.permit(
            :external_id, :email, :name, :address_line1, :address_line2,
            :city, :state, :postal_code, :country, :tax_id, :tax_id_type,
            :tax_exempt, :currency, metadata: {}
          )
        end
      end
    end
  end
end
