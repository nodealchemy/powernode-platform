# frozen_string_literal: true

require "rails_helper"

# IMP-f074ef554781 — the worker has no database, so the facts its sandbox
# cache pruner needs come from here: which accounts exist, and how long a
# cache may sit idle (an operator setting, not a constant).
RSpec.describe Mcp::SandboxCachePolicy do
  let!(:active) { create(:account) }
  let!(:suspended) { create(:account, status: "suspended") }
  let!(:cancelled) { create(:account, status: "cancelled") }

  describe ".call" do
    it "lists every account that has not been terminated, so a suspended tenant keeps its cache" do
      ids = described_class.call[:account_ids]

      expect(ids).to include(active.id, suspended.id)
      expect(ids).not_to include(cancelled.id)
    end

    it "defaults the idle age to 30 days" do
      expect(described_class.call[:max_idle_seconds]).to eq(30 * 86_400)
    end

    it "reads the idle age from the mcp.stdio.sandbox_cache_max_idle_seconds site setting" do
      allow(SiteSetting).to receive(:get).with("mcp.stdio.sandbox_cache_max_idle_seconds").and_return(7 * 86_400)

      expect(described_class.call[:max_idle_seconds]).to eq(7 * 86_400)
    end

    it "never offers an age below a day, however low the setting" do
      allow(SiteSetting).to receive(:get).with("mcp.stdio.sandbox_cache_max_idle_seconds").and_return(60)

      expect(described_class.call[:max_idle_seconds]).to eq(86_400)
    end

    it "ignores a value that is not a positive whole number rather than honouring it" do
      [ "abc", "1.5", "-5", "", nil, "010x" ].each do |junk|
        allow(SiteSetting).to receive(:get).with("mcp.stdio.sandbox_cache_max_idle_seconds").and_return(junk)

        expect(described_class.call[:max_idle_seconds]).to eq(30 * 86_400), "for #{junk.inspect}"
      end
    end
  end
end
