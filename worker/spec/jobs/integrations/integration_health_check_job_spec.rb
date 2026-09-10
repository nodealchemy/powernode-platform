# frozen_string_literal: true

require 'rails_helper'

# A8 (component status plane). This job used to call the OPERATOR-auth
# `/api/v1/devops/integration_instances` surface, which a worker mTLS principal
# cannot reach: every sweep logged "endpoint unreachable" and returned
# `{ skipped: true }`, so the health columns were never written and the
# auto-pause the schedule advertises never ran. It now drives the internal
# worker seam, where the SERVER owns the probe, the derivation and the pause.
RSpec.describe Integrations::IntegrationHealthCheckJob, type: :job do
  let(:job_instance) { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute with an instance_id (single probe)' do
    it 'POSTs the internal probe endpoint exactly once' do
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/devops/integration_health/inst-1/probe')
        .once
        .and_return({ success: true, data: { applied: true, health_status: 'healthy', paused: false } })

      result = job_instance.execute('inst-1')

      expect(result[:applied]).to be true
      expect(result[:health_status]).to eq('healthy')
    end
  end

  describe '#execute with no id (sweep)' do
    # The internal list is already scoped to ACTIVE instances on the calling
    # worker's account, so the job probes what it is given and nothing else.
    it 'probes each listed instance once and tallies the outcomes' do
      expect(api_client_double).to receive(:get)
        .with('/api/v1/internal/devops/integration_health', { page: 1, per_page: 50 })
        .and_return({
          success: true,
          data: {
            instances: [ { id: 'inst-1' }, { id: 'inst-2' } ],
            pagination: { total_pages: 1 }
          }
        })

      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/devops/integration_health/inst-1/probe')
        .and_return({ success: true, data: { applied: true, health_status: 'healthy', paused: false } })
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/devops/integration_health/inst-2/probe')
        .and_return({ success: true, data: { applied: true, health_status: 'unhealthy', paused: true } })

      result = job_instance.execute

      expect(result).to include(checked: 2, healthy: 1, unhealthy: 1, paused: 1)
    end

    it 'does not probe anything when the list comes back empty' do
      expect(api_client_double).to receive(:get)
        .with('/api/v1/internal/devops/integration_health', { page: 1, per_page: 50 })
        .and_return({ success: true, data: { instances: [], pagination: { total_pages: 1 } } })
      expect(api_client_double).not_to receive(:post)

      expect(job_instance.execute).to include(checked: 0)
    end

    it 'counts a skipped (non-applied) probe as neither healthy nor unhealthy' do
      allow(api_client_double).to receive(:get)
        .and_return({ success: true, data: { instances: [ { id: 'inst-1' } ], pagination: { total_pages: 1 } } })
      allow(api_client_double).to receive(:post)
        .and_return({ success: true, data: { applied: false, reason: 'not_active' } })

      expect(job_instance.execute).to include(checked: 1, healthy: 0, unhealthy: 0, skipped: 1)
    end
  end
end
