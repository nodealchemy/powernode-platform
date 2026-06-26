# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OllamaConnectivityTestJob, type: :job do
  let(:job) { described_class.new }
  let(:tester) { instance_double(OllamaConnectivityTester) }

  before do
    mock_powernode_worker_config
    # Inject a stubbed diagnostic tester so no real HTTP is performed.
    allow(job).to receive(:ollama_tester).and_return(tester)
    # Avoid real backend HTTP when reporting results.
    allow(job).to receive(:backend_api_post).and_return('success' => true)
  end

  describe '#execute' do
    context 'when the diagnostic suite completes' do
      before do
        allow(tester).to receive(:run).and_return(
          tests: { 'connectivity' => { status: 'passed' } },
          overall_status: 'passed'
        )
      end

      # Guards the report path (formerly log_ai_operation, which was undefined
      # and would raise NoMethodError on every run).
      it 'completes the connectivity test without raising' do
        expect { job.execute }.not_to raise_error
      end

      it 'returns the aggregated results summary' do
        result = job.execute

        expect(result[:overall_status]).to eq('passed')
        expect(result[:summary][:total_tests]).to eq(1)
        expect(result[:summary][:passed]).to eq(1)
      end
    end

    context 'when the diagnostic suite raises' do
      before do
        allow(tester).to receive(:run).and_raise(RuntimeError, 'boom')
      end

      # Guards the error path (formerly log_ai_error, which was undefined and
      # would mask the real error with a NoMethodError).
      it 'handles the error and re-raises the original failure' do
        expect { job.execute }.to raise_error(RuntimeError, /boom/)
      end

      it 'still attempts to report the failed results before re-raising' do
        expect { job.execute }.to raise_error(RuntimeError)
        expect(job).to have_received(:backend_api_post)
      end
    end
  end
end
