# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingTrainingSessionJob, type: :job do
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow_logging_methods
  end

  describe "#dispatch_learning_extraction!" do
    before do
      stub_const("TradingLearningExtractionJob", Class.new { def self.perform_async(*); end })
      allow(TradingLearningExtractionJob).to receive(:perform_async)
    end

    it "uses rolling @last_extraction_at when no since: is provided" do
      past = Time.now - 30
      job.instance_variable_set(:@last_extraction_at, past)
      job.instance_variable_set(:@session_started_at, Time.now - 120)

      job.send(:dispatch_learning_extraction!, ["strat-1", "strat-2"])

      expect(TradingLearningExtractionJob).to have_received(:perform_async)
        .with(["strat-1", "strat-2"], past.iso8601)
    end

    it "falls back to @session_started_at when @last_extraction_at is nil" do
      session_start = Time.now - 90
      job.instance_variable_set(:@last_extraction_at, nil)
      job.instance_variable_set(:@session_started_at, session_start)

      job.send(:dispatch_learning_extraction!, ["strat-1"])

      expect(TradingLearningExtractionJob).to have_received(:perform_async)
        .with(["strat-1"], session_start.iso8601)
    end

    it "falls back to 90.seconds.ago when both ivars are nil" do
      job.instance_variable_set(:@last_extraction_at, nil)
      job.instance_variable_set(:@session_started_at, nil)

      job.send(:dispatch_learning_extraction!, ["strat-1"])

      expect(TradingLearningExtractionJob).to have_received(:perform_async) do |ids, cutoff|
        expect(ids).to eq(["strat-1"])
        # Should be approximately 90 seconds ago
        parsed = Time.parse(cutoff)
        expect(parsed).to be_within(5).of(Time.now - 90)
      end
    end

    it "updates @last_extraction_at after dispatch" do
      job.instance_variable_set(:@last_extraction_at, nil)
      job.instance_variable_set(:@session_started_at, Time.now - 60)

      before = Time.now
      job.send(:dispatch_learning_extraction!, ["strat-1"])
      after = Time.now

      last = job.instance_variable_get(:@last_extraction_at)
      expect(last).to be_between(before, after)
    end

    it "uses explicit since: parameter when provided" do
      explicit = Time.now - 15
      job.instance_variable_set(:@last_extraction_at, Time.now - 60)

      job.send(:dispatch_learning_extraction!, ["strat-1"], since: explicit)

      expect(TradingLearningExtractionJob).to have_received(:perform_async)
        .with(["strat-1"], explicit.iso8601)
    end

    it "handles perform_async failure gracefully" do
      allow(TradingLearningExtractionJob).to receive(:perform_async).and_raise(Redis::CannotConnectError.new("conn refused"))
      job.instance_variable_set(:@session_started_at, Time.now)

      expect { job.send(:dispatch_learning_extraction!, ["strat-1"]) }.not_to raise_error
    end
  end
end
