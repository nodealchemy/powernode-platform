# frozen_string_literal: true

module BaaS
  class UsageMeteringService
    attr_reader :tenant

    def initialize(tenant:)
      @tenant = tenant
    end

    # Record a single usage event
    def record_usage(params)
      return { success: false, error: "Tenant not found" } unless tenant

      result = BaaS::UsageRecord.create_with_idempotency(tenant: tenant, params: params)

      if result[:success]
        if result[:duplicate]
          { success: true, record: result[:record].summary, duplicate: true }
        else
          { success: true, record: result[:record].summary }
        end
      else
        { success: false, error: result[:error] }
      end
    end

    # Record batch of usage events (up to 1000)
    def record_batch(events)
      return { success: false, error: "Tenant not found" } unless tenant
      return { success: false, error: "Events required" } if events.blank?
      return { success: false, error: "Maximum 1000 events per batch" } if events.size > 1000

      result = BaaS::UsageRecord.batch_create(tenant: tenant, records: events)

      {
        success: true,
        successful: result[:successful],
        failed: result[:failed],
        errors: result[:errors]
      }
    end

    # Get aggregated usage for a customer and meter
    def get_usage(customer_id:, meter_id:, start_date: nil, end_date: nil)
      return { success: false, error: "Tenant not found" } unless tenant

      start_date ||= Date.current.beginning_of_month
      end_date ||= Date.current.end_of_month

      quantity = BaaS::UsageRecord.aggregate_for_customer(
        tenant: tenant,
        customer_id: customer_id,
        meter_id: meter_id,
        start_date: start_date.beginning_of_day,
        end_date: end_date.end_of_day
      )

      {
        success: true,
        usage: {
          customer_id: customer_id,
          meter_id: meter_id,
          period: { start: start_date, end: end_date },
          total_quantity: quantity
        }
      }
    end

    # Get usage summary for a customer
    def customer_usage_summary(customer_id:, start_date: nil, end_date: nil)
      return { success: false, error: "Tenant not found" } unless tenant

      start_date ||= Date.current.beginning_of_month
      end_date ||= Date.current.end_of_month

      records = tenant.usage_records
                      .for_customer(customer_id)
                      .for_period(start_date.beginning_of_day, end_date.end_of_day)

      # Group by meter
      by_meter = records.group(:meter_id).sum(:quantity)

      {
        success: true,
        summary: {
          customer_id: customer_id,
          period: { start: start_date, end: end_date },
          total_events: records.count,
          meters: by_meter.map { |meter_id, quantity| { meter_id: meter_id, quantity: quantity } }
        }
      }
    end

    # Get pending usage records for invoicing
    def pending_for_invoice(customer_id:, billing_period_end:)
      return { success: false, error: "Tenant not found" } unless tenant

      records = tenant.usage_records
                      .for_customer(customer_id)
                      .pending
                      .where("event_timestamp <= ?", billing_period_end.end_of_day)
                      .order(event_timestamp: :asc)

      # Group and aggregate by meter
      aggregated = {}
      records.each do |record|
        aggregated[record.meter_id] ||= { records: [], total: 0 }
        aggregated[record.meter_id][:records] << record
        aggregated[record.meter_id][:total] += record.quantity if record.action == "increment"
      end

      {
        success: true,
        usage: aggregated.map do |meter_id, data|
          {
            meter_id: meter_id,
            total_quantity: data[:total],
            record_count: data[:records].size,
            record_ids: data[:records].map(&:id)
          }
        end
      }
    end

    # Mark usage records as processed
    def mark_processed(record_ids)
      return { success: false, error: "Tenant not found" } unless tenant

      count = tenant.usage_records
                    .where(id: record_ids, status: "pending")
                    .update_all(status: "processed", processed_at: Time.current)

      { success: true, processed_count: count }
    end

    # Mark usage records as invoiced
    def mark_invoiced(record_ids, invoice_id:)
      return { success: false, error: "Tenant not found" } unless tenant

      count = tenant.usage_records
                    .where(id: record_ids, status: "processed")
                    .update_all(status: "invoiced", invoice_id: invoice_id)

      { success: true, invoiced_count: count }
    end

    # List usage records with filtering
    def list_records(params = {})
      return { success: false, error: "Tenant not found" } unless tenant

      records = tenant.usage_records
      records = records.for_customer(params[:customer_id]) if params[:customer_id].present?
      records = records.for_meter(params[:meter_id]) if params[:meter_id].present?
      records = records.where(status: params[:status]) if params[:status].present?

      if params[:start_date].present? && params[:end_date].present?
        records = records.for_period(params[:start_date], params[:end_date])
      end

      records = records.order(event_timestamp: :desc)

      # Pagination
      page = params[:page] || 1
      per_page = [ params[:per_page]&.to_i || 25, 100 ].min
      paginated = records.page(page).per(per_page)

      {
        success: true,
        records: paginated.map(&:summary),
        pagination: {
          current_page: paginated.current_page,
          per_page: paginated.limit_value,
          total_pages: paginated.total_pages,
          total_count: paginated.total_count
        }
      }
    end

    # Usage analytics
    def analytics(start_date:, end_date:)
      return { success: false, error: "Tenant not found" } unless tenant

      records = tenant.usage_records.for_period(start_date, end_date)

      # Daily breakdown
      daily = records.group("DATE(event_timestamp)").sum(:quantity)

      # By meter
      by_meter = records.group(:meter_id).sum(:quantity)

      # By customer (top 10)
      by_customer = records.group(:customer_external_id)
                           .sum(:quantity)
                           .sort_by { |_, v| -v }
                           .first(10)
                           .to_h

      # Status breakdown
      by_status = records.group(:status).count

      {
        success: true,
        analytics: {
          period: { start: start_date, end: end_date },
          total_events: records.count,
          total_quantity: records.sum(:quantity),
          daily_breakdown: daily.map { |date, qty| { date: date, quantity: qty } },
          by_meter: by_meter.map { |meter, qty| { meter_id: meter, quantity: qty } },
          top_customers: by_customer.map { |cust, qty| { customer_id: cust, quantity: qty } },
          by_status: by_status
        }
      }
    end
  end
end
