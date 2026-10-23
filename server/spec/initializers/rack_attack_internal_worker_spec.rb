# frozen_string_literal: true

require "rails_helper"

# Production incident: an embedding path made ~88 worker->server calls in five
# minutes to /api/v1/internal/*. Worker tokens resolve no account, so every one
# counted against api_requests_by_ip (300 per 15 minutes) under the worker's one
# IP, and the throttle then answered 429 to ALL worker->server traffic (sweeps,
# agent runs, dispatch_tool) for 15 minutes.
#
# A request carrying a VERIFIED worker credential must not count. A path alone
# must never be enough: an anonymous or badly-signed request to /internal/ is
# exactly the traffic the IP throttle exists for.
RSpec.describe "Rack::Attack internal worker traffic" do
  let(:app) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] } }
  let(:middleware) { Rack::Attack.new(app) }
  let(:ip) { "198.51.100.#{rand(1..250)}" }
  let(:path) { "/api/v1/internal/ai/embedding_config" }
  let(:limit) { 3 }

  # api_requests_by_ip is registered only outside the test env, so the spec
  # registers a stand-in with the same discriminator shape (an /api/ path with no
  # resolved account, keyed by IP). What is under test is the safelist, which
  # exists in every env and short-circuits every throttle.
  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    cap = limit
    Rack::Attack.throttle("spec_api_requests_by_ip", limit: cap, period: 15.minutes) do |request|
      request.ip if request.path.start_with?("/api/")
    end
    example.run
  ensure
    Rack::Attack.throttles.delete("spec_api_requests_by_ip")
    Rack::Attack.cache.store = original_store
  end

  def worker_token(id: SecureRandom.uuid, exp: 1.hour.from_now)
    Security::JwtService.encode_for_worker({ sub: id, type: "worker" }, exp)
  end

  def status_for(request_path, token: nil, headers: {})
    env = Rack::MockRequest.env_for(request_path, "REMOTE_ADDR" => ip, "HTTP_AUTHORIZATION" => (token && "Bearer #{token}"))
    headers.each { |k, v| env[k] = v }
    env.delete("HTTP_AUTHORIZATION") unless token
    middleware.call(env).first
  end

  def statuses(count, request_path = path, **opts)
    Array.new(count) { status_for(request_path, **opts) }
  end

  it "counts anonymous internal requests (the control: the throttle is live)" do
    expect(statuses(limit + 3).last).to eq(429)
  end

  it "never throttles internal requests carrying a valid worker token" do
    token = worker_token

    expect(statuses(limit * 10, token: token).uniq).to eq([ 200 ])
  end

  it "does not let valid worker traffic eat the budget of an anonymous request from the same IP" do
    statuses(limit * 10, token: worker_token)

    expect(statuses(limit).uniq).to eq([ 200 ])
  end

  it "still counts an internal request whose token is signed with the wrong secret" do
    forged = JWT.encode({ sub: SecureRandom.uuid, type: "worker", aud: "worker",
                          iss: Rails.application.config.jwt_issuer, exp: 1.hour.from_now.to_i }, "not-the-secret", "HS256")

    expect(statuses(limit + 3, token: forged).last).to eq(429)
  end

  it "still counts an internal request whose worker token has expired" do
    expect(statuses(limit + 3, token: worker_token(exp: 1.hour.ago)).last).to eq(429)
  end

  it "still counts an internal request carrying a user access token (wrong audience)" do
    user = create(:user)
    access = Security::JwtService.encode({ sub: user.id, type: "access" })

    expect(statuses(limit + 3, token: access).last).to eq(429)
  end

  it "still counts an internal request with a garbage Authorization header" do
    expect(statuses(limit + 3, token: "garbage").last).to eq(429)
  end

  it "does not safelist a valid worker token outside /api/v1/internal/" do
    token = worker_token

    expect(statuses(limit + 3, "/api/v1/something_else", token: token).last).to eq(429)
  end

  it "does not safelist a path that merely contains /internal/" do
    token = worker_token

    expect(statuses(limit + 3, "/api/v1/x/api/v1/internal/y", token: token).last).to eq(429)
    expect(statuses(limit + 3, "/api/v1/internalx/y", token: token).last).to eq(429)
  end

  it "fails closed, still counting, when the verifier raises" do
    token = worker_token
    allow(Security::JwtKeyStore).to receive(:worker_auth_secret).and_raise(StandardError, "no secret")
    allow(Rails.logger).to receive(:error)

    expect(statuses(limit + 3, token: token).last).to eq(429)
    expect(Rails.logger).to have_received(:error).with(/worker token check failed/).at_least(:once)
  end

  context "with a client certificate" do
    let(:worker) { create(:worker) }
    let(:pem) { { "HTTP_X_FORWARDED_TLS_CLIENT_CERT" => "forwarded-pem" } }

    it "exempts a cert that verifies against our CA and names an active worker" do
      allow(Security::MtlsTrust).to receive(:verify_request)
        .with(anything, require_pem: true).and_return(worker.node_instance_id)

      expect(statuses(limit * 5, path, headers: pem).uniq).to eq([ 200 ])
    end

    it "keeps counting a cert that does not verify" do
      allow(Security::MtlsTrust).to receive(:verify_request).and_return(nil)

      expect(statuses(limit + 3, path, headers: pem).last).to eq(429)
    end

    it "keeps counting a verified cert whose CN is no active worker" do
      allow(Security::MtlsTrust).to receive(:verify_request).and_return(SecureRandom.uuid)

      expect(statuses(limit + 3, path, headers: pem).last).to eq(429)
    end

    it "keeps counting a bare forwarded subject header with no PEM, which a client could forge" do
      info = { "HTTP_X_FORWARDED_TLS_CLIENT_CERT_INFO" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }

      expect(statuses(limit + 3, path, headers: info).last).to eq(429)
    end
  end
end
