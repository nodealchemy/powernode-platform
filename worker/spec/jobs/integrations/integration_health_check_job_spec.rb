# frozen_string_literal: true

require 'rails_helper'

# A8 (component status plane). This job used to call the OPERATOR-auth
# `/api/v1/devops/integration_instances` surface, which a worker mTLS principal
# cannot reach: every sweep logged "endpoint unreachable" and returned
# `{ skipped: true }`, so the health columns were never written and the
# auto-pause the schedule advertises never ran. It now drives the internal
# worker seam, where the server owns the connection test, the health derivation
# and the auto-pause.
#
# ── FIXTURES ARE STRING-KEYED, ON PURPOSE (review F1) ──────────────────────────
# `BackendApiClient#get`/`#post` return `response.body` from a Faraday
# connection built with `conn.response :json` and no `parser_options`, so real
# bodies come back with STRING keys. The first version of this spec handed the
# job SYMBOL-keyed doubles, which is exactly why it stayed green while the
# deployed sweep broke out of its loop on the first iteration and issued ZERO
# probes. `api_body` is the single place the shape is defined, and it mirrors
# Faraday. Feeding these fixtures to the old symbol-keyed job fails.
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

  # Faraday parses JSON with string keys, all the way down.
  def api_body(hash)
    JSON.parse(hash.to_json)
  end

  def list_page(ids, next_cursor: nil)
    api_body(success: true, data: { instances: ids.map { |id| { id: id } }, next_cursor: next_cursor })
  end

  def probe_result(health_status: 'healthy', paused: false, applied: true, reason: nil)
    api_body(success: true,
             data: { applied: applied, health_status: health_status,
                     paused: paused, reason: reason, consecutive_probe_failures: 1 })
  end

  describe '#execute with an instance_id (single probe)' do
    it 'POSTs the internal probe endpoint exactly once' do
      expect(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/devops/integration_health/inst-1/probe')
        .once
        .and_return(probe_result)

      result = job_instance.execute('inst-1')

      expect(result[:applied]).to be true
      expect(result[:health_status]).to eq('healthy')
    end

    # Review F2: the default connection retries POST up to 5 times, and the
    # probe has a side effect PER CALL — it increments the failure streak and
    # can auto-pause. A retried probe would post a streak the operator never
    # saw. Both arms: the non-retrying method is used, the retrying one is not.
    it 'uses the NON-retrying connection, never the retrying #post' do
      allow(api_client_double).to receive(:post_no_retry).and_return(probe_result)
      expect(api_client_double).not_to receive(:post)

      job_instance.execute('inst-1')

      expect(api_client_double).to have_received(:post_no_retry)
    end

    # Both arms of the single-probe 404 rule: a 404 is a skip that does NOT
    # raise (so Sidekiq does not burn three retries on a row that is gone), and
    # any OTHER ApiError still raises (so a genuinely transient failure retries).
    it 'treats a 404 as a skip and does not raise' do
      allow(api_client_double).to receive(:post_no_retry)
        .and_raise(BackendApiClient::ApiError.new('Integration instance not found', 404))

      expect { job_instance.execute('gone') }.not_to raise_error
      expect(job_instance.execute('gone')).to eq(applied: false, reason: 'not_found')
    end

    it 'still raises a non-404 ApiError so a transient failure is retried' do
      allow(api_client_double).to receive(:post_no_retry)
        .and_raise(BackendApiClient::ApiError.new('Service temporarily unavailable', 503))

      expect { job_instance.execute('inst-1') }.to raise_error(BackendApiClient::ApiError)
    end

    it 'reports a probe the server declined to apply' do
      allow(api_client_double).to receive(:post_no_retry)
        .and_return(probe_result(applied: false, reason: 'not_active'))

      expect(job_instance.execute('inst-1')).to include(applied: false, reason: 'not_active')
    end
  end

  describe '#execute with no id (sweep)' do
    # The internal list is already scoped to ACTIVE instances on the calling
    # worker's account, so the job probes what it is given and nothing else.
    it 'probes each listed instance once and tallies the outcomes' do
      expect(api_client_double).to receive(:get)
        .with('/api/v1/internal/devops/integration_health', { per_page: 50 })
        .and_return(list_page(%w[inst-1 inst-2]))

      expect(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/devops/integration_health/inst-1/probe')
        .and_return(probe_result)
      expect(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/devops/integration_health/inst-2/probe')
        .and_return(probe_result(health_status: 'unhealthy', paused: true))

      result = job_instance.execute

      expect(result).to include(checked: 2, healthy: 1, unhealthy: 1, paused: 1)
    end

    # Review F5: the sweep follows the server's cursor rather than an offset,
    # because probing removes auto-paused rows from the listed scope.
    it 'follows next_cursor across pages and stops when it is nil' do
      expect(api_client_double).to receive(:get)
        .with('/api/v1/internal/devops/integration_health', { per_page: 50 })
        .and_return(list_page(%w[inst-1], next_cursor: 'inst-1'))
      expect(api_client_double).to receive(:get)
        .with('/api/v1/internal/devops/integration_health', { per_page: 50, after: 'inst-1' })
        .and_return(list_page(%w[inst-2]))
      allow(api_client_double).to receive(:post_no_retry).and_return(probe_result)

      expect(job_instance.execute).to include(checked: 2, healthy: 2)
    end

    it 'does not probe anything when the list comes back empty' do
      expect(api_client_double).to receive(:get).and_return(list_page([]))
      expect(api_client_double).not_to receive(:post_no_retry)

      expect(job_instance.execute).to include(checked: 0)
    end

    it 'counts a skipped (non-applied) probe as neither healthy nor unhealthy' do
      allow(api_client_double).to receive(:get).and_return(list_page(%w[inst-1]))
      allow(api_client_double).to receive(:post_no_retry)
        .and_return(probe_result(applied: false, reason: 'not_active'))

      expect(job_instance.execute).to include(checked: 1, healthy: 0, unhealthy: 0, skipped: 1)
    end

    # The F4 argument — the probe may 404 a row not visible to this worker —
    # rests on the sweep treating that 404 as a per-instance SKIP and carrying
    # on. Asserted here rather than assumed: one instance 404s, the next is
    # still probed, and the tally records exactly one skip.
    it 'skips an instance whose probe 404s and still probes the next one' do
      allow(api_client_double).to receive(:get).and_return(list_page(%w[gone inst-2]))
      allow(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/devops/integration_health/gone/probe')
        .and_raise(BackendApiClient::ApiError.new('Integration instance not found', 404))
      expect(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/devops/integration_health/inst-2/probe')
        .and_return(probe_result)

      expect(job_instance.execute).to include(checked: 2, skipped: 1, healthy: 1)
    end

    it 'stops without probing when the list call reports failure' do
      allow(api_client_double).to receive(:get).and_return(api_body(success: false, error: 'nope'))
      expect(api_client_double).not_to receive(:post_no_retry)

      expect(job_instance.execute).to include(checked: 0)
    end
  end
end
