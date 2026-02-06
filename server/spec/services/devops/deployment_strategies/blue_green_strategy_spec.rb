# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::DeploymentStrategies::BlueGreenStrategy do
  let(:account) { create(:account) }
  let(:strategy) { described_class.new(account: account) }

  let(:mock_http) { instance_double(Net::HTTP) }
  let(:healthy_response) { instance_double(Net::HTTPResponse, code: "200") }
  let(:unhealthy_response) { instance_double(Net::HTTPResponse, code: "503") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
    allow(mock_http).to receive(:get).and_return(healthy_response)
    # Prevent real sleep in tests
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  describe "constants" do
    it "has default health check retries of 3" do
      expect(described_class::DEFAULT_HEALTH_CHECK_RETRIES).to eq(3)
    end

    it "has default health check interval of 10" do
      expect(described_class::DEFAULT_HEALTH_CHECK_INTERVAL).to eq(10)
    end
  end

  describe "#execute" do
    context "with successful deployment (no health checks)" do
      let(:config) { {} }
      let(:context) { { active_environment: "blue" } }

      it "returns completed status" do
        result = strategy.execute(config: config, context: context)

        expect(result[:strategy]).to eq("blue_green")
        expect(result[:status]).to eq(:completed)
      end

      it "returns correct result structure" do
        result = strategy.execute(config: config, context: context)

        expect(result).to have_key(:strategy)
        expect(result).to have_key(:status)
        expect(result).to have_key(:active_environment)
        expect(result).to have_key(:steps)
        expect(result).to have_key(:completed_at)
      end

      it "swaps to the inactive environment" do
        result = strategy.execute(config: config, context: context)

        expect(result[:active_environment]).to eq("green")
      end

      it "deploys to inactive environment first" do
        result = strategy.execute(config: config, context: context)

        deploy_step = result[:steps].find { |s| s[:step] == :deploy }
        expect(deploy_step[:environment]).to eq("green")
        expect(deploy_step[:result][:success]).to be true
      end

      it "performs traffic swap" do
        result = strategy.execute(config: config, context: context)

        swap_step = result[:steps].find { |s| s[:step] == :swap }
        expect(swap_step[:from]).to eq("blue")
        expect(swap_step[:to]).to eq("green")
        expect(swap_step[:result][:success]).to be true
      end
    end

    context "swapping from green to blue" do
      it "deploys to blue when active is green" do
        result = strategy.execute(
          config: {},
          context: { active_environment: "green" }
        )

        deploy_step = result[:steps].find { |s| s[:step] == :deploy }
        expect(deploy_step[:environment]).to eq("blue")
        expect(result[:active_environment]).to eq("blue")
      end
    end

    context "with health checks" do
      let(:config) do
        {
          "health_check_url" => "http://app.example.com/health",
          "health_check_retries" => 2,
          "health_check_interval" => 5
        }
      end
      let(:context) { { active_environment: "blue" } }

      it "performs health check on inactive environment after deploy" do
        result = strategy.execute(config: config, context: context)

        health_step = result[:steps].find { |s| s[:step] == :health_check }
        expect(health_step).not_to be_nil
        expect(health_step[:environment]).to eq("green")
        expect(health_step[:result][:healthy]).to be true
      end

      it "performs post-swap health check" do
        result = strategy.execute(config: config, context: context)

        post_swap_step = result[:steps].find { |s| s[:step] == :post_swap_health }
        expect(post_swap_step).not_to be_nil
        expect(post_swap_step[:result][:healthy]).to be true
      end

      it "completes successfully when all health checks pass" do
        result = strategy.execute(config: config, context: context)

        expect(result[:status]).to eq(:completed)
        expect(result[:active_environment]).to eq("green")
      end
    end

    context "when health check fails on inactive environment" do
      let(:config) do
        {
          "health_check_url" => "http://app.example.com/health",
          "health_check_retries" => 2,
          "rollback_on_failure" => true
        }
      end
      let(:context) { { active_environment: "blue" } }

      before do
        allow(mock_http).to receive(:get).and_return(unhealthy_response)
      end

      it "returns health_check_failed status" do
        result = strategy.execute(config: config, context: context)

        expect(result[:status]).to eq(:health_check_failed)
      end

      it "keeps original active environment" do
        result = strategy.execute(config: config, context: context)

        expect(result[:active_environment]).to eq("blue")
      end

      it "cleans up inactive environment when rollback enabled" do
        result = strategy.execute(config: config, context: context)

        cleanup_step = result[:steps].find { |s| s[:step] == :cleanup }
        expect(cleanup_step).not_to be_nil
        expect(cleanup_step[:environment]).to eq("green")
      end

      it "does not clean up when rollback disabled" do
        config["rollback_on_failure"] = false

        result = strategy.execute(config: config, context: context)

        cleanup_step = result[:steps].find { |s| s[:step] == :cleanup }
        expect(cleanup_step).to be_nil
      end
    end

    context "when post-swap health check fails" do
      let(:config) do
        {
          "health_check_url" => "http://app.example.com/health",
          "rollback_on_failure" => true
        }
      end
      let(:context) { { active_environment: "blue" } }

      it "rolls back traffic swap" do
        call_count = 0
        allow(mock_http).to receive(:get) do
          call_count += 1
          # First health check passes (pre-swap succeeds on first attempt), later ones fail (post-swap)
          if call_count <= 1
            healthy_response
          else
            unhealthy_response
          end
        end

        result = strategy.execute(config: config, context: context)

        expect(result[:status]).to eq(:rolled_back)
        expect(result[:active_environment]).to eq("blue")

        rollback_swap = result[:steps].find { |s| s[:step] == :rollback_swap }
        expect(rollback_swap).not_to be_nil
        expect(rollback_swap[:from]).to eq("green")
        expect(rollback_swap[:to]).to eq("blue")
      end
    end

    context "when deploy fails" do
      it "returns deploy_failed status" do
        allow_any_instance_of(described_class).to receive(:deploy_to_environment).and_return({
          success: false,
          error: "Deployment failed"
        })

        result = strategy.execute(config: {}, context: { active_environment: "blue" })

        expect(result[:status]).to eq(:deploy_failed)
        expect(result[:active_environment]).to eq("blue")
      end
    end

    context "when swap fails" do
      it "returns swap_failed status" do
        allow_any_instance_of(described_class).to receive(:swap_traffic).and_return({
          success: false,
          error: "Load balancer error"
        })

        result = strategy.execute(config: {}, context: { active_environment: "blue" })

        expect(result[:status]).to eq(:swap_failed)
        expect(result[:active_environment]).to eq("blue")
      end
    end

    context "defaults" do
      it "defaults active environment to blue" do
        result = strategy.execute(config: {})

        deploy_step = result[:steps].find { |s| s[:step] == :deploy }
        expect(deploy_step[:environment]).to eq("green")
      end

      it "reads active_environment from config" do
        result = strategy.execute(
          config: { "active_environment" => "green" }
        )

        deploy_step = result[:steps].find { |s| s[:step] == :deploy }
        expect(deploy_step[:environment]).to eq("blue")
      end
    end
  end

  describe "#rollback" do
    it "swaps traffic back to previous environment" do
      result = strategy.rollback(
        config: {},
        context: { active_environment: "green" }
      )

      expect(result[:rolled_back]).to be true
      expect(result[:from]).to eq("green")
      expect(result[:to]).to eq("blue")
      expect(result[:rolled_back_at]).to be_a(String)
    end

    it "swaps from blue to green" do
      result = strategy.rollback(
        config: {},
        context: { active_environment: "blue" }
      )

      expect(result[:from]).to eq("blue")
      expect(result[:to]).to eq("green")
    end

    it "defaults current environment to green" do
      result = strategy.rollback(config: {})

      expect(result[:from]).to eq("green")
      expect(result[:to]).to eq("blue")
    end

    it "reports rollback failure when swap fails" do
      allow_any_instance_of(described_class).to receive(:swap_traffic).and_return({
        success: false,
        error: "Swap failed"
      })

      result = strategy.rollback(
        config: {},
        context: { active_environment: "green" }
      )

      expect(result[:rolled_back]).to be false
    end
  end
end
