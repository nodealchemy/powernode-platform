# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::BaseBroker — the template-method CONTRACT every
# dynamic credential broker inherits.
#
# The class under test is abstract: its #acquire! raises NotImplementedError, and
# the protected helpers (#cfg, #broker_http_connection, #audit_log) are only
# reachable from a subclass. So every example drives a tiny in-file TEST SUBCLASS
# that overrides #acquire! and exposes thin public shims for the protected
# helpers — exercising the REAL BaseBroker behaviour without touching a concrete
# broker (those have their own specs).
#
# HERMETIC: BaseBroker never opens a socket itself; the ONLY outbound seam is
# #broker_http_connection, which delegates to
# Ai::DataSources::HttpConnectionFactory.validate_url! / .build — both stubbed
# here (mirroring query_service_spec / robots_service_spec) so no network, AWS,
# Vault, or OAuth endpoint is ever reached. Inside the Ai:: namespace the impl
# qualifies the factory as Ai::DataSources::HttpConnectionFactory, so that is the
# constant we stub.
RSpec.describe Ai::DataSources::Credentials::BaseBroker, type: :service do
  # --------------------------------------------------------------------------
  # Test subclass. #acquire! returns a sentinel on the happy path; flip
  # @should_raise to make it blow up so the public #acquire fail-safe is
  # exercised. Public shims expose the protected helpers under test.
  # --------------------------------------------------------------------------
  let(:test_broker_class) do
    Class.new(described_class) do
      attr_writer :should_raise, :raise_with, :acquire_return, :config_seen

      # Records the config the template method handed to #acquire! so the
      # "non-Hash config => {}" coercion is observable.
      attr_reader :config_seen

      def acquire!(data_source:, base_credential:, config:)
        @config_seen = config
        raise((@raise_with || StandardError), "boom") if @should_raise || @raise_with

        @acquire_return.nil? ? base_credential : @acquire_return
      end

      # A stable, demodulize-friendly name so audit lines / broker_type are
      # deterministic (an anonymous Class has a nil #name).
      def self.name
        "Ai::DataSources::Credentials::TestProbeBroker"
      end

      # --- public shims onto the protected surface under test ---
      def public_cfg(config, *keys)
        cfg(config, *keys)
      end

      def public_broker_http_connection(url, data_source:, agent: nil, max_redirects: nil)
        broker_http_connection(url, data_source: data_source, agent: agent, max_redirects: max_redirects)
      end

      def public_audit_log(data_source, outcome, **meta)
        audit_log(data_source, outcome, **meta)
      end

      def public_broker_type
        broker_type
      end
    end
  end

  let(:broker) { test_broker_class.new }

  # A data source double exposing only what BaseBroker reads (#slug for the audit
  # line). Avoids a DB row — BaseBroker never persists anything.
  let(:data_source) { instance_double(Ai::DataSource, slug: "weather_src") }

  # The resolved STATIC/VAULT base credential the broker would exchange or pass
  # through. A bare double satisfying the signer contract is enough.
  let(:base_credential) do
    instance_double(Ai::DataSourceCredential,
                    decrypted_api_key: "base-key", decrypted_api_secret: "base-secret")
  end

  # ==========================================================================
  # #acquire fail-safe: a raising #acquire! degrades to base_credential and
  # NEVER lets the exception escape (the fetch pipeline must not crash).
  # ==========================================================================
  describe "#acquire fail-safe (raising subclass)" do
    before { broker.should_raise = true }

    it "returns the base_credential unchanged instead of raising" do
      result = nil
      expect do
        result = broker.acquire(data_source: data_source, base_credential: base_credential, config: {})
      end.not_to raise_error

      expect(result).to be(base_credential)
    end

    it "swallows even a non-StandardError-shaped failure class by degrading" do
      # The rescue targets StandardError; a RuntimeError (its subclass) is the
      # realistic worst case from an HTTP client / AWS SDK. It must be caught.
      broker.raise_with = RuntimeError

      expect do
        broker.acquire(data_source: data_source, base_credential: base_credential, config: {})
      end.not_to raise_error
    end

    it "emits exactly one audit line with outcome=error and the error CLASS only (no message, no secret)" do
      broker.raise_with = ArgumentError
      expect(Rails.logger).to receive(:info).once do |line|
        expect(line).to include("outcome=error")
        expect(line).to include("error_class=ArgumentError")
        expect(line).to include("source=weather_src")
        # The redacted contract: the raised MESSAGE ("boom") and any base secret
        # must never appear in the audit line.
        expect(line).not_to include("boom")
        expect(line).not_to include("base-key")
        expect(line).not_to include("base-secret")
      end

      broker.acquire(data_source: data_source, base_credential: base_credential, config: {})
    end

    it "returns base_credential even when base_credential is nil (degrade path)" do
      expect(
        broker.acquire(data_source: data_source, base_credential: nil, config: {})
      ).to be_nil
    end
  end

  # ==========================================================================
  # #acquire config coercion: a non-Hash config is passed to #acquire! as {}.
  # ==========================================================================
  describe "#acquire config coercion" do
    it "passes a non-Hash config through to #acquire! as an empty Hash" do
      broker.acquire(data_source: data_source, base_credential: base_credential, config: "not-a-hash")
      expect(broker.config_seen).to eq({})
    end

    it "passes nil config through as an empty Hash" do
      broker.acquire(data_source: data_source, base_credential: base_credential, config: nil)
      expect(broker.config_seen).to eq({})
    end

    it "passes a real Hash config through unchanged" do
      cfg = { "token_url" => "https://idp.example.com/token" }
      broker.acquire(data_source: data_source, base_credential: base_credential, config: cfg)
      expect(broker.config_seen).to eq(cfg)
    end

    it "returns the subclass result on the happy path (no rescue)" do
      brokered = instance_double(Ai::DataSourceCredential,
                                 decrypted_api_key: "fresh", decrypted_api_secret: "fresh-secret")
      broker.acquire_return = brokered

      expect(
        broker.acquire(data_source: data_source, base_credential: base_credential, config: {})
      ).to be(brokered)
    end
  end

  # ==========================================================================
  # #cfg tolerant jsonb read (string/symbol spellings + blank-skip fallback).
  # ==========================================================================
  describe "#cfg" do
    it "reads a String-keyed value" do
      expect(broker.public_cfg({ "token_url" => "https://idp/token" }, :token_url))
        .to eq("https://idp/token")
    end

    it "reads a Symbol-keyed value" do
      expect(broker.public_cfg({ token_url: "https://idp/token" }, :token_url))
        .to eq("https://idp/token")
    end

    it "accepts a String key argument as well as a Symbol" do
      expect(broker.public_cfg({ "audience" => "api://x" }, "audience")).to eq("api://x")
    end

    it "returns nil when the key is absent" do
      expect(broker.public_cfg({ "other" => "x" }, :token_url)).to be_nil
    end

    it "returns nil when config is not a Hash" do
      expect(broker.public_cfg("nope", :token_url)).to be_nil
      expect(broker.public_cfg(nil, :token_url)).to be_nil
    end

    it "skips a blank ('') value and falls through to a later present key" do
      # The first key is present-but-blank; the tolerant read must SKIP it and
      # return the next non-blank key's value (blank-skip fallback contract).
      result = broker.public_cfg({ "primary" => "", "fallback" => "https://idp/token" },
                                 :primary, :fallback)
      expect(result).to eq("https://idp/token")
    end

    it "treats a present non-empty value as a hit (does not skip)" do
      result = broker.public_cfg({ "primary" => "https://first/token", "fallback" => "https://second/token" },
                                 :primary, :fallback)
      expect(result).to eq("https://first/token")
    end

    it "returns a non-string scalar (e.g. an Integer that does not respond to #empty?)" do
      # skew_seconds-style numeric knob: respond_to?(:empty?) is false, so the
      # !value.nil? branch returns the number as a hit.
      expect(broker.public_cfg({ "skew_seconds" => 30 }, :skew_seconds)).to eq(30)
    end

    it "returns false as a hit (present, not nil, no #empty?)" do
      expect(broker.public_cfg({ "flag" => false }, :flag)).to be(false)
    end
  end

  # ==========================================================================
  # #broker_http_connection: validate_url! THEN build, passing max_redirects:
  # through. SSRF guard + factory are stubbed so nothing dials out.
  # ==========================================================================
  describe "#broker_http_connection" do
    let(:conn) { instance_double(Faraday::Connection) }
    let(:url) { "https://idp.example.com/oauth/token" }

    before do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    end

    it "fails fast through HttpConnectionFactory.validate_url! with the absolute url BEFORE building" do
      broker.public_broker_http_connection(url, data_source: data_source, max_redirects: 0)

      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:validate_url!).with(url)
    end

    it "returns the SSRF-guarded connection built by HttpConnectionFactory.build" do
      expect(
        broker.public_broker_http_connection(url, data_source: data_source, max_redirects: 0)
      ).to be(conn)
    end

    it "passes the max_redirects: kwarg straight through to .build (e.g. 0 to forbid 3xx-following)" do
      broker.public_broker_http_connection(url, data_source: data_source, max_redirects: 0)

      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:build)
        .with(data_source: data_source, agent: nil, max_redirects: 0)
    end

    it "forwards the agent through to .build when supplied" do
      agent = instance_double(Ai::Agent)
      broker.public_broker_http_connection(url, data_source: data_source, agent: agent, max_redirects: 0)

      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:build)
        .with(data_source: data_source, agent: agent, max_redirects: 0)
    end

    it "skips validate_url! when the url is blank (no fail-fast, nothing to pin)" do
      broker.public_broker_http_connection("", data_source: data_source, max_redirects: 0)

      expect(Ai::DataSources::HttpConnectionFactory).not_to have_received(:validate_url!)
      # build is still called (the connection guards each request regardless).
      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:build)
    end

    it "propagates an SsrfError raised by validate_url! (a bad host fails fast, no socket)" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!)
        .and_raise(Ai::DataSources::HttpConnectionFactory::SsrfError.new("blocked host"))

      expect do
        broker.public_broker_http_connection("https://169.254.169.254/latest", data_source: data_source)
      end.to raise_error(Ai::DataSources::HttpConnectionFactory::SsrfError)

      # Fail-fast: .build is never reached once the URL is rejected.
      expect(Ai::DataSources::HttpConnectionFactory).not_to have_received(:build)
    end
  end

  # ==========================================================================
  # #audit_log: a single NON-SECRET Rails.logger line carrying broker/source/
  # outcome (+ any extra non-secret meta), and NEVER a secret.
  # ==========================================================================
  describe "#audit_log" do
    it "writes one Rails.logger.info line tagged with the demodulized broker class" do
      expect(Rails.logger).to receive(:info).once
        .with(a_string_matching(/\A\[Credentials::TestProbeBroker\]/))

      broker.public_audit_log(data_source, "acquired")
    end

    it "includes broker, source, and outcome tokens" do
      expect(Rails.logger).to receive(:info).once do |line|
        expect(line).to include("broker=test_probe")
        expect(line).to include("source=weather_src")
        expect(line).to include("outcome=acquired")
      end

      broker.public_audit_log(data_source, "acquired")
    end

    it "interpolates extra NON-SECRET meta key=value pairs" do
      expect(Rails.logger).to receive(:info).once do |line|
        expect(line).to include("outcome=cached")
        expect(line).to include("expires_at=2026-01-01T00:00:00Z")
        expect(line).to include("reason=hit")
      end

      broker.public_audit_log(data_source, "cached",
                              expires_at: "2026-01-01T00:00:00Z", reason: "hit")
    end

    it "records source=unknown when the data source has no slug (does not raise)" do
      no_slug = Object.new # responds to neither slug nor much else
      expect(Rails.logger).to receive(:info).once
        .with(a_string_matching(/source=unknown/))

      broker.public_audit_log(no_slug, "skipped")
    end

    it "tolerates a nil data source (degrades to source=unknown, no exception)" do
      expect(Rails.logger).to receive(:info).once
        .with(a_string_matching(/source=unknown/))

      expect { broker.public_audit_log(nil, "skipped") }.not_to raise_error
    end

    it "never raises even if logging itself fails (audit must not crash the broker)" do
      allow(Rails.logger).to receive(:info).and_raise(StandardError, "logger down")

      expect { broker.public_audit_log(data_source, "acquired") }.not_to raise_error
    end
  end

  # ==========================================================================
  # #broker_type: derived from the class name, demodulized + underscored.
  # ==========================================================================
  describe "#broker_type" do
    it "derives the registry token from the class name (TestProbeBroker => test_probe)" do
      expect(broker.public_broker_type).to eq("test_probe")
    end
  end
end
