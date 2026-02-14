# frozen_string_literal: true

module Reports
  module CsvJsonReportConcern
    extend ActiveSupport::Concern

    private

    # Generate CSV report
    def generate_csv_report(report_request)
      require 'csv'

      # Get report data from backend API
      report_data = with_api_retry do
        backend_api_client.get_report_data(
          report_request['report_type'],
          report_request['account_id'],
          report_request['parameters'] || {}
        )
      end

      CSV.generate do |csv|
        # Add headers based on report type
        headers = get_csv_headers(report_request['report_type'])
        csv << headers

        # Add data rows
        if report_data && report_data['data']
          report_data['data'].each do |row|
            csv << extract_csv_row(row, headers)
          end
        end
      end
    end

    # Generate JSON report
    def generate_json_report(report_request)
      # Get report data from backend API
      report_data = with_api_retry do
        backend_api_client.get_report_data(
          report_request['report_type'],
          report_request['account_id'],
          report_request['parameters'] || {}
        )
      end

      JSON.pretty_generate({
        report_name: report_request['name'],
        report_type: report_request['report_type'],
        generated_at: Time.now.iso8601,
        data: report_data
      })
    end

    # Generate HTML content for PDF conversion
    def generate_html_report(report_data, report_request)
      case report_request['report_type']
      when 'revenue_analytics'
        generate_revenue_html(report_data)
      when 'customer_analytics'
        generate_customer_html(report_data)
      when 'churn_analysis'
        generate_churn_html(report_data)
      when 'growth_analytics'
        generate_growth_html(report_data)
      when 'cohort_analysis'
        generate_cohort_html(report_data)
      when 'comprehensive_report'
        generate_executive_html(report_data)
      else
        "Report Type: #{report_request['report_type']}\nData: #{report_data.inspect}"
      end
    end

    # Get CSV headers based on report type
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

    # Extract CSV row from data object
    def extract_csv_row(row_data, headers)
      headers.map { |header| row_data[header.downcase.gsub(' ', '_')] || '' }
    end

    # Generate revenue-specific HTML
    def generate_revenue_html(data)
      "Revenue Analytics Report\n" +
      "======================\n\n" +
      "Data: #{data.inspect}"
    end

    # Generate customer-specific HTML
    def generate_customer_html(data)
      "Customer Analytics Report\n" +
      "========================\n\n" +
      "Data: #{data.inspect}"
    end

    # Generate churn-specific HTML
    def generate_churn_html(data)
      "Churn Analysis Report\n" +
      "====================\n\n" +
      "Data: #{data.inspect}"
    end

    # Generate growth-specific HTML
    def generate_growth_html(data)
      "Growth Analytics Report\n" +
      "======================\n\n" +
      "Data: #{data.inspect}"
    end

    # Generate cohort-specific HTML
    def generate_cohort_html(data)
      "Cohort Analysis Report\n" +
      "=====================\n\n" +
      "Data: #{data.inspect}"
    end

    # Generate executive-specific HTML
    def generate_executive_html(data)
      "Executive Summary Report\n" +
      "=======================\n\n" +
      "Data: #{data.inspect}"
    end

    def send_completion_notification(callback_url, report_result)
      return unless callback_url.is_a?(String) && callback_url.start_with?('http')

      notification_payload = {
        event: 'report_generated',
        report_id: report_result['id'],
        report_type: report_result['report_type'],
        account_id: report_result['account_id'],
        status: 'completed',
        generated_at: Time.now.iso8601,
        download_url: report_result['download_url']
      }

      begin
        # Use Faraday to send webhook notification
        connection = Faraday.new do |conn|
          conn.request :json
          conn.adapter Faraday.default_adapter
          conn.options.timeout = 10
        end

        response = connection.post(callback_url, notification_payload)

        if response.success?
          log_info("Sent completion notification to #{callback_url}")
        else
          log_warn("Failed to send notification to #{callback_url}: #{response.status}")
        end
      rescue StandardError => e
        log_error("Error sending notification to #{callback_url}: #{e.message}")
        # Don't fail the job for notification errors
      end
    end
  end
end
