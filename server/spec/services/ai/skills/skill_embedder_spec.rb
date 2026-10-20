# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::SkillEmbedder do
  let(:account) { create(:account) }
  let(:texts) { { a: "alpha text", b: "beta text", c: "gamma text" } }

  # First boot runs db:seed under a systemd start timeout; each provider call
  # can wait out its own timeout, so :auto must not try every text.
  it "falls back to lexical for the whole set after the FIRST provider failure, calling the provider once" do
    calls = 0
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil) do
      calls += 1
      nil
    end
    vectors = described_class.new(:auto, account: account).embed_all(texts)
    expect(calls).to eq(1)
    expect(vectors.values).to all(be_present)
    expect(vectors[:a]).to eq(Ai::Skills::LexicalEmbedder.embed("alpha text"))
  end

  it "stops at the first failure in :provider mode too" do
    calls = 0
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil) do
      calls += 1
      nil
    end
    expect { described_class.new(:provider, account: account).embed_all(texts) }.to raise_error(described_class::EmbeddingUnavailable)
    expect(calls).to eq(1)
  end

  it "uses the provider for every text when it answers" do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil) { |_svc, text, **| [ text.size.to_f, 1.0 ] }
    embedder = described_class.new(:auto, account: account)
    expect(embedder.embed_all(texts)[:b]).to eq([ 9.0, 1.0 ])
    expect(embedder.mode_used).to eq("provider")
  end
end
