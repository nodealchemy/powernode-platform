# frozen_string_literal: true

require "rails_helper"

# Production incident: an embedding path made ~88 worker->server calls in five
# minutes to /api/v1/internal/*. The worker reaches Puma through Traefik, so every
# call arrives from Traefik's loopback address and, carrying no account, counted
# against api_requests_by_ip (300 per 15 minutes) under that ONE address; the
# throttle then answered 429 to ALL worker->server traffic for 15 minutes.
#
# A request that identifies as an ACTIVE worker (forwarded client-cert subject CN,
# or a PEM that verifies against our CA) leaves the shared per-IP count and is
# counted per worker identity against a high ceiling instead. Nothing is simply
# unlimited, and a path alone never changes how a request is counted.
RSpec.describe "Rack::Attack internal worker traffic" do
  let(:app) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] } }
  let(:middleware) { Rack::Attack.new(app) }
  let(:ip) { "::1" }
  let(:path) { "/api/v1/internal/ai/embedding_config" }
  let(:ip_limit) { 3 }
  let(:worker_ceiling) { 12 }
  let(:worker) { create(:worker) }
  let(:cn) { worker.node_instance_id }

  # api_requests_by_ip is registered only outside the test env, so the spec
  # registers a stand-in that uses the REAL discriminator
  # (Rack::Attack.api_ip_throttle_key) with a small limit.
  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    cap = ip_limit
    Rack::Attack.throttle("spec_api_requests_by_ip", limit: cap, period: 15.minutes) do |request|
      Rack::Attack.api_ip_throttle_key(request)
    end
    example.run
  ensure
    Rack::Attack.throttles.delete("spec_api_requests_by_ip")
    Rack::Attack.cache.store = original_store
  end

  before do
    allow(Rack::Attack).to receive(:rate_limiting_enabled?).and_return(true)
    allow(Rack::Attack).to receive(:get_rate_limit).and_call_original
    allow(Rack::Attack).to receive(:get_rate_limit)
      .with("internal_worker_requests_per_15_minutes", anything).and_return(worker_ceiling)
  end

  def info_header(name)
    { "HTTP_X_FORWARDED_TLS_CLIENT_CERT_INFO" => CGI.escape(%(Subject="CN=#{name}")) }
  end

  def status_for(request_path, headers: {})
    env = Rack::MockRequest.env_for(request_path, "REMOTE_ADDR" => ip)
    headers.each { |k, v| env[k] = v }
    middleware.call(env).first
  end

  def statuses(count, request_path = path, headers: {})
    Array.new(count) { status_for(request_path, headers: headers) }
  end

  it "counts anonymous internal requests per IP (the control: the throttle is live)" do
    expect(statuses(ip_limit + 3).last).to eq(429)
  end

  it "pins the per-worker ceiling default at about 20k per 15 minutes" do
    allow(Rack::Attack).to receive(:get_rate_limit).and_call_original
    throttle = Rack::Attack.throttles["internal_worker_by_identity"]

    expect(throttle.limit.call(nil)).to eq(20_000)
    expect(throttle.period).to eq(15.minutes)
  end

  context "when the caller identifies as an active worker" do
    let(:headers) { info_header(cn) }

    it "leaves the per-IP count, so a worker burst cannot lock the shared address" do
      expect(statuses(ip_limit * 3, headers: headers).first(worker_ceiling).uniq).to eq([ 200 ])
    end

    it "keeps an anonymous request from the same address unthrottled by that burst" do
      statuses(worker_ceiling, headers: headers)

      expect(statuses(ip_limit).uniq).to eq([ 200 ])
    end

    it "is still bounded: past its own ceiling the worker is throttled" do
      expect(statuses(worker_ceiling + 3, headers: headers).last).to eq(429)
    end

    it "does not let one worker's traffic spend another's ceiling" do
      other = create(:worker)
      statuses(worker_ceiling + 3, headers: headers)

      expect(statuses(3, headers: info_header(other.node_instance_id)).uniq).to eq([ 200 ])
    end
  end

  context "when the caller does not prove an active worker" do
    it "still counts a CN that is no worker" do
      expect(statuses(ip_limit + 3, headers: info_header(SecureRandom.uuid)).last).to eq(429)
    end

    it "still counts the CN of an inactive worker" do
      worker.update_columns(status: "suspended")

      expect(statuses(ip_limit + 3, headers: info_header(cn)).last).to eq(429)
    end

    it "still counts a PEM that does not verify" do
      headers = info_header(cn).merge("HTTP_X_FORWARDED_TLS_CLIENT_CERT" => "garbage")

      expect(statuses(ip_limit + 3, headers: headers).last).to eq(429)
    end

    it "still counts a worker CN outside /api/v1/internal/" do
      expect(statuses(ip_limit + 3, "/api/v1/something_else", headers: info_header(cn)).last).to eq(429)
    end

    it "still counts a path that merely contains /internal/" do
      expect(statuses(ip_limit + 3, "/api/v1/x/api/v1/internal/y", headers: info_header(cn)).last).to eq(429)
      expect(statuses(ip_limit + 3, "/api/v1/internalx/y", headers: info_header(cn)).last).to eq(429)
    end

    it "fails closed, still counting per IP, when the identity check raises" do
      allow(Security::MtlsTrust).to receive(:verify_request).and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      expect(statuses(ip_limit + 3, headers: info_header(cn)).last).to eq(429)
      expect(Rails.logger).to have_received(:error).with(/internal worker identity check failed/).at_least(:once)
    end
  end

  context "with a client certificate PEM" do
    let(:pem) { { "HTTP_X_FORWARDED_TLS_CLIENT_CERT" => "forwarded-pem" } }

    it "recognises a PEM that verifies against our CA and names an active worker" do
      allow(Security::MtlsTrust).to receive(:verify_request).and_return(cn)

      expect(statuses(ip_limit * 3, headers: pem).first(worker_ceiling).uniq).to eq([ 200 ])
    end
  end
end
