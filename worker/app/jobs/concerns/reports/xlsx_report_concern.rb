# frozen_string_literal: true

module Reports
  module XlsxReportConcern
    extend ActiveSupport::Concern

    private

    # Generate XLSX report (Excel format) using caxlsx
    def generate_xlsx_report(report_request)
      require 'caxlsx'

      # Get report data from backend API
      report_data = with_api_retry do
        backend_api_client.get_report_data(
          report_request['report_type'],
          report_request['account_id'],
          report_request['parameters'] || {}
        )
      end

      package = Axlsx::Package.new
      workbook = package.workbook

      # Define styles
      styles = define_xlsx_styles(workbook)

      case report_request['report_type']
      when 'revenue_analytics'
        generate_revenue_xlsx(workbook, styles, report_data, report_request)
      when 'customer_analytics'
        generate_customer_xlsx(workbook, styles, report_data, report_request)
      when 'churn_analysis'
        generate_churn_xlsx(workbook, styles, report_data, report_request)
      when 'growth_analytics'
        generate_growth_xlsx(workbook, styles, report_data, report_request)
      when 'cohort_analysis'
        generate_cohort_xlsx(workbook, styles, report_data, report_request)
      when 'comprehensive_report'
        generate_executive_xlsx(workbook, styles, report_data, report_request)
      else
        generate_generic_xlsx(workbook, styles, report_data, report_request)
      end

      package.to_stream.read
    end

    def define_xlsx_styles(workbook)
      {
        title: workbook.styles.add_style(
          b: true, sz: 16, alignment: { horizontal: :center }
        ),
        header: workbook.styles.add_style(
          b: true, bg_color: '4A90D9', fg_color: 'FFFFFF',
          alignment: { horizontal: :center },
          border: { style: :thin, color: '000000' }
        ),
        header_green: workbook.styles.add_style(
          b: true, bg_color: '4AD98C', fg_color: 'FFFFFF',
          alignment: { horizontal: :center },
          border: { style: :thin, color: '000000' }
        ),
        header_red: workbook.styles.add_style(
          b: true, bg_color: 'D94A4A', fg_color: 'FFFFFF',
          alignment: { horizontal: :center },
          border: { style: :thin, color: '000000' }
        ),
        header_purple: workbook.styles.add_style(
          b: true, bg_color: '9B59B6', fg_color: 'FFFFFF',
          alignment: { horizontal: :center },
          border: { style: :thin, color: '000000' }
        ),
        cell: workbook.styles.add_style(
          alignment: { horizontal: :left },
          border: { style: :thin, color: 'DDDDDD' }
        ),
        currency: workbook.styles.add_style(
          num_fmt: 8,
          alignment: { horizontal: :right },
          border: { style: :thin, color: 'DDDDDD' }
        ),
        percent: workbook.styles.add_style(
          num_fmt: 10,
          alignment: { horizontal: :right },
          border: { style: :thin, color: 'DDDDDD' }
        ),
        number: workbook.styles.add_style(
          num_fmt: 3,
          alignment: { horizontal: :right },
          border: { style: :thin, color: 'DDDDDD' }
        ),
        date: workbook.styles.add_style(
          num_fmt: 14,
          alignment: { horizontal: :center },
          border: { style: :thin, color: 'DDDDDD' }
        ),
        subtitle: workbook.styles.add_style(
          sz: 10, i: true, alignment: { horizontal: :center }
        )
      }
    end

    def generate_revenue_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Summary') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['summary']
          summary = data['summary']
          sheet.add_row []
          sheet.add_row ['Key Metrics'], style: styles[:title]
          sheet.add_row []
          sheet.add_row ['Metric', 'Value'], style: [styles[:header], styles[:header]]
          sheet.add_row ['Monthly Recurring Revenue (MRR)', summary['mrr'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['Annual Recurring Revenue (ARR)', summary['arr'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['Growth Rate', summary['growth_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
          sheet.add_row ['Net Revenue Retention', summary['net_revenue_retention'].to_f / 100], style: [styles[:cell], styles[:percent]]
          sheet.add_row ['Average Revenue Per User', summary['arpu'].to_f / 100], style: [styles[:cell], styles[:currency]]
        end

        sheet.column_widths 35, 20
      end

      if data && data['data']
        workbook.add_worksheet(name: 'Revenue Trend') do |sheet|
          headers = get_csv_headers('revenue_analytics')
          sheet.add_row headers, style: Array.new(headers.length, styles[:header])

          (data['data'] || []).each do |row|
            sheet.add_row extract_csv_row(row, headers), style: styles[:cell]
          end

          sheet.column_widths(*Array.new(headers.length, 15))
        end
      end
    end

    def generate_customer_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Summary') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['summary']
          summary = data['summary']
          sheet.add_row []
          sheet.add_row ['Customer Metrics'], style: styles[:title]
          sheet.add_row []
          sheet.add_row ['Metric', 'Value'], style: [styles[:header], styles[:header]]
          sheet.add_row ['Total Customers', summary['total_customers']], style: [styles[:cell], styles[:number]]
          sheet.add_row ['Active Customers', summary['active_customers']], style: [styles[:cell], styles[:number]]
          sheet.add_row ['Customer Lifetime Value', summary['ltv'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['Customer Acquisition Cost', summary['cac'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['LTV/CAC Ratio', summary['ltv_cac_ratio']], style: [styles[:cell], styles[:number]]
        end

        sheet.column_widths 35, 20
      end

      if data && data['data']
        workbook.add_worksheet(name: 'Customers') do |sheet|
          headers = get_csv_headers('customer_analytics')
          sheet.add_row headers, style: Array.new(headers.length, styles[:header])

          (data['data'] || []).each do |row|
            sheet.add_row extract_csv_row(row, headers), style: styles[:cell]
          end

          sheet.column_widths(*Array.new(headers.length, 18))
        end
      end
    end

    def generate_churn_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Churn Analysis') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['summary']
          summary = data['summary']
          sheet.add_row []
          sheet.add_row ['Churn Metrics'], style: styles[:title]
          sheet.add_row []
          sheet.add_row ['Metric', 'Value'], style: [styles[:header_red], styles[:header_red]]
          sheet.add_row ['Customer Churn Rate', summary['customer_churn_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
          sheet.add_row ['Revenue Churn Rate', summary['revenue_churn_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
          sheet.add_row ['Churned Customers', summary['churned_customers']], style: [styles[:cell], styles[:number]]
          sheet.add_row ['Churned Revenue', summary['churned_revenue'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['Average Days to Churn', summary['avg_days_to_churn']], style: [styles[:cell], styles[:number]]
        end

        sheet.column_widths 35, 20
      end

      add_trend_worksheet(workbook, styles, data, 'churn_analysis', 'Churn Trend')
    end

    def generate_growth_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Growth Analytics') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['summary']
          summary = data['summary']
          sheet.add_row []
          sheet.add_row ['Growth Metrics'], style: styles[:title]
          sheet.add_row []
          sheet.add_row ['Metric', 'Value'], style: [styles[:header_green], styles[:header_green]]
          sheet.add_row ['New Customers', summary['new_customers']], style: [styles[:cell], styles[:number]]
          sheet.add_row ['Customer Growth Rate', summary['growth_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
          sheet.add_row ['MRR Growth', summary['mrr_growth'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['Expansion Revenue', summary['expansion_revenue'].to_f / 100], style: [styles[:cell], styles[:currency]]
          sheet.add_row ['Net Revenue Retention', summary['net_revenue_retention'].to_f / 100], style: [styles[:cell], styles[:percent]]
        end

        sheet.column_widths 35, 20
      end

      add_trend_worksheet(workbook, styles, data, 'growth_analytics', 'Growth Trend')
    end

    def generate_cohort_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Cohort Analysis') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['cohorts']
          sheet.add_row []
          headers = ['Cohort', 'Size'] + (0..12).map { |i| "Month #{i}" }
          sheet.add_row headers, style: Array.new(headers.length, styles[:header_purple])

          (data['cohorts'] || []).each do |cohort|
            row = [cohort['name'], cohort['size']]
            (cohort['retention'] || []).each do |retention|
              row << retention.to_f / 100
            end
            row_styles = [styles[:cell], styles[:number]] + Array.new(row.length - 2, styles[:percent])
            sheet.add_row row, style: row_styles
          end

          sheet.column_widths(*Array.new(headers.length, 12))
        else
          sheet.add_row []
          sheet.add_row ['No cohort data available']
        end
      end
    end

    def generate_executive_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Executive Summary') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['summary']
          summary = data['summary']
          sheet.add_row []
          sheet.add_row ['Key Performance Indicators'], style: styles[:title]
          sheet.add_row []
          sheet.add_row ['Metric', 'Current', 'Previous', 'Change'], style: Array.new(4, styles[:header])
          sheet.add_row ['MRR', summary['mrr'].to_f / 100, summary['previous_mrr'].to_f / 100, summary['mrr_change'].to_f / 100],
                        style: [styles[:cell], styles[:currency], styles[:currency], styles[:percent]]
          sheet.add_row ['ARR', summary['arr'].to_f / 100, summary['previous_arr'].to_f / 100, summary['arr_change'].to_f / 100],
                        style: [styles[:cell], styles[:currency], styles[:currency], styles[:percent]]
          sheet.add_row ['Customers', summary['customers'], summary['previous_customers'], summary['customer_change'].to_f / 100],
                        style: [styles[:cell], styles[:number], styles[:number], styles[:percent]]
          sheet.add_row ['Churn Rate', summary['churn_rate'].to_f / 100, summary['previous_churn_rate'].to_f / 100, summary['churn_change'].to_f / 100],
                        style: [styles[:cell], styles[:percent], styles[:percent], styles[:percent]]
        end

        sheet.column_widths 25, 18, 18, 15
      end

      add_trend_worksheet(workbook, styles, data, 'comprehensive_report', 'Trend Data')
    end

    def generate_generic_xlsx(workbook, styles, data, report_request)
      workbook.add_worksheet(name: 'Report') do |sheet|
        add_report_header(sheet, styles, report_request['name'])

        if data && data['data']
          sheet.add_row []
          sheet.add_row ['Data'], style: styles[:header]
          sheet.add_row [data['data'].to_json], style: styles[:cell]
        else
          sheet.add_row []
          sheet.add_row ['No data available']
        end
      end
    end

    def add_report_header(sheet, styles, title)
      sheet.add_row [title], style: styles[:title]
      sheet.add_row ["Generated: #{Time.now.strftime('%B %d, %Y at %I:%M %p')}"], style: styles[:subtitle]
    end

    def add_trend_worksheet(workbook, styles, data, report_type, sheet_name)
      return unless data && data['data']

      workbook.add_worksheet(name: sheet_name) do |sheet|
        headers = get_csv_headers(report_type)
        sheet.add_row headers, style: Array.new(headers.length, styles[:header])

        (data['data'] || []).each do |row|
          sheet.add_row extract_csv_row(row, headers), style: styles[:cell]
        end

        sheet.column_widths(*Array.new(headers.length, 15))
      end
    end
  end
end
