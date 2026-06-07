# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::HttpConnectionFactory, type: :service do
  let(:data_source) { build(:ai_data_source, api_base_url: "https://api.example.com") }

  describe ".validate_url! SSRF guard" do
    # Literal-IP targets do not hit DNS — resolve_host returns the literal
    # directly — so these assertions are fully hermetic.
    context "with blocked literal addresses" do
      it "blocks the cloud metadata endpoint (169.254.169.254 link-local)" do
        expect do
          described_class.validate_url!("http://169.254.169.254/latest/meta-data/")
        end.to raise_error(described_class::SsrfError)
      end

      it "blocks IPv4 loopback (127.0.0.1)" do
        expect do
          described_class.validate_url!("http://127.0.0.1:3000/internal")
        end.to raise_error(described_class::SsrfError)
      end

      it "blocks an RFC1918 private address (10.x)" do
        expect do
          described_class.validate_url!("http://10.1.2.3/admin")
        end.to raise_error(described_class::SsrfError)
      end

      it "blocks another RFC1918 range (192.168.x)" do
        expect do
          described_class.validate_url!("http://192.168.0.10/")
        end.to raise_error(described_class::SsrfError)
      end

      it "blocks IPv6 loopback (::1)" do
        expect do
          described_class.validate_url!("http://[::1]/")
        end.to raise_error(described_class::SsrfError)
      end
    end

    context "with localhost (resolves to loopback)" do
      before do
        # Pin localhost to loopback so the check is deterministic and offline.
        allow(described_class).to receive(:resolve_host)
          .with("localhost").and_return([IPAddr.new("127.0.0.1")])
      end

      it "blocks localhost" do
        expect do
          described_class.validate_url!("http://localhost:8080/")
        end.to raise_error(described_class::SsrfError)
      end
    end

    context "with a public host" do
      before do
        # Stub DNS resolution so the spec never touches the network.
        allow(described_class).to receive(:resolve_host)
          .with("api.example.com").and_return([IPAddr.new("93.184.216.34")])
      end

      it "allows a public host (returns true, raises nothing)" do
        expect(described_class.validate_url!("https://api.example.com/v1/items")).to be(true)
      end
    end

    context "with disallowed schemes / malformed input" do
      it "rejects a non-http(s) scheme" do
        expect do
          described_class.validate_url!("file:///etc/passwd")
        end.to raise_error(described_class::SsrfError, /scheme/i)
      end

      it "rejects a URL with no host" do
        expect do
          described_class.validate_url!("https:///path-only")
        end.to raise_error(described_class::SsrfError)
      end

      it "raises SsrfError (not a raw resolver error) when the host cannot resolve" do
        allow(described_class).to receive(:resolve_host)
          .with("does-not-exist.invalid").and_raise(Resolv::ResolvError, "no address")

        expect do
          described_class.validate_url!("https://does-not-exist.invalid/")
        end.to raise_error(described_class::SsrfError)
      end
    end
  end

  describe ".blocked_address?" do
    it "flags loopback, link-local, and private ranges" do
      expect(described_class.blocked_address?("127.0.0.1")).to be(true)
      expect(described_class.blocked_address?("169.254.169.254")).to be(true)
      expect(described_class.blocked_address?("10.0.0.1")).to be(true)
      expect(described_class.blocked_address?("::1")).to be(true)
    end

    it "does not flag a public address" do
      expect(described_class.blocked_address?("93.184.216.34")).to be(false)
    end

    it "flags an IPv4-mapped IPv6 loopback (::ffff:127.0.0.1)" do
      expect(described_class.blocked_address?("::ffff:127.0.0.1")).to be(true)
    end
  end

  describe ".build" do
    it "returns a Faraday::Connection" do
      conn = described_class.build(data_source: data_source)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "sets a contactable Powernode User-Agent header" do
      conn = described_class.build(data_source: data_source)
      expect(conn.headers["User-Agent"]).to match(%r{\APowernode/.*agent:none\)})
    end

    it "includes the agent slug in the User-Agent when an agent is supplied" do
      agent = instance_double("Ai::Agent", slug: "weather-bot")
      conn = described_class.build(data_source: data_source, agent: agent)
      expect(conn.headers["User-Agent"]).to include("agent:weather-bot")
    end

    it "uses the data source's api_base_url as the connection base URL" do
      conn = described_class.build(data_source: data_source)
      expect(conn.url_prefix.to_s).to start_with("https://api.example.com")
    end

    it "installs the SSRF guard middleware so requests are pinned before egress" do
      conn = described_class.build(data_source: data_source)
      handlers = conn.builder.handlers
      expect(handlers).to include(Ai::DataSources::HttpConnectionFactory::SsrfGuardMiddleware)
    end
  end

  # ==========================================================================
  # Phase 4b-2a — max_redirects: override on .build
  #
  # A credential broker that POSTs a body-mode client_secret to a token endpoint
  # passes max_redirects: 0 so a 307/308 cannot replay the secret cross-host. When
  # the kwarg is OMITTED (nil), the follow_redirects limit falls back to the
  # per-source config["max_redirects"] (or DEFAULT_MAX_REDIRECTS), so the default
  # build path is byte-for-byte unchanged. A passed value OVERRIDES the config and
  # is clamped to >= 0.
  #
  # Hermetic: we inspect the configured limit off the constructed connection's
  # follow_redirects middleware (the gem stores it in the handler's @kwargs[:limit]),
  # consistent with the existing `conn.builder.handlers` inspection in `.build`.
  # ==========================================================================
  describe ".build max_redirects: override" do
    # Pull the configured redirect limit out of the constructed connection's
    # follow_redirects handler. The gem records the `limit:` option in the handler's
    # @kwargs (Faraday::FollowRedirects::Middleware), so this reads exactly what the
    # factory wired in — without opening a socket.
    def configured_redirect_limit(conn)
      handler = conn.builder.handlers.find { |h| h.name.to_s.include?("FollowRedirects") }
      raise "follow_redirects middleware not installed" unless handler

      handler.instance_variable_get(:@kwargs)[:limit]
    end

    context "when max_redirects: is omitted (nil)" do
      it "falls back to DEFAULT_MAX_REDIRECTS when the source config sets none" do
        # Default factory configuration is {} — no max_redirects key.
        conn = described_class.build(data_source: data_source)

        expect(configured_redirect_limit(conn)).to eq(described_class::DEFAULT_MAX_REDIRECTS)
      end

      it "falls back to the per-source config['max_redirects'] when present" do
        source = build(:ai_data_source, api_base_url: "https://api.example.com",
                                        configuration: { "max_redirects" => 7 })
        conn = described_class.build(data_source: source)

        expect(configured_redirect_limit(conn)).to eq(7)
      end

      it "ignores a non-positive config value and uses DEFAULT_MAX_REDIRECTS" do
        # positive_int rejects 0 / negatives, so the per-source config cannot lower
        # the limit to 0 — only an explicit max_redirects: kwarg can.
        source = build(:ai_data_source, api_base_url: "https://api.example.com",
                                        configuration: { "max_redirects" => 0 })
        conn = described_class.build(data_source: source)

        expect(configured_redirect_limit(conn)).to eq(described_class::DEFAULT_MAX_REDIRECTS)
      end
    end

    context "when max_redirects: is passed" do
      it "overrides the config value (a broker passes 0 to forbid redirect-following)" do
        source = build(:ai_data_source, api_base_url: "https://api.example.com",
                                        configuration: { "max_redirects" => 7 })
        conn = described_class.build(data_source: source, max_redirects: 0)

        # The explicit kwarg wins over the per-source config: 0 means "never follow".
        expect(configured_redirect_limit(conn)).to eq(0)
      end

      it "clamps a negative override up to 0" do
        conn = described_class.build(data_source: data_source, max_redirects: -3)

        expect(configured_redirect_limit(conn)).to eq(0)
      end

      it "honors a positive override over the config value" do
        source = build(:ai_data_source, api_base_url: "https://api.example.com",
                                        configuration: { "max_redirects" => 7 })
        conn = described_class.build(data_source: source, max_redirects: 2)

        expect(configured_redirect_limit(conn)).to eq(2)
      end
    end

    it "wires the follow_redirects middleware so a 0 limit does not chase a 3xx" do
      # Behavioral confirmation of what the 0 limit MEANS: the factory installs the
      # real Faraday::FollowRedirects::Middleware, and with limit 0 that middleware
      # refuses to follow a Location (it raises RedirectLimitReached rather than
      # dispatching a second request). The factory's terminal net_http adapter is not
      # stubbable in isolation, so we exercise the SAME middleware the factory wired
      # in over a Faraday :test adapter that mirrors the factory's redirect stack —
      # asserting the limit the factory configures (0) yields no-follow semantics.
      dispatched = 0
      conn = Faraday.new(url: "https://api.example.com") do |c|
        c.response :follow_redirects, limit: 0 # what build(..., max_redirects: 0) configures
        c.adapter :test do |stub|
          stub.get("/start") do
            dispatched += 1
            [301, { "Location" => "https://api.example.com/elsewhere" }, ""]
          end
          stub.get("/elsewhere") do
            dispatched += 1
            [200, {}, "FOLLOWED"]
          end
        end
      end

      # limit 0 => the redirect is NOT followed (raises rather than chasing Location),
      # so the second "/elsewhere" stub is never dispatched.
      expect { conn.get("/start") }
        .to raise_error(Faraday::FollowRedirects::RedirectLimitReached)
      expect(dispatched).to eq(1)
    end
  end

  describe "error classes" do
    it "defines SsrfError and ResponseTooLargeError" do
      expect(described_class::SsrfError.ancestors).to include(StandardError)
      expect(described_class::ResponseTooLargeError.ancestors).to include(StandardError)
    end
  end
end
