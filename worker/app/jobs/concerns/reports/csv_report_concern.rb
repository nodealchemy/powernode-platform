# frozen_string_literal: true

module Reports
  module CsvReportConcern
    extend ActiveSupport::Concern

    private

    # The server's /analytics/export endpoint pre-renders the CSV body and
    # returns it under `csv_data`. We use that verbatim — re-rendering on the
    # worker side just duplicates the pivot logic and drifts.
    def generate_csv_report(report_request)
      report_data = with_api_retry do
        backend_api_client.get_report_data(
          report_request['report_type'],
          report_request['account_id'],
          report_request['parameters'] || {}
        )
      end

      csv_body = report_data.is_a?(Hash) ? report_data['csv_data'] : nil
      return csv_body if csv_body.present?

      # Fallback for endpoints that hand back tabular data rather than pre-rendered CSV.
      require 'csv'
      CSV.generate do |csv|
        headers = get_csv_headers(report_request['report_type'])
        csv << headers
        rows = report_data.is_a?(Hash) ? report_data['data'] : nil
        Array(rows).each do |row|
          csv << (row.is_a?(Hash) ? extract_csv_row(row, headers) : Array(row))
        end
      end
    end

    def get_csv_headers(report_type)
      case report_type
      when 'revenue_analytics'
        ['Period', 'MRR', 'ARR', 'Growth Rate', 'New Revenue', 'Churn Revenue']
      when 'customer_analytics'
        ['Customer ID', 'Name', 'Email', 'Plan', 'Status', 'MRR', 'LTV', 'Created']
      when 'churn_analysis'
        ['Period', 'Customer Churn Rate', 'Revenue Churn Rate', 'Churned Customers', 'Churned Revenue']
      when 'growth_analytics'
        ['Period', 'New Customers', 'Growth Rate', 'Compound Growth', 'Net Revenue Retention']
      when 'cohort_analysis'
        ['Cohort', 'Period 0', 'Period 1', 'Period 2', 'Period 3', 'Period 6', 'Period 12']
      when 'comprehensive_report'
        ['Metric', 'Current Value', 'Previous Value', 'Change', 'Percentage Change']
      else
        ['Data']
      end
    end

    def extract_csv_row(row_data, headers)
      headers.map { |header| row_data[header.downcase.gsub(' ', '_')] || '' }
    end
  end
end
