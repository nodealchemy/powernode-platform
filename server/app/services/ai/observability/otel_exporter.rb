# frozen_string_literal: true

module Ai
  module Observability
    class OtelExporter
      OTEL_SERVICE_NAME = "powernode-ai"

      def initialize(account:, endpoint: nil)
        @account = account
        @endpoint = endpoint || ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
      end

      def export_trace(trace_data)
        return unless trace_data && trace_data[:trace]

        spans = build_otlp_spans(trace_data)
        return if spans.empty?

        payload = build_otlp_payload(spans)
        send_to_collector(payload)
      rescue StandardError => e
        Rails.logger.warn "[OtelExporter] Failed to export trace: #{e.message}"
        nil
      end

      def export_span(span_data)
        return unless span_data

        otlp_span = convert_span(span_data)
        payload = build_otlp_payload([otlp_span])
        send_to_collector(payload)
      rescue StandardError => e
        Rails.logger.warn "[OtelExporter] Failed to export span: #{e.message}"
        nil
      end

      def export_metrics(metrics)
        return unless metrics.is_a?(Hash)

        payload = build_otlp_metrics_payload(metrics)
        send_metrics_to_collector(payload)
      rescue StandardError => e
        Rails.logger.warn "[OtelExporter] Failed to export metrics: #{e.message}"
        nil
      end

      private

      def build_otlp_spans(trace_data)
        spans = trace_data[:spans] || []
        spans.map { |span| convert_span(span) }
      end

      def convert_span(span)
        trace_id = normalize_id(span[:trace_id] || span["trace_id"], 32)
        span_id = normalize_id(span[:span_id] || span["span_id"], 16)
        parent_span_id = normalize_id(span[:parent_span_id] || span["parent_span_id"], 16)

        started_at = span[:started_at] || span["started_at"]
        completed_at = span[:completed_at] || span["completed_at"]

        {
          traceId: trace_id,
          spanId: span_id,
          parentSpanId: parent_span_id,
          name: span[:name] || span["name"] || "unknown",
          kind: map_span_kind(span[:type] || span["type"] || span["span_type"]),
          startTimeUnixNano: to_unix_nano(started_at),
          endTimeUnixNano: to_unix_nano(completed_at),
          attributes: build_attributes(span),
          status: build_status(span),
          events: build_events(span[:events] || span["events"])
        }
      end

      def build_attributes(span)
        attrs = [
          { key: "service.name", value: { stringValue: OTEL_SERVICE_NAME } },
          { key: "account.id", value: { stringValue: @account.id.to_s } },
          { key: "span.type", value: { stringValue: (span[:type] || span["type"] || span["span_type"]).to_s } }
        ]

        if (tokens = span[:tokens] || span["tokens"])
          if tokens.is_a?(Hash)
            attrs << { key: "llm.token_count.prompt", value: { intValue: tokens[:prompt] || tokens["prompt"] || 0 } }
            attrs << { key: "llm.token_count.completion", value: { intValue: tokens[:completion] || tokens["completion"] || 0 } }
          end
        end

        if (cost = span[:cost] || span["cost"])
          attrs << { key: "llm.cost.usd", value: { doubleValue: cost.to_f } }
        end

        if (error = span[:error] || span["error"])
          attrs << { key: "error.message", value: { stringValue: error.to_s.truncate(500) } }
        end

        metadata = span[:metadata] || span["metadata"]
        if metadata.is_a?(Hash)
          metadata.each do |key, value|
            attrs << { key: "metadata.#{key}", value: { stringValue: value.to_s } }
          end
        end

        attrs
      end

      def build_status(span)
        status = span[:status] || span["status"]

        case status.to_s
        when "completed"
          { code: 1, message: "OK" }
        when "failed"
          { code: 2, message: span[:error] || span["error"] || "Error" }
        else
          { code: 0, message: "Unset" }
        end
      end

      def build_events(events)
        return [] unless events.is_a?(Array)

        events.map do |event|
          {
            name: event[:name] || event["name"] || "event",
            timeUnixNano: to_unix_nano(event[:timestamp] || event["timestamp"]),
            attributes: (event[:data] || event["data"] || {}).map do |k, v|
              { key: k.to_s, value: { stringValue: v.to_s } }
            end
          }
        end
      end

      def build_otlp_payload(spans)
        {
          resourceSpans: [
            {
              resource: {
                attributes: [
                  { key: "service.name", value: { stringValue: OTEL_SERVICE_NAME } },
                  { key: "service.version", value: { stringValue: "1.0.0" } },
                  { key: "deployment.environment", value: { stringValue: Rails.env } }
                ]
              },
              scopeSpans: [
                {
                  scope: { name: "powernode.ai", version: "1.0.0" },
                  spans: spans
                }
              ]
            }
          ]
        }
      end

      def build_otlp_metrics_payload(metrics)
        data_points = metrics.map do |key, value|
          {
            asDouble: value.to_f,
            timeUnixNano: to_unix_nano(Time.current),
            attributes: [
              { key: "metric.name", value: { stringValue: key.to_s } },
              { key: "account.id", value: { stringValue: @account.id.to_s } }
            ]
          }
        end

        {
          resourceMetrics: [
            {
              resource: {
                attributes: [
                  { key: "service.name", value: { stringValue: OTEL_SERVICE_NAME } }
                ]
              },
              scopeMetrics: [
                {
                  scope: { name: "powernode.ai", version: "1.0.0" },
                  metrics: [
                    {
                      name: "powernode.ai.metrics",
                      gauge: { dataPoints: data_points }
                    }
                  ]
                }
              ]
            }
          ]
        }
      end

      def send_to_collector(payload)
        uri = URI("#{@endpoint}/v1/traces")
        send_otlp_request(uri, payload)
      end

      def send_metrics_to_collector(payload)
        uri = URI("#{@endpoint}/v1/metrics")
        send_otlp_request(uri, payload)
      end

      def send_otlp_request(uri, payload)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        response = http.request(request)

        unless response.code.to_i.between?(200, 299)
          Rails.logger.warn "[OtelExporter] Collector returned #{response.code}: #{response.body.to_s.truncate(200)}"
        end

        response.code.to_i.between?(200, 299)
      rescue StandardError => e
        Rails.logger.warn "[OtelExporter] Failed to send to collector: #{e.message}"
        false
      end

      def map_span_kind(type)
        case type.to_s
        when "llm_call", "tool_execution"
          3 # CLIENT
        when "root"
          2 # SERVER
        else
          1 # INTERNAL
        end
      end

      def normalize_id(id, length)
        return "0" * length unless id

        hex = id.to_s.gsub(/[^a-f0-9]/i, "")
        hex = Digest::SHA256.hexdigest(id.to_s) if hex.empty?
        hex[0, length].ljust(length, "0")
      end

      def to_unix_nano(time)
        case time
        when Time
          (time.to_f * 1_000_000_000).to_i
        when String
          (Time.parse(time).to_f * 1_000_000_000).to_i
        when Numeric
          (time * 1_000_000_000).to_i
        else
          (Time.current.to_f * 1_000_000_000).to_i
        end
      rescue ArgumentError
        (Time.current.to_f * 1_000_000_000).to_i
      end
    end
  end
end
