# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::GenerateReportJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:report_request_id) { 'req-123' }
  let(:account_id) { 'account-456' }
  let(:job_args) { report_request_id }

  let(:report_request) do
    {
      'id' => report_request_id,
      'name' => 'Revenue Report Q1',
      'type' => 'revenue_analytics',
      'report_type' => 'revenue_analytics',
      'format' => 'csv',
      'account_id' => account_id,
      'parameters' => { 'date_range' => 'last_30_days' }
    }
  end

  let(:report_data) do
    {
      'summary' => {
        'mrr' => 10000,
        'arr' => 120000,
        'growth_rate' => 5.5
      },
      'data' => [
        { 'period' => '2024-01', 'mrr' => 9000, 'arr' => 108000 },
        { 'period' => '2024-02', 'mrr' => 9500, 'arr' => 114000 }
      ]
    }
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with reports queue' do
      expect(described_class.sidekiq_options['queue']).to eq('reports')
    end

    it 'has 2 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
    end
  end

  describe '#execute' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }

    before do
      allow(job).to receive(:backend_api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    context 'when generating CSV report successfully' do
      before do
        allow(api_client).to receive(:get_report_request)
          .with(report_request_id)
          .and_return(report_request)
        allow(api_client).to receive(:update_report_request_status).and_return(true)
        allow(api_client).to receive(:get_report_data)
          .and_return(report_data)
        allow(api_client).to receive(:complete_report_request).and_return(true)
      end

      it 'fetches report request details' do
        expect(api_client).to receive(:get_report_request).with(report_request_id)

        job.execute(report_request_id)
      end

      it 'updates status to processing' do
        expect(api_client).to receive(:update_report_request_status)
          .with(report_request_id, 'processing')

        job.execute(report_request_id)
      end

      it 'fetches report data' do
        expect(api_client).to receive(:get_report_data)
          .with('revenue_analytics', account_id, { 'date_range' => 'last_30_days' })

        job.execute(report_request_id)
      end

      it 'completes report request with file info' do
        expect(api_client).to receive(:complete_report_request)
          .with(
            report_request_id,
            hash_including(:file_path, :file_size, :file_url)
          )

        job.execute(report_request_id)
      end

      it 'logs success' do
        expect(job).to receive(:log_info).with(/Successfully generated report/)

        job.execute(report_request_id)
      end
    end

    context 'when report request is not found' do
      before do
        allow(api_client).to receive(:get_report_request)
          .with(report_request_id)
          .and_return(nil)
      end

      it 'logs error and returns false' do
        expect(job).to receive(:log_error).with(/not found/)

        result = job.execute(report_request_id)
        expect(result).to be false
      end
    end

    context 'when report generation fails' do
      before do
        allow(api_client).to receive(:get_report_request)
          .with(report_request_id)
          .and_return(report_request)
        allow(api_client).to receive(:update_report_request_status).and_return(true)
        allow(api_client).to receive(:get_report_data)
          .and_raise(StandardError, 'API error')
        allow(api_client).to receive(:fail_report_request).and_return(true)
      end

      it 'marks request as failed' do
        expect(api_client).to receive(:fail_report_request)
          .with(report_request_id, 'API error')

        expect { job.execute(report_request_id) }.to raise_error(StandardError)
      end
    end

    context 'with different report formats' do
      before do
        allow(api_client).to receive(:get_report_request).and_return(report_request)
        allow(api_client).to receive(:update_report_request_status).and_return(true)
        allow(api_client).to receive(:get_report_data).and_return(report_data)
        allow(api_client).to receive(:complete_report_request).and_return(true)
      end

      context 'JSON format' do
        let(:report_request) { super().merge('format' => 'json') }

        it 'generates JSON report' do
          expect(job).to receive(:generate_json_report).and_call_original

          job.execute(report_request_id)
        end
      end

      context 'PDF format' do
        let(:report_request) { super().merge('format' => 'pdf') }

        before do
          # Mock Prawn to avoid complex PDF generation in tests
          allow(job).to receive(:generate_pdf_report).and_return('PDF content')
        end

        it 'generates PDF report' do
          expect(job).to receive(:generate_pdf_report)

          job.execute(report_request_id)
        end
      end

      context 'XLSX format' do
        let(:report_request) { super().merge('format' => 'xlsx') }

        before do
          # Mock caxlsx to avoid complex Excel generation in tests
          allow(job).to receive(:generate_xlsx_report).and_return('XLSX content')
        end

        it 'generates XLSX report' do
          expect(job).to receive(:generate_xlsx_report)

          job.execute(report_request_id)
        end
      end

      context 'unsupported format' do
        let(:report_request) { super().merge('format' => 'html') }

        it 'raises error for unsupported format' do
          expect(api_client).to receive(:fail_report_request)

          expect { job.execute(report_request_id) }.to raise_error(/Unsupported format/)
        end
      end
    end

    context 'with different report types' do
      before do
        allow(api_client).to receive(:get_report_request).and_return(report_request)
        allow(api_client).to receive(:update_report_request_status).and_return(true)
        allow(api_client).to receive(:get_report_data).and_return(report_data)
        allow(api_client).to receive(:complete_report_request).and_return(true)
      end

      %w[revenue_analytics customer_analytics churn_analysis growth_analytics cohort_analysis comprehensive_report].each do |report_type|
        context "#{report_type} report" do
          let(:report_request) { super().merge('report_type' => report_type) }

          it "generates #{report_type} report" do
            job.execute(report_request_id)
          end
        end
      end
    end
  end

  describe '#get_csv_headers' do
    let(:job) { described_class.new }

    it 'returns headers for revenue_analytics' do
      headers = job.send(:get_csv_headers, 'revenue_analytics')
      expect(headers).to include('Period', 'MRR', 'ARR')
    end

    it 'returns headers for customer_analytics' do
      headers = job.send(:get_csv_headers, 'customer_analytics')
      expect(headers).to include('Customer ID', 'Name', 'Email')
    end

    it 'returns headers for churn_analysis' do
      headers = job.send(:get_csv_headers, 'churn_analysis')
      expect(headers).to include('Customer Churn Rate', 'Revenue Churn Rate')
    end

    it 'returns default headers for unknown type' do
      headers = job.send(:get_csv_headers, 'unknown_type')
      expect(headers).to eq(['Data'])
    end
  end
end
