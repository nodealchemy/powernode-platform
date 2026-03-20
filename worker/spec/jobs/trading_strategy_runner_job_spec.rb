# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingStrategyRunnerJob, type: :job do
  include_examples "a base job", TradingStrategyRunnerJob

  describe "#execute" do
    let(:job) { described_class.new }
    let(:redis_double) { double("Redis") }
    let(:strategy_id) { "strategy-123" }
    let(:session_id) { "session-456" }
    let(:data_fetcher) { double("DataFetcher") }
    let(:evaluator) { double("Evaluator") }

    before do
      mock_powernode_worker_config
      allow_logging_methods
      allow(Sidekiq).to receive(:redis).and_yield(redis_double)
      allow(redis_double).to receive(:set).and_return(true)
      allow(redis_double).to receive(:get).and_return(nil)
      allow(redis_double).to receive(:del)
      allow(redis_double).to receive(:rpush)
      allow(redis_double).to receive(:ltrim)
      allow(redis_double).to receive(:expire)
      allow(job).to receive(:jid).and_return("test-jid-123")

      # Stub internals
      allow(job).to receive(:trading_data_fetcher).and_return(data_fetcher)
      allow(job).to receive(:build_evaluator).and_return(evaluator)
      allow(described_class).to receive(:perform_in)

      # Stub PriceChangeDetector
      stub_const("Trading::PriceChangeDetector", Class.new {
        def self.tier_for(*); :standard; end
        def self.wake_pending?(*); false; end
      })
    end

    def stub_session_running
      allow(data_fetcher).to receive(:training_status).and_return({
        "data" => { "status" => "running" }
      })
    end

    def stub_context_success
      allow(data_fetcher).to receive(:strategy_evaluation_context).and_return({
        "strategy" => { "pair" => "BTC/USDC", "tick_interval_seconds" => 30, "strategy_type" => "momentum" }
      })
    end

    def stub_evaluation_success
      allow(evaluator).to receive(:evaluate).and_return({
        "signals_generated" => 1,
        "tick_cost_usd" => 0.01
      })
    end

    it "acquires per-strategy Redis lock" do
      stub_session_running
      stub_context_success
      stub_evaluation_success

      job.execute(strategy_id, session_id)

      expect(redis_double).to have_received(:set).with(
        "strategy_runner_lock:#{strategy_id}", "test-jid-123", nx: true, ex: 120
      )
    end

    it "skips when lock is held by active JID" do
      allow(redis_double).to receive(:set).and_return(false)
      allow(redis_double).to receive(:get).and_return("other-jid")
      allow(job).to receive(:jid_active?).with("other-jid").and_return(true)

      result = job.execute(strategy_id, session_id)

      expect(result[:skipped]).to be true
      expect(result[:reason]).to eq("already_running")
    end

    it "takes over lock from dead JID" do
      allow(redis_double).to receive(:set).with(anything, anything, nx: true, ex: anything).and_return(false)
      allow(redis_double).to receive(:get).and_return("dead-jid")
      allow(job).to receive(:jid_active?).with("dead-jid").and_return(false)

      # After takeover, it should set the lock without NX
      allow(redis_double).to receive(:set).with(anything, anything, ex: anything).and_return(true)

      stub_session_running
      stub_context_success
      stub_evaluation_success

      job.execute(strategy_id, session_id)

      expect(redis_double).to have_received(:set).with(
        "strategy_runner_lock:#{strategy_id}", "test-jid-123", ex: 120
      )
    end

    it "releases lock in ensure block" do
      stub_session_running
      stub_context_success
      stub_evaluation_success

      # Lock get returns our JID for cleanup check
      allow(redis_double).to receive(:get).with("strategy_runner_lock:#{strategy_id}").and_return("test-jid-123")

      job.execute(strategy_id, session_id)

      expect(redis_double).to have_received(:del).with("strategy_runner_lock:#{strategy_id}")
    end

    it "stops when session is gone" do
      allow(data_fetcher).to receive(:training_status).and_return(nil)

      result = job.execute(strategy_id, session_id)

      expect(result[:stopped]).to be true
      expect(result[:reason]).to eq("session_gone")
    end

    it "stops when session is cancelled" do
      allow(data_fetcher).to receive(:training_status).and_return({
        "data" => { "status" => "cancelled" }
      })

      result = job.execute(strategy_id, session_id)

      expect(result[:stopped]).to be true
      expect(result[:reason]).to eq("session_cancelled")
    end

    it "stops when completion is requested" do
      allow(data_fetcher).to receive(:training_status).and_return({
        "data" => { "status" => "running", "completion_requested" => true }
      })

      result = job.execute(strategy_id, session_id)

      expect(result[:stopped]).to be true
      expect(result[:reason]).to eq("completion_requested")
    end

    it "runs evaluation and schedules next tick" do
      stub_session_running
      stub_context_success
      stub_evaluation_success

      job.execute(strategy_id, session_id)

      expect(evaluator).to have_received(:evaluate)
      expect(described_class).to have_received(:perform_in)
    end

    it "submits result when submission data present" do
      stub_session_running
      stub_context_success
      allow(evaluator).to receive(:evaluate).and_return({
        "signals_generated" => 1,
        "_submission" => { strategy_id: strategy_id, signals: [] }
      })
      allow(data_fetcher).to receive(:record_evaluation_result).and_return({})

      job.execute(strategy_id, session_id)

      expect(data_fetcher).to have_received(:record_evaluation_result)
    end

    it "stops when circuit breaker is tripped after submission" do
      stub_session_running
      stub_context_success
      allow(evaluator).to receive(:evaluate).and_return({
        "signals_generated" => 1,
        "_submission" => { strategy_id: strategy_id }
      })
      allow(data_fetcher).to receive(:record_evaluation_result).and_return({
        "circuit_breaker_tripped" => true
      })

      result = job.execute(strategy_id, session_id)

      expect(result[:stopped]).to be true
      expect(result[:reason]).to eq("circuit_breaker")
    end

    it "reschedules on connection failure" do
      stub_session_running
      allow(data_fetcher).to receive(:strategy_evaluation_context)
        .and_raise(Faraday::ConnectionFailed.new("refused"))

      result = job.execute(strategy_id, session_id)

      expect(result[:backend_down]).to be true
      expect(described_class).to have_received(:perform_in).with(30, strategy_id, session_id, anything)
    end

    it "reschedules on standard error without killing runner" do
      stub_session_running
      stub_context_success
      allow(evaluator).to receive(:evaluate).and_raise(StandardError.new("unexpected"))

      result = job.execute(strategy_id, session_id)

      expect(result[:error]).to eq("unexpected")
      expect(described_class).to have_received(:perform_in)
    end
  end
end
