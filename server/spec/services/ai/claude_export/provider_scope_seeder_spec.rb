# frozen_string_literal: true

require "rails_helper"

# IMP-e8513b30152d — the seam that owns the `claude-code` provider scope. Its
# docstring advertises ensure_for! as idempotent, and Accounts::ProvisionService
# calls it INSIDE an open transaction, so its RecordNotUnique recovery has to
# work there too: a nested save joins the caller's transaction, and a unique
# violation poisons it unless the insert runs in its own savepoint.
RSpec.describe Ai::ClaudeExport::ProviderScopeSeeder do
  let(:account) { create(:account) }

  describe ".ensure_for!" do
    it "recovers from a concurrent insert when called inside a caller's transaction" do
      described_class.ensure_for!(account)
      # Simulate the race: the pre-flight lookup misses, the insert loses.
      allow(described_class).to receive(:find_for).and_return(nil)

      scope = nil
      expect do
        ActiveRecord::Base.transaction { scope = described_class.ensure_for!(account) }
      end.not_to raise_error

      expect(scope).to be_present
      expect(scope.slug).to eq(described_class::SLUG)
      expect(account.ai_providers.where(slug: described_class::SLUG).count).to eq(1)
    end
  end
end
