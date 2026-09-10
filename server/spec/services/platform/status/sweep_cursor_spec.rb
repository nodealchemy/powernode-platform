# frozen_string_literal: true

require "rails_helper"

# A2 review M2 — where the next sweep starts.
RSpec.describe Platform::Status::SweepCursor do
  after { described_class.clear }

  it "round-trips an account id" do
    described_class.write("acct-1")

    expect(described_class.read).to eq("acct-1")
  end

  it "reads nil when nothing was ever written, and after a clear — both arms" do
    expect(described_class.read).to be_nil

    described_class.write("acct-1")
    expect(described_class.read).to eq("acct-1")

    described_class.clear
    expect(described_class.read).to be_nil
  end

  it "treats a blank write as a clear, so 'finished the set' and 'no cursor' are one state" do
    described_class.write("acct-1")

    described_class.write(nil)
    expect(described_class.read).to be_nil

    described_class.write("acct-1")
    described_class.write("")
    expect(described_class.read).to be_nil
  end

  it "sets a TTL, so a cursor pointing at a deleted account expires instead of needing cleanup" do
    described_class.write("acct-1")

    ttl = ::Powernode::Redis.client.ttl("#{described_class::REDIS_KEY}")
    expect(ttl).to be_between(1, described_class::TTL_SECONDS)
  end

  describe "when Redis is unavailable" do
    before do
      allow(::Powernode::Redis).to receive(:client).and_raise(Redis::CannotConnectError, "down")
    end

    it "reads nil rather than raising — a lost cursor costs one tick from the top" do
      expect(described_class.read).to be_nil
    end

    it "swallows a write rather than failing the sweep" do
      expect { described_class.write("acct-1") }.not_to raise_error
    end
  end
end
