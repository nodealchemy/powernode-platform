# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Observability::OtelExporter do
  let(:account) { create(:account) }
  let(:endpoint) { "http://localhost:4318" }
  let(:exporter) { described_class.new(account: account, endpoint: endpoint) }

  let(:mock_http) { instance_double(Net::HTTP) }
  let(:mock_response) { instance_double(Net::HTTPResponse, code: "200", body: "OK") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
    allow(mock_http).to receive(:request).and_return(mock_response)
  end

  describe "#initialize" do
    it "sets account and endpoint" do
      expect(exporter).to be_a(described_class)
    end

    it "defaults endpoint from environment" do
      allow(ENV).to receive(:fetch).with("OTEL_EXPORTER_OTLP_ENDPOINT", anything).and_return("http://otel:4318")

      service = described_class.new(account: account)
      expect(service).to be_a(described_class)
    end
  end

  describe "#export_trace" do
    let(:trace_data) do
      {
        trace: true,
        spans: [
          {
            trace_id: "abc123",
            span_id: "span456",
            parent_span_id: nil,
            name: "agent_execution",
            type: "root",
            started_at: Time.current,
            completed_at: Time.current + 2.seconds,
            status: "completed",
            tokens: { prompt: 100, completion: 50 },
            cost: 0.005,
            metadata: { model: "gpt-4" }
          }
        ]
      }
    end

    it "builds and sends OTLP payload to /v1/traces" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)

        expect(payload["resourceSpans"]).to be_an(Array)
        expect(payload["resourceSpans"].first["resource"]["attributes"]).to be_an(Array)

        scope_spans = payload["resourceSpans"].first["scopeSpans"].first
        expect(scope_spans["scope"]["name"]).to eq("powernode.ai")
        expect(scope_spans["spans"]).to be_an(Array)
        expect(scope_spans["spans"].first["name"]).to eq("agent_execution")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "builds correct OTLP span structure" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first

        expect(span).to have_key("traceId")
        expect(span).to have_key("spanId")
        expect(span).to have_key("name")
        expect(span).to have_key("kind")
        expect(span).to have_key("startTimeUnixNano")
        expect(span).to have_key("endTimeUnixNano")
        expect(span).to have_key("attributes")
        expect(span).to have_key("status")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "includes resource attributes" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        resource_attrs = payload["resourceSpans"].first["resource"]["attributes"]
        attr_keys = resource_attrs.map { |a| a["key"] }

        expect(attr_keys).to include("service.name")
        expect(attr_keys).to include("service.version")
        expect(attr_keys).to include("deployment.environment")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "includes token counts in attributes" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first
        attr_keys = span["attributes"].map { |a| a["key"] }

        expect(attr_keys).to include("llm.token_count.prompt")
        expect(attr_keys).to include("llm.token_count.completion")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "includes cost in attributes" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first
        cost_attr = span["attributes"].find { |a| a["key"] == "llm.cost.usd" }

        expect(cost_attr["value"]["doubleValue"]).to eq(0.005)

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "includes metadata in attributes" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first
        model_attr = span["attributes"].find { |a| a["key"] == "metadata.model" }

        expect(model_attr["value"]["stringValue"]).to eq("gpt-4")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "maps span kind correctly for root" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first

        expect(span["kind"]).to eq(2) # SERVER for root

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "maps span kind correctly for llm_call" do
      trace_data[:spans].first[:type] = "llm_call"

      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first

        expect(span["kind"]).to eq(3) # CLIENT for llm_call

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "sets completed status for successful spans" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first

        expect(span["status"]["code"]).to eq(1)
        expect(span["status"]["message"]).to eq("OK")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "sets failed status for errored spans" do
      trace_data[:spans].first[:status] = "failed"
      trace_data[:spans].first[:error] = "Model timeout"

      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first

        expect(span["status"]["code"]).to eq(2)
        expect(span["status"]["message"]).to eq("Model timeout")

        mock_response
      end

      exporter.export_trace(trace_data)
    end

    it "returns nil when trace_data is nil" do
      result = exporter.export_trace(nil)

      expect(result).to be_nil
    end

    it "returns nil when trace_data has no trace key" do
      result = exporter.export_trace({ spans: [] })

      expect(result).to be_nil
    end

    it "returns nil for empty spans" do
      result = exporter.export_trace({ trace: true, spans: [] })

      expect(result).to be_nil
    end

    it "handles HTTP errors gracefully" do
      allow(mock_http).to receive(:request).and_raise(StandardError, "Connection refused")

      result = exporter.export_trace(trace_data)

      expect(result).to be_falsey
    end

    it "handles non-2xx responses" do
      error_response = instance_double(Net::HTTPResponse, code: "500", body: "Internal Error")
      allow(mock_http).to receive(:request).and_return(error_response)

      result = exporter.export_trace(trace_data)

      expect(result).to be_falsey
    end

    it "builds events from span events" do
      trace_data[:spans].first[:events] = [
        { name: "tool_call", timestamp: Time.current, data: { tool: "search" } }
      ]

      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        span = payload["resourceSpans"].first["scopeSpans"].first["spans"].first

        expect(span["events"]).to be_an(Array)
        expect(span["events"].first["name"]).to eq("tool_call")

        mock_response
      end

      exporter.export_trace(trace_data)
    end
  end

  describe "#export_span" do
    let(:span_data) do
      {
        trace_id: "trace123",
        span_id: "span456",
        name: "llm_call",
        type: "llm_call",
        started_at: Time.current,
        completed_at: Time.current + 1.second,
        status: "completed"
      }
    end

    it "exports a single span" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        spans = payload["resourceSpans"].first["scopeSpans"].first["spans"]

        expect(spans.length).to eq(1)
        expect(spans.first["name"]).to eq("llm_call")

        mock_response
      end

      exporter.export_span(span_data)
    end

    it "returns nil when span_data is nil" do
      result = exporter.export_span(nil)

      expect(result).to be_nil
    end

    it "handles errors gracefully" do
      allow(mock_http).to receive(:request).and_raise(StandardError, "Timeout")

      result = exporter.export_span(span_data)

      expect(result).to be_falsey
    end
  end

  describe "#export_metrics" do
    let(:metrics) do
      {
        "agent_executions" => 42,
        "avg_latency_ms" => 1250.5,
        "error_rate" => 0.03
      }
    end

    it "builds correct OTLP metrics payload" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)

        expect(payload).to have_key("resourceMetrics")
        resource_metrics = payload["resourceMetrics"].first
        expect(resource_metrics["resource"]["attributes"]).to be_an(Array)

        scope_metrics = resource_metrics["scopeMetrics"].first
        expect(scope_metrics["scope"]["name"]).to eq("powernode.ai")

        gauge = scope_metrics["metrics"].first["gauge"]
        expect(gauge["dataPoints"].length).to eq(3)

        mock_response
      end

      exporter.export_metrics(metrics)
    end

    it "includes metric name and account_id in data point attributes" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        data_points = payload["resourceMetrics"].first["scopeMetrics"].first["metrics"].first["gauge"]["dataPoints"]

        first_point = data_points.first
        attr_keys = first_point["attributes"].map { |a| a["key"] }

        expect(attr_keys).to include("metric.name")
        expect(attr_keys).to include("account.id")

        mock_response
      end

      exporter.export_metrics(metrics)
    end

    it "sends to /v1/metrics endpoint" do
      expect(mock_http).to receive(:request) do |request|
        expect(request.path).to eq("/v1/metrics")
        mock_response
      end

      exporter.export_metrics(metrics)
    end

    it "converts metric values to doubles" do
      expect(mock_http).to receive(:request) do |request|
        payload = JSON.parse(request.body)
        data_points = payload["resourceMetrics"].first["scopeMetrics"].first["metrics"].first["gauge"]["dataPoints"]

        data_points.each do |dp|
          expect(dp["asDouble"]).to be_a(Numeric)
        end

        mock_response
      end

      exporter.export_metrics(metrics)
    end

    it "returns nil when metrics is not a hash" do
      result = exporter.export_metrics("invalid")

      expect(result).to be_nil
    end

    it "returns nil when metrics is nil" do
      result = exporter.export_metrics(nil)

      expect(result).to be_nil
    end

    it "handles errors gracefully" do
      allow(mock_http).to receive(:request).and_raise(StandardError, "Connection refused")

      result = exporter.export_metrics(metrics)

      expect(result).to be_falsey
    end
  end

  describe "OTEL_SERVICE_NAME" do
    it "is set to powernode-ai" do
      expect(described_class::OTEL_SERVICE_NAME).to eq("powernode-ai")
    end
  end
end
