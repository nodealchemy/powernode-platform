# frozen_string_literal: true

module Reports
  module PdfReportConcern
    extend ActiveSupport::Concern

    private

    # Generate PDF report using Prawn
    def generate_pdf_report(report_request)
      require 'prawn'
      require 'prawn/table'

      # Get report data from backend API
      report_data = with_api_retry do
        backend_api_client.get_report_data(
          report_request['report_type'],
          report_request['account_id'],
          report_request['parameters'] || {}
        )
      end

      Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
        # Header
        pdf.font_size(20) do
          pdf.text report_request['name'], style: :bold, align: :center
        end
        pdf.move_down 10

        pdf.font_size(10) do
          pdf.text "Generated: #{Time.now.strftime('%B %d, %Y at %I:%M %p')}", align: :center, color: '666666'
          pdf.text "Report Type: #{report_request['report_type'].to_s.titlecase}", align: :center, color: '666666'
        end
        pdf.move_down 20

        # Horizontal line
        pdf.stroke_horizontal_rule
        pdf.move_down 20

        # Generate report-specific content
        case report_request['report_type']
        when 'revenue_analytics'
          generate_revenue_pdf_content(pdf, report_data)
        when 'customer_analytics'
          generate_customer_pdf_content(pdf, report_data)
        when 'churn_analysis'
          generate_churn_pdf_content(pdf, report_data)
        when 'growth_analytics'
          generate_growth_pdf_content(pdf, report_data)
        when 'cohort_analysis'
          generate_cohort_pdf_content(pdf, report_data)
        when 'comprehensive_report'
          generate_executive_pdf_content(pdf, report_data)
        else
          generate_generic_pdf_content(pdf, report_data, report_request['report_type'])
        end

        # Footer with page numbers
        pdf.number_pages 'Page <page> of <total>',
                         at: [pdf.bounds.right - 100, 0],
                         align: :right,
                         size: 9
      end.render
    end

    def generate_revenue_pdf_content(pdf, data)
      pdf.font_size(14) { pdf.text 'Revenue Analytics', style: :bold }
      pdf.move_down 10

      if data && data['summary']
        summary = data['summary']
        summary_table = [
          ['Metric', 'Value'],
          ['Monthly Recurring Revenue (MRR)', format_currency(summary['mrr'])],
          ['Annual Recurring Revenue (ARR)', format_currency(summary['arr'])],
          ['Growth Rate', "#{summary['growth_rate']}%"],
          ['Net Revenue Retention', "#{summary['net_revenue_retention']}%"],
          ['Average Revenue Per User', format_currency(summary['arpu'])]
        ]

        pdf.table(summary_table, header: true, width: pdf.bounds.width) do
          row(0).background_color = '4A90D9'
          row(0).text_color = 'FFFFFF'
          row(0).font_style = :bold
          cells.padding = 8
          cells.borders = [:bottom]
          cells.border_color = 'DDDDDD'
        end
      end

      if data && data['data']
        pdf.move_down 20
        pdf.font_size(12) { pdf.text 'Revenue Trend', style: :bold }
        pdf.move_down 10

        headers = get_csv_headers('revenue_analytics')
        table_data = [headers] + (data['data'] || []).map do |row|
          extract_csv_row(row, headers)
        end

        if table_data.length > 1
          pdf.table(table_data, header: true, width: pdf.bounds.width) do
            row(0).background_color = 'EEEEEE'
            row(0).font_style = :bold
            cells.padding = 6
            cells.size = 9
          end
        end
      end
    end

    def generate_customer_pdf_content(pdf, data)
      pdf.font_size(14) { pdf.text 'Customer Analytics', style: :bold }
      pdf.move_down 10

      if data && data['summary']
        summary = data['summary']
        summary_table = [
          ['Metric', 'Value'],
          ['Total Customers', summary['total_customers'].to_s],
          ['Active Customers', summary['active_customers'].to_s],
          ['Customer Lifetime Value (LTV)', format_currency(summary['ltv'])],
          ['Customer Acquisition Cost (CAC)', format_currency(summary['cac'])],
          ['LTV/CAC Ratio', summary['ltv_cac_ratio'].to_s]
        ]

        pdf.table(summary_table, header: true, width: pdf.bounds.width) do
          row(0).background_color = '4A90D9'
          row(0).text_color = 'FFFFFF'
          row(0).font_style = :bold
          cells.padding = 8
        end
      end

      if data && data['data']
        pdf.move_down 20
        pdf.font_size(12) { pdf.text 'Customer List', style: :bold }
        pdf.move_down 10

        headers = get_csv_headers('customer_analytics')
        table_data = [headers] + (data['data'] || []).first(50).map do |row|
          extract_csv_row(row, headers)
        end

        if table_data.length > 1
          pdf.table(table_data, header: true, width: pdf.bounds.width) do
            row(0).background_color = 'EEEEEE'
            row(0).font_style = :bold
            cells.padding = 4
            cells.size = 8
          end
        end
      end
    end

    def generate_churn_pdf_content(pdf, data)
      pdf.font_size(14) { pdf.text 'Churn Analysis', style: :bold }
      pdf.move_down 10

      if data && data['summary']
        summary = data['summary']
        summary_table = [
          ['Metric', 'Value'],
          ['Customer Churn Rate', "#{summary['customer_churn_rate']}%"],
          ['Revenue Churn Rate', "#{summary['revenue_churn_rate']}%"],
          ['Churned Customers', summary['churned_customers'].to_s],
          ['Churned Revenue', format_currency(summary['churned_revenue'])],
          ['Average Days to Churn', summary['avg_days_to_churn'].to_s]
        ]

        pdf.table(summary_table, header: true, width: pdf.bounds.width) do
          row(0).background_color = 'D94A4A'
          row(0).text_color = 'FFFFFF'
          row(0).font_style = :bold
          cells.padding = 8
        end
      end

      generate_trend_table(pdf, data, 'churn_analysis')
    end

    def generate_growth_pdf_content(pdf, data)
      pdf.font_size(14) { pdf.text 'Growth Analytics', style: :bold }
      pdf.move_down 10

      if data && data['summary']
        summary = data['summary']
        summary_table = [
          ['Metric', 'Value'],
          ['New Customers', summary['new_customers'].to_s],
          ['Customer Growth Rate', "#{summary['growth_rate']}%"],
          ['MRR Growth', format_currency(summary['mrr_growth'])],
          ['Expansion Revenue', format_currency(summary['expansion_revenue'])],
          ['Net Revenue Retention', "#{summary['net_revenue_retention']}%"]
        ]

        pdf.table(summary_table, header: true, width: pdf.bounds.width) do
          row(0).background_color = '4AD98C'
          row(0).text_color = 'FFFFFF'
          row(0).font_style = :bold
          cells.padding = 8
        end
      end

      generate_trend_table(pdf, data, 'growth_analytics')
    end

    def generate_cohort_pdf_content(pdf, data)
      pdf.font_size(14) { pdf.text 'Cohort Analysis', style: :bold }
      pdf.move_down 10

      if data && data['cohorts']
        headers = ['Cohort', 'Size'] + (0..12).map { |i| "M#{i}" }
        table_data = [headers]

        (data['cohorts'] || []).each do |cohort|
          row = [cohort['name'], cohort['size'].to_s]
          (cohort['retention'] || []).each do |retention|
            row << "#{retention}%"
          end
          table_data << row
        end

        if table_data.length > 1
          pdf.table(table_data, header: true, width: pdf.bounds.width) do
            row(0).background_color = '9B59B6'
            row(0).text_color = 'FFFFFF'
            row(0).font_style = :bold
            cells.padding = 4
            cells.size = 8
          end
        end
      else
        pdf.text 'No cohort data available', color: '999999'
      end
    end

    def generate_executive_pdf_content(pdf, data)
      pdf.font_size(14) { pdf.text 'Executive Summary', style: :bold }
      pdf.move_down 10

      if data && data['summary']
        summary = data['summary']

        # Key Metrics
        pdf.font_size(12) { pdf.text 'Key Metrics', style: :bold }
        pdf.move_down 5

        metrics_table = [
          ['Metric', 'Current', 'Previous', 'Change'],
          ['MRR', format_currency(summary['mrr']), format_currency(summary['previous_mrr']), "#{summary['mrr_change']}%"],
          ['ARR', format_currency(summary['arr']), format_currency(summary['previous_arr']), "#{summary['arr_change']}%"],
          ['Customers', summary['customers'].to_s, summary['previous_customers'].to_s, "#{summary['customer_change']}%"],
          ['Churn Rate', "#{summary['churn_rate']}%", "#{summary['previous_churn_rate']}%", "#{summary['churn_change']}%"]
        ]

        pdf.table(metrics_table, header: true, width: pdf.bounds.width) do
          row(0).background_color = '2C3E50'
          row(0).text_color = 'FFFFFF'
          row(0).font_style = :bold
          cells.padding = 8
        end
      end

      generate_trend_table(pdf, data, 'comprehensive_report')
    end

    def generate_generic_pdf_content(pdf, data, report_type)
      pdf.font_size(14) { pdf.text report_type.to_s.titlecase, style: :bold }
      pdf.move_down 10

      if data && data['data']
        pdf.text data['data'].to_json, size: 9
      else
        pdf.text 'No data available for this report.', color: '999999'
      end
    end

    def generate_trend_table(pdf, data, report_type)
      return unless data && data['data']

      pdf.move_down 20
      pdf.font_size(12) { pdf.text 'Trend Data', style: :bold }
      pdf.move_down 10

      headers = get_csv_headers(report_type)
      table_data = [headers] + (data['data'] || []).map do |row|
        extract_csv_row(row, headers)
      end

      if table_data.length > 1
        pdf.table(table_data, header: true, width: pdf.bounds.width) do
          row(0).background_color = 'EEEEEE'
          row(0).font_style = :bold
          cells.padding = 6
          cells.size = 9
        end
      end
    end

    def format_currency(amount)
      return '$0.00' unless amount

      cents = amount.is_a?(Integer) ? amount : (amount * 100).to_i
      dollars = cents / 100.0
      "$#{format('%.2f', dollars).gsub(/\B(?=(\d{3})+(?!\d))/, ',')}"
    end
  end
end
