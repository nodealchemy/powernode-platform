# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::DeploymentStrategies::CanaryStrategy do
  let(:account) { create(:account) }
  let(:strategy) { described_class.new(account: account) }

  let(:mock_http) { instance_double(Net::HTTP) }
  let(:healthy_response) { instance_double(Net::HTTPResponse, code: "200") }
  let(:unhealthy_response) { instance_double(Net::HTTPResponse, code: "500") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
    allow(mock_http).to receive(:get).and_return(healthy_response)
    # Prevent real sleep in tests
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  describe "DEFAULT_STEPS" do
    it "has 4 progressive steps" do
      expect(described_class::DEFAULT_STEPS.length).to eq(4)
    end

    it "starts at 5% and ends at 100%" do
      expect(described_class::DEFAULT_STEPS.first[:weight]).to eq(5)
      expect(described_class::DEFAULT_STEPS.last[:weight]).to eq(100)
    end

    it "increases weight progressively" do
      weights = described_class::DEFAULT_STEPS.map { |s| s[:weight] }
      expect(weights).to eq([5, 25, 50, 100])
    end
  end

  describe "#execute" do
    context "with successful deployment" do
      let(:config) { { "steps" => nil, "health_check_url" => nil } }

      it "returns completed status" do
        result = strategy.execute(config: config)

        expect(result[:strategy]).to eq("canary")
        expect(result[:status]).to eq(:completed)
        expect(result[:completed_at]).to be_a(String)
      end

      it "returns correct result structure" do
        result = strategy.execute(config: config)

        expect(result).to have_key(:strategy)
        expect(result).to have_key(:status)
        expect(result).to have_key(:steps_completed)
        expect(result).to have_key(:total_steps)
        expect(result).to have_key(:results)
        expect(result).to have_key(:completed_at)
      end

      it "completes all steps" do
        result = strategy.execute(config: config)

        expect(result[:steps_completed]).to eq(4)
        expect(result[:total_steps]).to eq(4)
      end

      it "each step result includes weight and timestamp" do
        result = strategy.execute(config: config)

        step_results = result[:results].select { |r| r[:type] != :health_check }
        step_results.each do |step|
          expect(step[:success]).to be true
          expect(step[:weight]).to be_a(Integer)
          expect(step[:executed_at]).to be_a(String)
        end
      end
    end

    context "with custom steps" do
      let(:config) do
        {
          "steps" => [
            { "weight" => 10, "pause_seconds" => 0 },
            { "weight" => 50, "pause_seconds" => 0 },
            { "weight" => 100, "pause_seconds" => 0 }
          ]
        }
      end

      it "uses custom steps" do
        result = strategy.execute(config: config)

        expect(result[:total_steps]).to eq(3)
        expect(result[:steps_completed]).to eq(3)
        expect(result[:status]).to eq(:completed)
      end
    end

    context "with health checks" do
      let(:config) do
        {
          "steps" => [
            { "weight" => 25, "pause_seconds" => 30 },
            { "weight" => 100, "pause_seconds" => 0 }
          ],
          "health_check_url" => "http://app.example.com/health",
          "error_threshold" => 5.0
        }
      end

      it "performs health checks during pause periods" do
        result = strategy.execute(config: config)

        health_results = result[:results].select { |r| r[:type] == :health_check }
        expect(health_results).not_to be_empty
      end

      it "completes when all health checks pass" do
        result = strategy.execute(config: config)

        expect(result[:status]).to eq(:completed)
      end

      it "rolls back when health check fails" do
        allow(mock_http).to receive(:get).and_raise(StandardError, "Connection refused")

        result = strategy.execute(config: config)

        expect(result[:status]).to eq(:rolled_back)
        expect(result[:rollback]).to be_a(Hash)
        expect(result[:rollback][:rolled_back]).to be true
      end

      it "does not rollback when rollback_on_failure is false" do
        config["rollback_on_failure"] = false
        allow(mock_http).to receive(:get).and_raise(StandardError, "Connection refused")

        result = strategy.execute(config: config)

        expect(result[:status]).to eq(:unhealthy)
        expect(result[:rollback]).to be_nil
      end
    end

    context "with error threshold exceeded" do
      let(:config) do
        {
          "steps" => [
            { "weight" => 25, "pause_seconds" => 30 },
            { "weight" => 100, "pause_seconds" => 0 }
          ],
          "health_check_url" => "http://app.example.com/health",
          "error_threshold" => 5.0
        }
      end

      it "triggers rollback when error rate exceeds threshold" do
        # Simulate health check failure that returns high error rate
        allow(mock_http).to receive(:get).and_raise(StandardError, "Timeout")

        result = strategy.execute(config: config)

        expect(result[:status]).to eq(:rolled_back)
      end
    end

    context "with step failure" do
      it "rolls back on step failure with rollback enabled" do
        allow_any_instance_of(described_class).to receive(:execute_step).and_return({
          success: false,
          step: 0,
          weight: 5,
          error: "Deploy failed"
        })

        result = strategy.execute(config: { "rollback_on_failure" => true })

        expect(result[:status]).to eq(:rolled_back)
      end

      it "returns failed status when rollback disabled" do
        allow_any_instance_of(described_class).to receive(:execute_step).and_return({
          success: false,
          step: 0,
          weight: 5,
          error: "Deploy failed"
        })

        result = strategy.execute(config: { "rollback_on_failure" => false })

        expect(result[:status]).to eq(:failed)
      end
    end

    context "with context" do
      it "passes context to steps" do
        context = { previous_version: "1.0.0", current_version: "1.1.0" }
        result = strategy.execute(config: {}, context: context)

        expect(result[:status]).to eq(:completed)
      end
    end
  end

  describe "#rollback" do
    it "returns rollback result" do
      context = { previous_version: "1.0.0" }

      result = strategy.rollback(config: {}, context: context)

      expect(result[:rolled_back]).to be true
      expect(result[:rolled_back_at]).to be_a(String)
      expect(result[:previous_version]).to eq("1.0.0")
    end

    it "includes previous version from context" do
      result = strategy.rollback(config: {}, context: { previous_version: "2.3.1" })

      expect(result[:previous_version]).to eq("2.3.1")
    end

    it "works without context" do
      result = strategy.rollback(config: {})

      expect(result[:rolled_back]).to be true
      expect(result[:previous_version]).to be_nil
    end
  end
end
