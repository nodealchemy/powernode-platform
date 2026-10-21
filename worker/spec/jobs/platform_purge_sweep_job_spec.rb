# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlatformPurgeSweepJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
  end

  it 'asks the server to sweep due purge tasks once and returns its totals' do
    expect(api_client).to receive(:post).with(described_class::SWEEP_PATH, {})
                                        .and_return('data' => { 'completed' => 2, 'failed' => 1, 'pending' => 1 })

    expect(job.execute).to include('completed' => 2, 'failed' => 1)
  end

  it 'is scheduled in sidekiq.yml' do
    yml = File.read(File.expand_path('../../config/sidekiq.yml', __dir__))
    expect(yml).to match(/platform_purge_sweep:\n(?:\s+.*\n)*?\s+class: PlatformPurgeSweepJob/)
  end
end
