# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Paginator do
  # Minimal Faraday-style response stand-in (status / body / headers). Scoped to
  # this example group (not a top-level constant) to avoid namespace pollution.
  let(:response_class) do
    Struct.new(:status, :body, :headers, keyword_init: true) do
      def initialize(status: 200, body: "[]", headers: {})
        super(status: status, body: body, headers: headers)
      end
    end
  end

  def resp(**kwargs)
    response_class.new(**kwargs)
  end

  def endpoint_double(pagination)
    instance_double(Ai::DataSourceEndpoint, pagination: pagination)
  end

  # Build a paginator whose fetch_page returns the queued responses in order and
  # records the params it was called with. decode_page defaults to parsing the
  # body as a JSON array; pass a custom proc for object-bodied responses.
  def build(pagination:, responses:, base_params: {}, check_quota: nil, decode_page: nil)
    queue = responses.dup
    seen_params = []
    decoder = decode_page || ->(r) { JSON.parse(r.body) }
    paginator = described_class.new(
      endpoint: endpoint_double(pagination),
      base_params: base_params,
      fetch_page: lambda { |params|
        seen_params << params
        queue.shift
      },
      decode_page: decoder,
      check_quota: check_quota
    )
    [paginator, seen_params]
  end

  describe "#enabled?" do
    it "is false for a blank config" do
      expect(described_class.new(endpoint: endpoint_double({}), base_params: {},
                                 fetch_page: ->(_) {}, decode_page: ->(_) {}).enabled?).to be(false)
    end

    it "is false for an unsupported type" do
      expect(described_class.new(endpoint: endpoint_double({ "type" => "soap" }), base_params: {},
                                 fetch_page: ->(_) {}, decode_page: ->(_) {}).enabled?).to be(false)
    end

    it "is true for a supported type" do
      expect(described_class.new(endpoint: endpoint_double({ "type" => "offset" }), base_params: {},
                                 fetch_page: ->(_) {}, decode_page: ->(_) {}).enabled?).to be(true)
    end
  end

  describe "offset pagination" do
    it "concatenates records and advances the offset by the limit" do
      paginator, seen = build(
        pagination: { "type" => "offset", "limit" => 2, "limit_param" => "limit", "offset_param" => "off" },
        responses: [
          resp(body: [{ "id" => 1 }, { "id" => 2 }].to_json),
          resp(body: [{ "id" => 3 }].to_json),
          resp(body: [].to_json)
        ]
      )

      result = paginator.each_page

      expect(result[:records]).to eq([{ "id" => 1 }, { "id" => 2 }, { "id" => 3 }])
      expect(result[:stopped_reason]).to eq("empty_page")
      expect(seen.map { |p| p["off"] }).to eq(%w[0 2 4])
      expect(seen.map { |p| p["limit"] }).to eq(%w[2 2 2])
    end
  end

  describe "page pagination" do
    it "advances the page number from the configured start_page" do
      paginator, seen = build(
        pagination: { "type" => "page", "page_param" => "p", "start_page" => 1 },
        responses: [
          resp(body: [{ "id" => 1 }].to_json),
          resp(body: [].to_json)
        ]
      )

      paginator.each_page

      expect(seen.map { |p| p["p"] }).to eq(%w[1 2])
    end
  end

  describe "cursor pagination" do
    it "reads the next cursor from the body and stops when absent" do
      paginator, seen = build(
        pagination: { "type" => "cursor", "cursor_param" => "after", "cursor_path" => "meta.next" },
        responses: [
          resp(body: { "data" => [{ "id" => 1 }], "meta" => { "next" => "C2" } }.to_json),
          resp(body: { "data" => [{ "id" => 2 }], "meta" => { "next" => nil } }.to_json)
        ],
        decode_page: ->(r) { JSON.parse(r.body)["data"] }
      )

      result = paginator.each_page

      expect(result[:records]).to eq([{ "id" => 1 }, { "id" => 2 }])
      expect(result[:stopped_reason]).to eq("no_cursor")
      expect(seen[0]["after"]).to be_nil
      expect(seen[1]["after"]).to eq("C2")
    end
  end

  describe "link pagination" do
    it "follows the rel=next Link header until none remains" do
      paginator, seen = build(
        pagination: { "type" => "link" },
        responses: [
          resp(body: [{ "id" => 1 }].to_json, headers: { "link" => '<https://x/p2>; rel="next"' }),
          resp(body: [{ "id" => 2 }].to_json, headers: {})
        ]
      )

      result = paginator.each_page

      expect(result[:records]).to eq([{ "id" => 1 }, { "id" => 2 }])
      expect(result[:stopped_reason]).to eq("no_next_link")
      expect(seen[1][described_class::ABSOLUTE_URL_PARAM]).to eq("https://x/p2")
    end
  end

  describe "hard cap" do
    it "never exceeds HARD_MAX_PAGES even when configured higher" do
      responses = Array.new(described_class::HARD_MAX_PAGES + 5) { resp(body: [{ "id" => 1 }].to_json) }
      paginator, seen = build(
        pagination: { "type" => "page", "max_pages" => 999 },
        responses: responses
      )

      result = paginator.each_page

      expect(result[:pages_fetched]).to eq(described_class::HARD_MAX_PAGES)
      expect(result[:truncated]).to be(true)
      expect(seen.size).to eq(described_class::HARD_MAX_PAGES)
    end
  end

  describe "quota veto" do
    it "stops before the next page when the quota check vetoes" do
      calls = 0
      paginator, = build(
        pagination: { "type" => "page" },
        responses: [
          resp(body: [{ "id" => 1 }].to_json),
          resp(body: [{ "id" => 2 }].to_json)
        ],
        check_quota: lambda {
          calls += 1
          { limit: "requests_per_minute" }
        }
      )

      result = paginator.each_page

      expect(result[:records]).to eq([{ "id" => 1 }])
      expect(result[:stopped_reason]).to eq("quota:requests_per_minute")
      expect(calls).to eq(1)
    end
  end

  describe "failed page" do
    it "stops on a non-2xx response and keeps the partial records" do
      paginator, = build(
        pagination: { "type" => "page" },
        responses: [
          resp(status: 200, body: [{ "id" => 1 }].to_json),
          resp(status: 500, body: "[]")
        ]
      )

      result = paginator.each_page

      expect(result[:records]).to eq([{ "id" => 1 }])
      expect(result[:stopped_reason]).to eq("page_failed")
    end
  end
end
