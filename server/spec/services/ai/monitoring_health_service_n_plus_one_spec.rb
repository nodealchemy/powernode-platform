# frozen_string_literal: true

require 'rails_helper'

# N+1 guard for IMP-1565a8c93da0: the provider-health check iterates
# account.ai_providers and touch provider_credentials per row. They must
# batch-load provider_credentials (one query), not query once per provider.
# #detailed_provider_health and #test_provider_connections were deleted with the
# dead health endpoints (8c5847e2b); #check_provider_health is the surviving
# method that does this iteration.
# Note: a plain .includes is NOT enough here because the code called
# `.where(is_active: true).count/.exists?` on the association (which re-queries);
# the fix pairs .includes with in-Ruby filtering.
RSpec.describe Ai::MonitoringHealthService do
  subject(:service) { described_class.new(account: account) }

  let(:account) { create(:account) }

  # Count non-cached SQL statements matching a table pattern during the block.
  def sql_matching(pattern)
    matched = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      payload = args.last
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql] =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i
      matched << payload[:sql] if payload[:sql] =~ pattern
    end
    yield
    matched
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  before do
    3.times do
      provider = create(:ai_provider, account: account, is_active: true)
      create(:ai_provider_credential, provider: provider, account: account, is_active: true)
    end
  end

  it 'batch-loads provider_credentials in #check_provider_health (no N+1)' do
    result = nil
    queries = sql_matching(/provider_credentials/i) { result = service.check_provider_health }
    expect(result[:providers].size).to eq(3)
    expect(result[:providers]).to all(include(has_credentials: true))
    expect(queries.size).to be <= 1
  end
end
