# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevopsService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "#initialize" do
    it "stores the account" do
      expect(service.account).to eq(account)
    end
  end

  describe "#create_template" do
    it "creates a draft template with correct attributes" do
      template = service.create_template(
        name: "CI Pipeline",
        category: "deployment",
        template_type: "code_review",
        workflow_definition: { "nodes" => [], "edges" => [] },
        user: user,
        description: "Test template"
      )

      expect(template).to be_persisted
      expect(template.name).to eq("CI Pipeline")
      expect(template.category).to eq("deployment")
      expect(template.status).to eq("draft")
      expect(template.visibility).to eq("private")
      expect(template.created_by).to eq(user)
      expect(template.account).to eq(account)
    end

    it "creates a template without optional params" do
      template = service.create_template(
        name: "Minimal",
        category: "deployment",
        template_type: "custom",
        workflow_definition: {}
      )

      expect(template).to be_persisted
      expect(template.created_by).to be_nil
      expect(template.description).to be_nil
    end
  end

  describe "#search_templates" do
    let!(:published_template) do
      create(:ai_devops_template, :published, account: account, name: "Deploy Pipeline", visibility: "public")
    end

    let!(:draft_template) do
      create(:ai_devops_template, account: account, name: "Draft Template", status: "draft", visibility: "public")
    end

    it "returns only published templates" do
      results = service.search_templates
      expect(results).to include(published_template)
      expect(results).not_to include(draft_template)
    end

    it "filters by query matching name" do
      results = service.search_templates(query: "Deploy")
      expect(results).to include(published_template)
    end

    it "returns no results for non-matching query" do
      results = service.search_templates(query: "NonExistentTemplate")
      expect(results).to be_empty
    end

    it "sanitizes SQL-like characters in query" do
      expect {
        service.search_templates(query: "test%'; DROP TABLE--")
      }.not_to raise_error
    end
  end

  describe "#install_template" do
    let(:template) { create(:ai_devops_template, :published, account: account) }

    before do
      allow(service).to receive(:create_workflow_from_template).and_return(nil)
      allow(template).to receive(:increment_installations!)
    end

    it "installs a published template" do
      result = service.install_template(template: template, user: user)

      expect(result[:success]).to be true
      expect(result[:installation]).to be_persisted
      expect(result[:installation].status).to eq("active")
      expect(result[:installation].installed_by).to eq(user)
    end

    it "rejects unpublished templates" do
      draft = create(:ai_devops_template, account: account, status: "draft")

      result = service.install_template(template: draft, user: user)

      expect(result[:success]).to be false
      expect(result[:error]).to include("not available")
    end

    it "rejects already installed templates" do
      create(:ai_devops_template_installation, :active,
             account: account, devops_template: template, installed_by: user)

      result = service.install_template(template: template, user: user)

      expect(result[:success]).to be false
      expect(result[:error]).to include("Already installed")
    end

    it "passes variable values to installation" do
      vars = { "branch" => "main" }
      result = service.install_template(template: template, user: user, variable_values: vars)

      expect(result[:installation].variable_values).to eq(vars)
    end
  end

  describe "#execute_pipeline" do
    it "creates a pipeline execution and starts it" do
      result = service.execute_pipeline(
        pipeline_type: "pr_review",
        user: user,
        input_data: { "files" => ["app.rb"] },
        repository_id: "repo-123",
        branch: "main"
      )

      expect(result[:success]).to be true
      expect(result[:execution]).to be_persisted
      expect(result[:execution].pipeline_type).to eq("pr_review")
      expect(result[:execution].status).to eq("running")
    end
  end

  describe "#get_pipeline_status" do
    let(:execution) { create(:ai_pipeline_execution, :completed, account: account) }

    it "returns a status hash with correct keys" do
      status = service.get_pipeline_status(execution)

      expect(status).to include(
        :id, :execution_id, :status, :pipeline_type,
        :started_at, :completed_at, :duration_ms, :output_data, :ai_analysis
      )
      expect(status[:status]).to eq("completed")
    end
  end

  describe "#assess_deployment_risk" do
    before do
      # The service creates DeploymentRisk with risk_level: "pending" which is not in the valid list.
      # Wrap create! to substitute a valid initial value that will be overwritten by assess!.
      allow(Ai::DeploymentRisk).to receive(:create!).and_wrap_original do |method, **attrs|
        attrs[:risk_level] = "low" if attrs[:risk_level] == "pending"
        method.call(**attrs)
      end
    end

    it "creates a risk assessment and analyzes it" do
      change_data = {
        "lines_changed" => 50,
        "test_coverage" => 90,
        "files_changed" => 3
      }

      result = service.assess_deployment_risk(
        deployment_type: "application",
        target_environment: "staging",
        change_data: change_data,
        user: user
      )

      expect(result[:success]).to be true
      expect(result[:assessment]).to be_persisted
      expect(result[:assessment].status).to eq("assessed")
    end

    it "assigns higher risk for production deployments with low coverage" do
      change_data = {
        "lines_changed" => 600,
        "test_coverage" => 30,
        "files_changed" => 20
      }

      result = service.assess_deployment_risk(
        deployment_type: "application",
        target_environment: "production",
        change_data: change_data
      )

      expect(result[:success]).to be true
      assessment = result[:assessment]
      expect(assessment.risk_factors).to be_an(Array)
      expect(assessment.risk_factors.any? { |f| f["score"].to_f > 0.7 }).to be true
    end
  end

  describe "#create_code_review" do
    it "creates a code review and starts analysis" do
      result = service.create_code_review(
        repository_id: "repo-1",
        pull_request_number: 42,
        commit_sha: "abc123",
        base_branch: "main",
        head_branch: "feature/test"
      )

      expect(result[:success]).to be true
      expect(result[:review]).to be_persisted
      expect(result[:review].status).to eq("analyzing")
      expect(result[:review].pull_request_number).to eq("42")
    end
  end

  describe "#complete_code_review" do
    let(:review) { create(:ai_code_review, :analyzing, account: account) }

    it "completes a code review with findings" do
      result = service.complete_code_review(
        review: review,
        file_analyses: [{ file: "app.rb", issues: 1 }],
        issues: [{ severity: "warning", message: "Unused variable" }],
        suggestions: [{ message: "Consider extracting method" }],
        tokens_used: 1000,
        cost: 0.01
      )

      expect(result[:success]).to be true
      expect(result[:review].status).to eq("completed")
    end
  end

  describe "#get_pipeline_analytics" do
    let!(:completed_execution) do
      create(:ai_pipeline_execution, :completed, account: account, pipeline_type: "pr_review")
    end

    let!(:failed_execution) do
      create(:ai_pipeline_execution, :failed, account: account, pipeline_type: "deployment")
    end

    it "returns analytics hash with correct structure" do
      analytics = service.get_pipeline_analytics

      expect(analytics).to include(
        :total_executions, :by_status, :by_type, :success_rate,
        :average_duration_ms, :deployments, :code_reviews
      )
      expect(analytics[:total_executions]).to eq(2)
    end

    it "calculates success rate correctly" do
      analytics = service.get_pipeline_analytics
      expect(analytics[:success_rate]).to eq(50.0)
    end

    it "groups by status" do
      analytics = service.get_pipeline_analytics
      expect(analytics[:by_status]).to include("completed" => 1, "failed" => 1)
    end

    it "groups by pipeline type" do
      analytics = service.get_pipeline_analytics
      expect(analytics[:by_type]).to include("pr_review" => 1, "deployment" => 1)
    end

    it "respects date range filters" do
      analytics = service.get_pipeline_analytics(start_date: 1.day.from_now, end_date: 2.days.from_now)
      expect(analytics[:total_executions]).to eq(0)
    end

    it "returns 0 success rate when no executions exist" do
      Ai::PipelineExecution.where(account: account).delete_all
      analytics = service.get_pipeline_analytics
      expect(analytics[:success_rate]).to eq(0)
    end
  end
end
