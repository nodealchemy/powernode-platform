# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::RobotsService — robots.txt politeness for governed outbound
# data-source fetches.
#
# THE CENTRAL CONTRACT under test is DEFAULT-ALLOW: a flaky, missing, blocked,
# 5xx, or garbage robots.txt must NEVER wedge a legitimate fetch. allowed?
# returns false ONLY when a robots.txt loads cleanly AND explicitly Disallows
# the request path. Everything else => true.
#
# HERMETIC:
#   - the outbound robots.txt fetch goes through
#     Ai::DataSources::HttpConnectionFactory.build(...).get(robots_url); we stub
#     .build to hand back a fake connection double so no socket is ever opened;
#   - the parsed-rules cache uses the REAL shared Redis client
#     (Powernode::Redis.client, available in test). Each example runs against a
#     fresh, isolated host AND flushes the data_source_robots:* namespace in a
#     before/after hook so cached rules never leak between examples;
#   - the DataSource after_commit knowledge-graph sync (which would otherwise
#     reach embeddings/Redis under DatabaseCleaner :deletion) is stubbed on every
#     factory create.
RSpec.describe Ai::DataSources::RobotsService, type: :service do
  let(:account) { create(:account) }

  # respect_robots OFF by default would short-circuit allowed? to true before any
  # fetch — so every gating/failure-mode example uses the :respect_robots trait
  # to actually exercise the fetch+parse path. A UNIQUE host per source keeps the
  # per-host Redis cache key isolated across examples.
  let(:host) { "robots-#{SecureRandom.hex(6)}.example.com" }
  let(:data_source) do
    create(:ai_data_source, :respect_robots, account: account,
                                             api_base_url: "https://#{host}")
  end

  subject(:service) { described_class.new(data_source) }

  # A Faraday-response stand-in: only #status and #body are consulted by the impl.
  def http_response(status:, body: "")
    instance_double("Faraday::Response", status: status, body: body)
  end

  # Wire HttpConnectionFactory.build to return a connection double whose #get
  # yields +response+ (or raises +raises+). Returns the connection double so a
  # caller can assert how many times #get ran (cache-hit verification).
  def stub_robots_fetch(response: nil, raises: nil)
    conn = instance_double("Faraday::Connection")
    if raises
      allow(conn).to receive(:get).and_raise(raises)
    else
      allow(conn).to receive(:get).and_return(response)
    end
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    conn
  end

  # The robots namespace is shared (real Redis); scrub it so a cached ruleset from
  # one example can never satisfy the next. Distinct per-example hosts make this
  # belt-and-suspenders, but the flush guarantees determinism under reruns.
  def flush_robots_cache!
    client = Powernode::Redis.client
    return unless client

    keys = client.keys("#{described_class::REDIS_NAMESPACE}:*")
    client.del(*keys) if keys.any?
  rescue StandardError
    nil
  end

  before do
    # The DataSource after_commit KG sync would otherwise reach embeddings/Redis
    # when the factory persists a source under DatabaseCleaner :deletion.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    flush_robots_cache!
  end

  after { flush_robots_cache! }

  # ==========================================================================
  # respect_robots gate — zero overhead when off
  # ==========================================================================
  describe "#allowed? when respect_robots is OFF" do
    let(:data_source) do
      create(:ai_data_source, account: account, api_base_url: "https://#{host}")
    end

    it "returns true WITHOUT fetching robots.txt (no connection built)" do
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      expect(service.allowed?("https://#{host}/anything")).to be(true)
    end
  end

  # ==========================================================================
  # DEFAULT ALLOW on every failure mode
  # ==========================================================================
  describe "#allowed? default-allow failure modes" do
    it "allows when robots.txt 404s (no robots file => crawl freely)" do
      stub_robots_fetch(response: http_response(status: 404, body: "Not Found"))

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when the robots.txt fetch raises a transport error (Faraday)" do
      stub_robots_fetch(raises: Faraday::ConnectionFailed.new("conn refused"))

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when the robots.txt fetch times out (open timeout)" do
      stub_robots_fetch(raises: Net::OpenTimeout.new("execution expired"))

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when the robots.txt fetch times out (read timeout)" do
      stub_robots_fetch(raises: Net::ReadTimeout.new("read timed out"))

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when robots.txt returns 5xx (server error treated as unavailable)" do
      stub_robots_fetch(response: http_response(status: 503, body: "upstream is down"))

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when the robots fetch itself is refused as an SSRF target" do
      stub_robots_fetch(
        raises: Ai::DataSources::HttpConnectionFactory::SsrfError.new(
          "URL resolves to a disallowed (private/loopback/link-local) address"
        )
      )

      expect(service.allowed?("https://#{host}/internal")).to be(true)
    end

    it "allows when the robots response exceeds the size cap (ResponseTooLargeError)" do
      stub_robots_fetch(
        raises: Ai::DataSources::HttpConnectionFactory::ResponseTooLargeError.new("too big")
      )

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when robots.txt body is malformed/garbage (no parseable directives)" do
      stub_robots_fetch(
        response: http_response(status: 200, body: "\x00\xFF not a robots file <<<>>> :::: %%%")
      )

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when robots.txt is served but empty" do
      stub_robots_fetch(response: http_response(status: 200, body: "   \n  \n"))

      expect(service.allowed?("https://#{host}/data")).to be(true)
    end

    it "allows when the URL is unparseable / has no host (never even fetches)" do
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      expect(service.allowed?("not a url")).to be(true)
      expect(service.allowed?("ftp://#{host}/x")).to be(true) # non-http(s) => nil uri => allow
    end
  end

  # ==========================================================================
  # Genuine gating — the ONLY path that returns false
  # ==========================================================================
  describe "#allowed? genuine robots gating" do
    it "DISALLOWS a path matched by a Disallow rule for the wildcard group" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /private
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(service.allowed?("https://#{host}/private/secret")).to be(false)
    end

    it "ALLOWS a path NOT matched by any Disallow rule" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /private
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(service.allowed?("https://#{host}/public/data.json")).to be(true)
    end

    it "ALLOWS everything when Disallow is empty (\"Disallow:\")" do
      body = <<~ROBOTS
        User-agent: *
        Disallow:
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(service.allowed?("https://#{host}/anything/at/all")).to be(true)
    end

    it "lets a more specific Allow override a broader Disallow (longest-match wins)" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /data
        Allow: /data/public
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(service.allowed?("https://#{host}/data/public/feed")).to be(true)
      expect(service.allowed?("https://#{host}/data/private")).to be(false)
    end

    it "honors a '*' wildcard inside a Disallow pattern" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /*/secret
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(service.allowed?("https://#{host}/team/secret")).to be(false)
      expect(service.allowed?("https://#{host}/team/public")).to be(true)
    end

    it "honors a trailing '$' end-anchor in a Disallow pattern" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /report.pdf$
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(service.allowed?("https://#{host}/report.pdf")).to be(false)
      # The anchor means a longer path does NOT match the rule => allowed.
      expect(service.allowed?("https://#{host}/report.pdf.bak")).to be(true)
    end
  end

  # ==========================================================================
  # User-agent specific rule selection (our UA is "Powernode/...; agent:<slug>")
  # ==========================================================================
  describe "#allowed? user-agent specific groups" do
    it "applies a Powernode-specific group over the '*' group" do
      body = <<~ROBOTS
        User-agent: *
        Disallow:

        User-agent: Powernode
        Disallow: /no-bots
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      # Our UA ("Powernode/...") prefix-includes the "powernode" token, so the
      # specific group's Disallow applies even though "*" allows everything.
      expect(service.allowed?("https://#{host}/no-bots/page")).to be(false)
    end

    it "falls back to the '*' group when no UA token matches ours" do
      body = <<~ROBOTS
        User-agent: SomeOtherBot
        Disallow: /

        User-agent: *
        Disallow: /admin
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      # The blanket "Disallow: /" belongs to SomeOtherBot, NOT us; we use "*".
      expect(service.allowed?("https://#{host}/admin/panel")).to be(false)
      expect(service.allowed?("https://#{host}/everything-else")).to be(true)
    end

    it "respects rules when an explicit agent's slug is part of our UA" do
      agent = instance_double("Ai::Agent", slug: "weather-bot")
      svc = described_class.new(data_source, agent: agent)
      body = <<~ROBOTS
        User-agent: *
        Disallow: /blocked
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(svc.allowed?("https://#{host}/blocked/x")).to be(false)
      expect(svc.allowed?("https://#{host}/open")).to be(true)
    end
  end

  # ==========================================================================
  # Caching — a second allowed? for the same host does NOT refetch
  # ==========================================================================
  describe "#allowed? caching" do
    it "fetches robots.txt only ONCE for repeated checks against the same host" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /private
      ROBOTS
      conn = stub_robots_fetch(response: http_response(status: 200, body: body))

      first  = service.allowed?("https://#{host}/private/a")
      second = service.allowed?("https://#{host}/public/b")
      third  = service.allowed?("https://#{host}/private/c")

      expect(first).to be(false)
      expect(second).to be(true)
      expect(third).to be(false)
      # Parsed rules are cached in Redis after the first miss; subsequent checks
      # read the cache, so the connection's #get ran exactly once.
      expect(conn).to have_received(:get).once
    end

    it "caches a fetch FAILURE (negative marker) so a flaky host isn't hammered" do
      conn = stub_robots_fetch(raises: Faraday::ConnectionFailed.new("refused"))

      expect(service.allowed?("https://#{host}/a")).to be(true)
      expect(service.allowed?("https://#{host}/b")).to be(true)

      # The negative marker is cached for NEGATIVE_CACHE_TTL_SECONDS, so the
      # failing endpoint is probed only once across back-to-back checks.
      expect(conn).to have_received(:get).once
    end

    it "caches a 404 as permissive so an absent robots.txt isn't refetched" do
      conn = stub_robots_fetch(response: http_response(status: 404, body: ""))

      3.times { expect(service.allowed?("https://#{host}/x")).to be(true) }

      expect(conn).to have_received(:get).once
    end
  end

  # ==========================================================================
  # #crawl_delay
  # ==========================================================================
  describe "#crawl_delay" do
    it "returns nil when respect_robots is off and no crawl_delay_seconds is set" do
      ds = create(:ai_data_source, account: account, api_base_url: "https://#{host}")
      expect(described_class.new(ds).crawl_delay).to be_nil
    end

    it "falls back to the source's configured crawl_delay_seconds when robots has none" do
      # respect_robots ON + a configured fallback delay; robots.txt declares no
      # Crawl-delay, so the configured value wins.
      ds = create(:ai_data_source, :respect_robots, account: account,
                                                     api_base_url: "https://#{host}",
                                                     crawl_delay_seconds: 7)
      svc = described_class.new(ds)
      stub_robots_fetch(response: http_response(status: 200, body: "User-agent: *\nDisallow:\n"))

      expect(svc.crawl_delay).to eq(7)
    end

    it "prefers the robots.txt Crawl-delay over the configured fallback" do
      ds = create(:ai_data_source, :respect_robots, account: account,
                                                     api_base_url: "https://#{host}",
                                                     crawl_delay_seconds: 2)
      svc = described_class.new(ds)
      body = <<~ROBOTS
        User-agent: *
        Crawl-delay: 10
        Disallow:
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(svc.crawl_delay).to eq(10)
    end

    it "rounds a fractional robots Crawl-delay UP to whole seconds" do
      ds = create(:ai_data_source, :respect_robots, account: account,
                                                     api_base_url: "https://#{host}")
      svc = described_class.new(ds)
      body = <<~ROBOTS
        User-agent: *
        Crawl-delay: 0.5
      ROBOTS
      stub_robots_fetch(response: http_response(status: 200, body: body))

      expect(svc.crawl_delay).to eq(1)
    end

    it "returns nil (no crawl_delay) when the robots fetch fails and nothing is configured" do
      ds = create(:ai_data_source, :respect_robots, account: account,
                                                     api_base_url: "https://#{host}")
      svc = described_class.new(ds)
      stub_robots_fetch(raises: Faraday::ConnectionFailed.new("refused"))

      expect(svc.crawl_delay).to be_nil
    end
  end

  # ==========================================================================
  # Constants
  # ==========================================================================
  describe "constants" do
    it "namespaces cached robots rules under data_source_robots" do
      expect(described_class::REDIS_NAMESPACE).to eq("data_source_robots")
    end

    it "exposes a positive negative-cache TTL shorter than the success TTL" do
      expect(described_class::NEGATIVE_CACHE_TTL_SECONDS).to be_positive
      expect(described_class::NEGATIVE_CACHE_TTL_SECONDS).to be < described_class::CACHE_TTL_SECONDS
    end
  end
end
