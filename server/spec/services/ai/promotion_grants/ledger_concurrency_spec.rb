# frozen_string_literal: true

require "rails_helper"

# max_uses must hold under concurrency: two promotions racing on the last use
# of a grant may not BOTH proceed. Proven with real, separate database
# connections and COMMITTED rows, which transactional fixtures cannot give
# (Rails 8 pins every thread to the example's one connection, inside one
# transaction), so this file opts out of them and deletes what it created.
RSpec.describe Ai::PromotionGrants::Ledger, "concurrent consumption" do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:granter) { create(:user, account: account) }
  # The provider is pinned to the same account: its factory otherwise mints an
  # account of its own, which this file would then have to find and delete.
  let!(:provider) { create(:ai_provider, account: account) }
  let!(:agent) { create(:ai_agent, account: account, provider: provider, creator: granter) }
  let!(:ops) { account.environments.find_by!(slug: "ops") }
  let!(:grant) do
    create(:ai_promotion_grant, account: account, granted_by: granter, agent: agent, environment: ops, max_uses: 1)
  end
  let(:module_id) { SecureRandom.uuid }

  after do
    # Everything this example committed, children first. The account's own
    # dependents (environments, roles, users) go with its destroy.
    AuditLog.where(account_id: account.id).delete_all
    Ai::DeferredOperation.where(account_id: account.id).delete_all
    Ai::PromotionGrant.where(account_id: account.id).delete_all
    agent.class.where(id: agent.id).delete_all
    account.reload.destroy!
    # The teardown leaves one platform-scoped row (account_id NULL) behind.
    AuditLog.where(account_id: nil, resource_id: account.id).delete_all
  end

  def operation!
    Ai::DeferredOperation.create!(account: account, action_category: "release.promote",
                                  executor_class: "PromotionGrantSpecExecutor", params: {}, ai_agent: agent,
                                  environment: ops)
  end

  it "admits exactly one of four racers to a single-use grant" do
    operations = Array.new(4) { operation! }
    gate = Concurrent::CyclicBarrier.new(4)

    winners = operations.map do |op|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.wait
          described_class.consume!(
            account: account, agent: agent, action_category: "release.promote", environment: ops,
            subject: { module_id: module_id, version_id: SecureRandom.uuid, environment_id: ops.id }, deferred_operation: op
          )
        end
      end
    end.map(&:value)

    expect(winners.compact.size).to eq(1)
    expect(grant.reload.uses_count).to eq(1)
    expect(Ai::DeferredOperation.where(promotion_grant_id: grant.id).count).to eq(1)
    expect(AuditLog.where(account_id: account.id, action: "ai.promotion_grant.used").count).to eq(1)
  end
end
