# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::TradingSimulationTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  before do
    allow(WorkerJobService).to receive(:enqueue_trading_training_session)
    allow(TradingTrainingChannel).to receive(:broadcast_tick_update) if defined?(TradingTrainingChannel)
  end

  describe "#create_training_session_record" do
    context "with duration_minutes" do
      it "computes correct ends_at from now when not scheduled" do
        config = {
          "name" => "Test Session",
          "duration_minutes" => 120,
          "strategy_types" => ["momentum"],
          "mode" => "continuous"
        }

        session = tool.send(:create_training_session_record, config)
        expect(session.ends_at).to be_within(5.seconds).of(Time.current + 120.minutes)
        expect(session.status).to eq("pending")
      end

      it "bases ends_at on scheduled_for when both provided" do
        scheduled = 3.hours.from_now
        config = {
          "name" => "Scheduled Session",
          "duration_minutes" => 60,
          "scheduled_for" => scheduled.iso8601,
          "strategy_types" => ["momentum"],
          "mode" => "continuous"
        }

        session = tool.send(:create_training_session_record, config)
        expect(session.ends_at).to be_within(5.seconds).of(scheduled + 60.minutes)
        expect(session.status).to eq("scheduled")
        expect(session.scheduled_for).to be_within(5.seconds).of(scheduled)
      end
    end

    context "without duration_minutes" do
      it "leaves ends_at nil" do
        config = {
          "name" => "Indefinite Session",
          "strategy_types" => ["momentum"],
          "mode" => "continuous"
        }

        session = tool.send(:create_training_session_record, config)
        expect(session.ends_at).to be_nil
      end
    end

    context "with past scheduled_for" do
      it "raises ArgumentError" do
        config = {
          "name" => "Past Session",
          "scheduled_for" => 1.hour.ago.iso8601,
          "strategy_types" => ["momentum"]
        }

        expect {
          tool.send(:create_training_session_record, config)
        }.to raise_error(ArgumentError, /scheduled_for must be in the future/)
      end
    end
  end

  describe "#run_backtest" do
    it "sets backtest_config with default time range" do
      tool.send(:run_backtest, {})
      session = Trading::TrainingSession.last
      bt_config = session.config["backtest_config"]

      expect(bt_config).to be_present
      expect(bt_config["start_at"]).to be_present
      expect(bt_config["end_at"]).to be_present
      expect(bt_config["replay_interval_hours"]).to eq(1.0)
    end

    it "respects custom start_at and end_at params" do
      start_at = 14.days.ago.iso8601
      end_at = 3.days.ago.iso8601
      tool.send(:run_backtest, { start_at: start_at, end_at: end_at })
      session = Trading::TrainingSession.last
      bt_config = session.config["backtest_config"]

      expect(bt_config["start_at"]).to eq(start_at)
      expect(bt_config["end_at"]).to eq(end_at)
    end

    it "respects custom replay_interval_hours" do
      tool.send(:run_backtest, { replay_interval_hours: 4 })
      session = Trading::TrainingSession.last
      expect(session.config.dig("backtest_config", "replay_interval_hours")).to eq(4.0)
    end

    it "sets mode to backtest and price_mode to historical_replay" do
      tool.send(:run_backtest, {})
      session = Trading::TrainingSession.last
      expect(session.config["mode"]).to eq("backtest")
      expect(session.config["price_mode"]).to eq("historical_replay")
      expect(session.config["venue_slug"]).to eq("simulator")
    end

    it "clamps tick_count to 5..500 range" do
      tool.send(:run_backtest, { tick_count: 1000 })
      session = Trading::TrainingSession.last
      expect(session.tick_count).to eq(500)
    end

    it "enqueues the session for worker processing" do
      tool.send(:run_backtest, {})
      expect(WorkerJobService).to have_received(:enqueue_trading_training_session)
    end
  end

  describe "#serialize_training_session" do
    let(:session) do
      create(:trading_training_session,
             account: account,
             ends_at: 2.hours.from_now,
             scheduled_for: 1.hour.from_now)
    end

    it "includes ends_at field" do
      result = tool.send(:serialize_training_session, session)
      expect(result).to have_key(:ends_at)
      expect(result[:ends_at]).to eq(session.ends_at)
    end

    it "includes scheduled_for field" do
      result = tool.send(:serialize_training_session, session)
      expect(result).to have_key(:scheduled_for)
      expect(result[:scheduled_for]).to eq(session.scheduled_for)
    end

    it "includes all core fields" do
      result = tool.send(:serialize_training_session, session)
      expect(result).to include(:id, :name, :status, :market_count, :tick_count,
                                :strategy_types, :ends_at, :started_at, :created_at)
    end
  end
end
