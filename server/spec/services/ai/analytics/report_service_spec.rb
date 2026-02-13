# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Analytics::ReportService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account, user: user, time_range: 30.days) }

  let(:workflow) { create(:ai_workflow, :active, account: account) }

  describe "REPORT_TYPES" do
    it "defines the expected report types" do
      expect(described_class::REPORT_TYPES).to contain_exactly(
        "executive_summary", "cost_analysis", "performance_analysis",
        "workflow_analysis", "agent_analysis", "custom"
      )
    end
  end

  describe "#generate" do
    context "with invalid report type" do
      it "raises ArgumentError" do
        expect { service.generate(type: :invalid) }.to raise_error(
          ArgumentError, /Invalid report type: invalid/
        )
      end
    end

    context "with valid report types" do
      before do
        # Create some data so sub-services have something to work with
        3.times do
          create(:ai_workflow_run, :completed, workflow: workflow)
        end
      end

      described_class::REPORT_TYPES.each do |report_type|
        it "generates #{report_type} report" do
          result = service.generate(type: report_type)

          expect(result[:report_type]).to eq(report_type)
          expect(result[:generated_at]).to be_present
          expect(result[:generated_by]).to eq(user.email)
          expect(result[:account_id]).to eq(account.id)
          expect(result[:time_range]).to include(:start, :end, :period)
          expect(result[:data]).to be_present
        end
      end

      it "accepts report type as symbol" do
        result = service.generate(type: :cost_analysis)
        expect(result[:report_type]).to eq("cost_analysis")
      end

      it "accepts report type as string" do
        result = service.generate(type: "cost_analysis")
        expect(result[:report_type]).to eq("cost_analysis")
      end
    end

    context "executive_summary report" do
      before do
        3.times { create(:ai_workflow_run, :completed, workflow: workflow) }
      end

      it "includes expected sections" do
        result = service.generate(type: :executive_summary)
        data = result[:data]

        expect(data).to include(:title, :highlights, :kpis, :trends,
                                :cost_summary, :performance_summary,
                                :top_workflows, :recent_issues)
        expect(data[:title]).to eq("Executive Summary Report")
      end
    end

    context "cost_analysis report" do
      before do
        3.times { create(:ai_workflow_run, :completed, workflow: workflow) }
      end

      it "includes cost sections" do
        result = service.generate(type: :cost_analysis)
        data = result[:data]

        expect(data).to include(:title, :total_cost, :cost_trend,
                                :cost_by_provider, :cost_by_workflow)
        expect(data[:title]).to eq("Cost Analysis Report")
      end
    end

    context "performance_analysis report" do
      before do
        3.times { create(:ai_workflow_run, :completed, workflow: workflow) }
      end

      it "includes performance sections" do
        result = service.generate(type: :performance_analysis)
        data = result[:data]

        expect(data).to include(:title, :response_times, :success_rates,
                                :throughput, :error_rates, :bottlenecks,
                                :sla_compliance, :trends)
        expect(data[:title]).to eq("Performance Analysis Report")
      end
    end

    context "workflow_analysis report" do
      before do
        3.times { create(:ai_workflow_run, :completed, workflow: workflow) }
      end

      it "includes workflow sections" do
        result = service.generate(type: :workflow_analysis)
        data = result[:data]

        expect(data).to include(:title, :summary, :top_performers,
                                :needs_attention, :execution_trends)
        expect(data[:title]).to eq("Workflow Analysis Report")
      end

      it "supports workflow_ids option" do
        result = service.generate(type: :workflow_analysis, options: { workflow_ids: [workflow.id] })
        data = result[:data]

        expect(data[:workflow_details]).to be_an(Array)
      end
    end

    context "agent_analysis report" do
      let!(:agent) { create(:ai_agent, account: account) }

      it "includes agent sections" do
        result = service.generate(type: :agent_analysis)
        data = result[:data]

        expect(data).to include(:title, :summary, :agent_performance)
        expect(data[:title]).to eq("Agent Analysis Report")
      end

      it "supports agent_ids option" do
        result = service.generate(type: :agent_analysis, options: { agent_ids: [agent.id] })
        data = result[:data]

        expect(data[:agent_details]).to be_an(Array)
      end
    end

    context "custom report" do
      before do
        3.times { create(:ai_workflow_run, :completed, workflow: workflow) }
      end

      it "generates report with specified sections" do
        result = service.generate(type: :custom, options: { sections: %w[cost performance], title: "My Report" })
        data = result[:data]

        expect(data[:title]).to eq("My Report")
        expect(data[:sections]).to be_an(Array)
        expect(data[:sections].length).to eq(2)
        expect(data[:sections].map { |s| s[:name] }).to contain_exactly("Cost Analysis", "Performance")
      end

      it "uses default title when not specified" do
        result = service.generate(type: :custom, options: { sections: [] })
        expect(result[:data][:title]).to eq("Custom Report")
      end

      it "handles unknown sections gracefully" do
        result = service.generate(type: :custom, options: { sections: ["unknown_section"] })
        data = result[:data]

        expect(data[:sections].first[:name]).to eq("unknown_section")
        expect(data[:sections].first[:data]).to eq({})
      end
    end
  end

  describe "#export" do
    let(:report) do
      {
        report_type: "test",
        generated_at: Time.current.iso8601,
        generated_by: user.email,
        time_range: { start: 30.days.ago.iso8601, end: Time.current.iso8601, period: "30 days" },
        data: { title: "Test Report", value: 42 }
      }
    end

    context "JSON export" do
      it "returns valid JSON string" do
        result = service.export(report: report, format: :json)
        parsed = JSON.parse(result)

        expect(parsed["report_type"]).to eq("test")
        expect(parsed["data"]["value"]).to eq(42)
      end

      it "accepts format as string" do
        result = service.export(report: report, format: "json")
        expect { JSON.parse(result) }.not_to raise_error
      end
    end

    context "CSV export" do
      it "returns CSV formatted string" do
        result = service.export(report: report, format: :csv)

        expect(result).to include("Report Type,test")
        expect(result).to include("Generated At")
      end

      it "flattens nested data" do
        result = service.export(report: report, format: :csv)
        expect(result).to include("data.title,Test Report")
        expect(result).to include("data.value,42")
      end
    end

    context "PDF export" do
      it "generates PDF content" do
        # The PDF export requires prawn gem; skip if not available
        begin
          require "prawn"
          result = service.export(report: report, format: :pdf)
          expect(result).to be_present
          # PDF files start with %PDF
          expect(result).to start_with("%PDF")
        rescue LoadError
          skip "prawn gem not available"
        end
      end
    end

    context "with invalid format" do
      it "raises ArgumentError" do
        expect { service.export(report: report, format: :xml) }.to raise_error(
          ArgumentError, /Unknown export format: xml/
        )
      end
    end
  end

  describe "#schedule" do
    it "returns schedule confirmation" do
      result = service.schedule(
        type: "executive_summary",
        schedule: "0 9 * * 1",
        recipients: ["admin@example.com"]
      )

      expect(result[:scheduled]).to be true
      expect(result[:report_type]).to eq("executive_summary")
      expect(result[:schedule]).to eq("0 9 * * 1")
      expect(result[:recipients]).to eq(["admin@example.com"])
      expect(result[:next_run]).to be_present
    end

    it "passes options through" do
      result = service.schedule(
        type: "custom",
        schedule: "0 0 * * *",
        recipients: ["user@example.com"],
        options: { sections: %w[cost] }
      )

      expect(result[:options]).to eq({ sections: %w[cost] })
    end
  end

  describe "#available_reports" do
    it "returns all report types with metadata" do
      result = service.available_reports

      expect(result.length).to eq(described_class::REPORT_TYPES.length)

      result.each do |report|
        expect(report).to include(:type, :name, :description, :estimated_generation_time)
        expect(report[:type]).to be_in(described_class::REPORT_TYPES)
        expect(report[:name]).to be_present
        expect(report[:description]).to be_present
        expect(report[:estimated_generation_time]).to be_present
      end
    end

    it "returns correct descriptions for each type" do
      result = service.available_reports
      exec_report = result.find { |r| r[:type] == "executive_summary" }

      expect(exec_report[:description]).to include("overview")
    end
  end

  describe "time range formatting" do
    it "formats 1 day range" do
      svc = described_class.new(account: account, user: user, time_range: 1.day)
      result = svc.generate(type: :custom, options: { sections: [] })
      expect(result[:time_range][:period]).to eq("1 day")
    end

    it "formats 7 day range" do
      svc = described_class.new(account: account, user: user, time_range: 7.days)
      result = svc.generate(type: :custom, options: { sections: [] })
      expect(result[:time_range][:period]).to eq("1 week")
    end

    it "formats 30 day range" do
      result = service.generate(type: :custom, options: { sections: [] })
      expect(result[:time_range][:period]).to eq("30 days")
    end

    it "formats 90 day range" do
      svc = described_class.new(account: account, user: user, time_range: 90.days)
      result = svc.generate(type: :custom, options: { sections: [] })
      expect(result[:time_range][:period]).to eq("90 days")
    end
  end
end
