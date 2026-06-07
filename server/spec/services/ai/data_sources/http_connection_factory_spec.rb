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

  describe "error classes" do
    it "defines SsrfError and ResponseTooLargeError" do
      expect(described_class::SsrfError.ancestors).to include(StandardError)
      expect(described_class::ResponseTooLargeError.ancestors).to include(StandardError)
    end
  end
end
