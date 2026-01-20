# frozen_string_literal: true

module Api
  module BaaS
    module V1
      class InvoicesController < Api::BaaS::BaseController
        before_action :require_invoices_scope

        # GET /api/baas/v1/invoices
        def index
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.list_invoices(
            status: params[:status],
            customer_id: params[:customer_id],
            page: params[:page],
            per_page: params[:per_page]
          )

          if result[:success]
            render_success(result[:invoices], meta: { pagination: result[:pagination] })
          else
            render_error(result[:error])
          end
        end

        # GET /api/baas/v1/invoices/:id
        def show
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.get_invoice(params[:id])

          if result[:success]
            render_success(result[:invoice])
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/baas/v1/invoices
        def create
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.create_invoice(invoice_params)

          if result[:success]
            render_success(result[:invoice], status: :created)
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # PATCH /api/baas/v1/invoices/:id
        def update
          invoice = current_tenant.invoices.find_by(external_id: params[:id])
          return render_error("Invoice not found", status: :not_found) unless invoice
          return render_error("Cannot update non-draft invoice") unless invoice.draft?

          if invoice.update(invoice_params.except(:line_items))
            render_success(invoice.summary)
          else
            render_error(invoice.errors.full_messages.join(", "))
          end
        end

        # DELETE /api/baas/v1/invoices/:id
        def destroy
          invoice = current_tenant.invoices.find_by(external_id: params[:id])
          return render_error("Invoice not found", status: :not_found) unless invoice
          return render_error("Cannot delete non-draft invoice") unless invoice.draft?

          invoice.destroy!
          head :no_content
        end

        # POST /api/baas/v1/invoices/:id/finalize
        def finalize
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.finalize_invoice(params[:id])

          if result[:success]
            render_success(result[:invoice], message: "Invoice finalized")
          else
            render_error(result[:error])
          end
        end

        # POST /api/baas/v1/invoices/:id/pay
        def pay
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.pay_invoice(params[:id], payment_params)

          if result[:success]
            render_success(result[:invoice], message: "Invoice marked as paid")
          else
            render_error(result[:error])
          end
        end

        # POST /api/baas/v1/invoices/:id/void
        def void
          service = ::BaaS::BillingApiService.new(tenant: current_tenant)
          result = service.void_invoice(params[:id], void_params)

          if result[:success]
            render_success(result[:invoice], message: "Invoice voided")
          else
            render_error(result[:error])
          end
        end

        # POST /api/baas/v1/invoices/:id/line_items
        def add_line_item
          invoice = current_tenant.invoices.find_by(external_id: params[:id])
          return render_error("Invoice not found", status: :not_found) unless invoice
          return render_error("Cannot modify non-draft invoice") unless invoice.draft?

          item = invoice.add_line_item(
            description: params[:description],
            amount_cents: params[:amount_cents] || (params[:amount].to_f * 100).to_i,
            quantity: params[:quantity] || 1,
            metadata: params[:metadata] || {}
          )

          render_success(item, message: "Line item added")
        end

        # DELETE /api/baas/v1/invoices/:id/line_items/:item_id
        def remove_line_item
          invoice = current_tenant.invoices.find_by(external_id: params[:id])
          return render_error("Invoice not found", status: :not_found) unless invoice
          return render_error("Cannot modify non-draft invoice") unless invoice.draft?

          invoice.remove_line_item(params[:item_id])
          render_success(message: "Line item removed")
        end

        private

        def require_invoices_scope
          require_scope("invoices")
        end

        def invoice_params
          params.permit(
            :customer_id, :subscription_id, :external_id, :currency,
            :due_date, :period_start, :period_end, metadata: {},
            line_items: [:description, :amount_cents, :amount, :quantity, metadata: {}]
          )
        end

        def payment_params
          params.permit(:payment_reference)
        end

        def void_params
          params.permit(:reason)
        end
      end
    end
  end
end
