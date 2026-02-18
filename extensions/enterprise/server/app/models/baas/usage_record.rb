# frozen_string_literal: true

module BaaS
  class UsageRecord < ApplicationRecord
    self.table_name = "baas_usage_records"

    # Associations
    belongs_to :baas_tenant, class_name: "BaaS::Tenant"

    # Validations
    validates :customer_external_id, presence: true
    validates :meter_id, presence: true
    validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :action, presence: true, inclusion: { in: %w[set increment] }
    validates :event_timestamp, presence: true
    validates :status, presence: true, inclusion: { in: %w[pending processed invoiced failed] }
    validates :idempotency_key, uniqueness: true, allow_nil: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :processed, -> { where(status: "processed") }
    scope :invoiced, -> { where(status: "invoiced") }
    scope :failed, -> { where(status: "failed") }
    scope :for_customer, ->(external_id) { where(customer_external_id: external_id) }
    scope :for_meter, ->(meter_id) { where(meter_id: meter_id) }
    scope :for_period, ->(start_date, end_date) { where(event_timestamp: start_date..end_date) }
    scope :in_billing_period, ->(start_date, end_date) { where(billing_period_start: start_date, billing_period_end: end_date) }

    # Class methods
    class << self
      def create_with_idempotency(tenant:, params:)
        if params[:idempotency_key].present?
          existing = tenant.usage_records.find_by(idempotency_key: params[:idempotency_key])
          return { success: true, record: existing, duplicate: true } if existing
        end

        record = tenant.usage_records.create!(
          customer_external_id: params[:customer_id],
          subscription_external_id: params[:subscription_id],
          meter_id: params[:meter_id],
          idempotency_key: params[:idempotency_key],
          quantity: params[:quantity],
          action: params[:action] || "increment",
          event_timestamp: params[:timestamp] || Time.current,
          billing_period_start: params[:billing_period_start],
          billing_period_end: params[:billing_period_end],
          properties: params[:properties] || {},
          metadata: params[:metadata] || {},
          status: "pending"
        )

        { success: true, record: record, duplicate: false }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def aggregate_for_customer(tenant:, customer_id:, meter_id:, start_date:, end_date:)
        records = tenant.usage_records
                        .for_customer(customer_id)
                        .for_meter(meter_id)
                        .for_period(start_date, end_date)
                        .where(status: %w[pending processed])

        # Process based on action type
        set_records = records.where(action: "set").order(event_timestamp: :desc)
        increment_records = records.where(action: "increment")

        # If there are "set" records, use the most recent one as base
        if set_records.exists?
          base_quantity = set_records.first.quantity
          # Add any increments after the last set
          increments_after_set = increment_records
                                  .where("event_timestamp > ?", set_records.first.event_timestamp)
                                  .sum(:quantity)
          base_quantity + increments_after_set
        else
          # Just sum all increments
          increment_records.sum(:quantity)
        end
      end

      def batch_create(tenant:, records:)
        results = { successful: 0, failed: 0, errors: [] }

        records.each_with_index do |params, index|
          result = create_with_idempotency(tenant: tenant, params: params)
          if result[:success]
            results[:successful] += 1
          else
            results[:failed] += 1
            results[:errors] << { index: index, error: result[:error] }
          end
        end

        results
      end
    end

    # Instance methods
    def pending?
      status == "pending"
    end

    def processed?
      status == "processed"
    end

    def invoiced?
      status == "invoiced"
    end

    def mark_processed!
      update!(status: "processed", processed_at: Time.current)
    end

    def mark_invoiced!(invoice_id)
      update!(status: "invoiced", invoice_id: invoice_id)
    end

    def mark_failed!(reason = nil)
      update!(
        status: "failed",
        metadata: metadata.merge(failure_reason: reason)
      )
    end

    def summary
      {
        id: id,
        customer_id: customer_external_id,
        subscription_id: subscription_external_id,
        meter_id: meter_id,
        quantity: quantity,
        action: action,
        timestamp: event_timestamp,
        status: status,
        billing_period: {
          start: billing_period_start,
          end: billing_period_end
        }
      }
    end
  end
end
