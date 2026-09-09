# frozen_string_literal: true

require "rails_helper"

# Environment campaign, increment 4 — the blast-radius seam.
RSpec.describe Ai::EnvironmentResolution, ".blast_radius" do
  let(:account) { create(:account) }

  it "answers nil when no estimator is registered" do
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(described_class::BLAST_RADIUS_PROVIDER_KEY).and_return(nil)
    expect(described_class.blast_radius(account: account, params: { instance_ids: %w[a b] })).to be_nil
  end

  it "returns the estimator's integer and raises ResolverError when the estimator fails" do
    estimator = ->(account:, params:) { params[:instance_ids].size }
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(described_class::BLAST_RADIUS_PROVIDER_KEY).and_return(estimator)
    expect(described_class.blast_radius(account: account, params: { instance_ids: %w[a b c] })).to eq(3)

    broken = ->(**) { raise "boom" }
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(described_class::BLAST_RADIUS_PROVIDER_KEY).and_return(broken)
    expect { described_class.blast_radius(account: account, params: {}) }.to raise_error(described_class::ResolverError, /boom/)
  end
end
