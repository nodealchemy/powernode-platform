# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Intelligence::PipelineIntelligenceService, type: :service do
  let(:account) { create(:account) }
  let(:pipeline) { create(:devops_pipeline, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe "#analyze_failure" do
    let!(:failed_run) do
      create(:devops_pipeline_run, :failed,
        pipeline: pipeline,
        error_message: "Build failed: npm ERR! ERESOLVE unable to resolve dependency tree",
        outputs: {
          "exit_code" => 1,
          "failed_step" => "install_dependencies"
        })
    end

    let!(:failed_step) do
      step = create(:devops_pipeline_step, pipeline: pipeline, name: "Install Dependencies", step_type: "custom")
      create(:devops_step_execution, :failed,
        pipeline_run: failed_run,
        pipeline_step: step,
        error_message: "npm ERR! ERESOLVE unable to resolve dependency tree",
        outputs: {
          "logs" => [
            "npm ERR! ERESOLVE unable to resolve dependency tree",
            "npm ERR! While resolving: react@18.2.0",
            "npm ERR! Found: react@17.0.2",
            "npm ERR! Could not resolve dependency: peer react@'^18.0.0'"
          ]
        })
    end

    it "analyzes failed pipeline run" do
      result = service.analyze_failure(pipeline_run_id: failed_run.id)

      expect(result[:success]).to be true
      expect(result[:pipeline_run_id]).to eq(failed_run.id)
    end

    it "identifies root cause from step logs" do
      result = service.analyze_failure(pipeline_run_id: failed_run.id)

      expect(result[:root_cause]).to be_present
      expect(result[:root_cause][:category]).to be_a(String)
      expect(result[:root_cause][:description]).to be_a(String)
      expect(result[:suggested_fixes]).to be_an(Array)
      expect(result[:suggested_fixes]).not_to be_empty
    end

    it "returns error for non-existent run" do
      result = service.analyze_failure(pipeline_run_id: SecureRandom.uuid)

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end
  end

  describe "#health_check" do
    before do
      # Create a mix of successful and failed runs
      3.times { create(:devops_pipeline_run, :completed, pipeline: pipeline) }
      2.times { create(:devops_pipeline_run, :failed, pipeline: pipeline) }
    end

    it "returns overall pipeline health" do
      result = service.health_check

      expect(result[:success]).to be true
      expect(result[:overall_health]).to be_in(%w[healthy degraded unhealthy critical no_pipelines])
      expect(result[:pipelines]).to be_an(Array)

      pipeline_report = result[:pipelines].find { |p| p[:pipeline_id] == pipeline.id }
      expect(pipeline_report).to be_present
      expect(pipeline_report[:health_status]).to be_in(%w[healthy degraded unhealthy critical inactive])
      expect(pipeline_report[:recent_runs]).to eq(5)
      expect(pipeline_report[:successful]).to eq(3)
      expect(pipeline_report[:failed]).to eq(2)
    end
  end

  describe "#failure_trends" do
    before do
      # Create failures spread across different time periods
      3.times do |i|
        run = create(:devops_pipeline_run, :failed,
          pipeline: pipeline,
          error_message: "Dependency resolution failed",
          created_at: (i + 1).days.ago)
        step = create(:devops_pipeline_step, pipeline: pipeline, name: "Build-#{i}", step_type: "custom")
        create(:devops_step_execution, :failed,
          pipeline_run: run,
          pipeline_step: step,
          error_message: "Dependency resolution failed")
      end

      2.times do |i|
        run = create(:devops_pipeline_run, :failed,
          pipeline: pipeline,
          error_message: "Test suite failed: 3 failures",
          created_at: (i + 5).days.ago)
        step = create(:devops_pipeline_step, pipeline: pipeline, name: "Test-#{i}", step_type: "custom")
        create(:devops_step_execution, :failed,
          pipeline_run: run,
          pipeline_step: step,
          error_message: "Test suite failed: 3 failures")
      end
    end

    it "returns failure patterns over time" do
      result = service.failure_trends(period_days: 30)

      expect(result[:success]).to be true
      expect(result[:period_days]).to eq(30)
      expect(result[:total_runs]).to be >= 5
      expect(result[:failed_runs]).to be >= 5
      expect(result[:failure_categories]).to be_a(Hash)
      expect(result[:failure_categories]).not_to be_empty
    end
  end
end
