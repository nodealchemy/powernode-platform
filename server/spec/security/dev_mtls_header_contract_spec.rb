# frozen_string_literal: true

require "rails_helper"

# CROSS-APP CONTRACT: the dev mTLS client-cert header.
#
# Why this spec exists, and why it lives HERE:
#
# The header is one wire format with two independent implementations — the
# worker EMITS it (worker/app/services/dev_mtls_header.rb) and the server PARSES
# it (Security::MtlsTrust.forwarded_subject_cn). Nothing connected them, so
# either side could be edited without reddening a test on the other. That is
# exactly how the two sides came to disagree on the dev CN default: the server
# defaulted to a sentinel, the worker did not, and every /api/v1/internal/*
# call from the worker 401'd in development.
#
# Two mirror-image fixtures would not close that gap, so this spec drives the
# WORKER'S REAL EMITTER — it require_relative's the worker source file and calls
# it — and feeds the result through the REAL Security::MtlsTrust parser and the
# REAL MtlsClientAuthentication concern, over a real request.
#
# It lives in the server suite because only this suite has all three pieces: the
# parser, the Worker model, and ActiveRecord. The worker suite has no models, so
# it cannot assert that the CN RESOLVES to anything. The server suite in turn
# cannot load BackendApiClient (the server bundle has no `oj`/`faraday-retry`),
# which is why the emitter was extracted into a dependency-free file. The
# complement — proof that BackendApiClient actually puts DevMtlsHeader's value
# on the wire — is asserted in worker/spec/services/backend_api_client_spec.rb.
# require_relative, not Rails.root.join: pattern-validation.sh's "Zeitwerk shadow
# vector" guard forbids a spec from requiring an autoload root by ABSOLUTE path,
# because RSpec loads every spec file before running any example and such a
# require can shadow an autoloaded constant suite-wide. That hazard does not
# apply here — DevMtlsHeader lives in the WORKER's autoload root, which this
# app's Zeitwerk never manages — and require_relative is the form the guard
# itself documents as safe. It is also how BackendApiClient loads this file.
require_relative "../../../worker/app/services/dev_mtls_header"

RSpec.describe "Dev mTLS header contract (worker emitter -> server parser)", type: :request do
  let(:account) { create(:account) }
  let(:path)    { "/api/v1/internal/accounts/#{account.id}" }

  # Mutate the real ENV (restored after) so the emitter's own defaulting logic
  # is the thing under test, not a stub of it.
  def with_env(overrides)
    original = overrides.keys.to_h { |k| [ k, ENV[k] ] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # The header exactly as the worker emits it. NOT hand-written.
  def emitted_header(env: { "DEV_WORKER_NODE_INSTANCE_ID" => nil })
    with_env(env) { DevMtlsHeader.header_value }
  end

  # A REAL request, not an instance_double backed by a plain Hash. A Hash is
  # exact-match only, so doubles would not catch a header-name normalization
  # regression; ActionDispatch::Http::Headers is case-insensitive and aliases
  # X-Foo <-> HTTP_X_FOO the way production does.
  def request_with(header)
    ActionDispatch::TestRequest.create("HTTP_X_FORWARDED_TLS_CLIENT_CERT_INFO" => header)
  end

  describe "the header name" do
    it "is the same constant on both sides" do
      expect(DevMtlsHeader::HEADER).to eq(Security::MtlsTrust::SUBJECT_HEADER)
    end
  end

  # THE ORACLE. With DEV_WORKER_NODE_INSTANCE_ID unset — the normal dev state,
  # since no .env, compose file or script in the repo sets it — the worker must
  # emit a header AND the server must resolve it to the sentinel Worker.
  # A variant that SETS the env var passes against the bug and proves nothing.
  describe "with DEV_WORKER_NODE_INSTANCE_ID unset (the normal dev state)" do
    let(:sentinel) { Workers::EnsureSystemWorker::DEV_SENTINEL_NODE_ID }
    let!(:worker) do
      create(:worker, :system_worker, account: account,
                                      status: "active", node_instance_id: sentinel)
    end

    it "emits a header at all" do
      expect(emitted_header).to be_present
    end

    it "round-trips the CN through the real parser" do
      expect(Security::MtlsTrust.forwarded_subject_cn(request_with(emitted_header))).to eq(sentinel)
    end

    it "verify_request accepts the emitted header (no PEM present)" do
      expect(Security::MtlsTrust.verify_request(request_with(emitted_header))).to eq(sentinel)
    end

    it "authenticates end-to-end on a real /api/v1/internal/* route" do
      get path, headers: { Security::MtlsTrust::SUBJECT_HEADER => emitted_header }
      # :ok, not merely "not 401" — a 500 would satisfy the weaker form.
      expect(response).to have_http_status(:ok)
    end

    it "resolves to the sentinel Worker row the server bound" do
      cn = Security::MtlsTrust.forwarded_subject_cn(request_with(emitted_header))
      expect(Worker.find_by(node_instance_id: cn)).to eq(worker)
    end
  end

  # The emitter must also carry a configured CN through unchanged.
  describe "with DEV_WORKER_NODE_INSTANCE_ID set" do
    let(:configured) { "019f7cb5-3858-7000-8000-abcdefabcdef" }
    let!(:worker) do
      create(:worker, account: account, status: "active", node_instance_id: configured)
    end

    it "round-trips the configured CN and resolves it" do
      header = emitted_header(env: { "DEV_WORKER_NODE_INSTANCE_ID" => configured })
      get path, headers: { Security::MtlsTrust::SUBJECT_HEADER => header }
      expect(response).to have_http_status(:ok)
    end
  end

  # Without these the round-trip is a rubber stamp: a parser that returned the
  # sentinel for ANY input would pass everything above.
  #
  # Each negative asserts the ERROR MESSAGE too, not just the 401. The three
  # rejection branches in MtlsClientAuthentication emit distinct messages, so
  # the message is what proves a case reached the branch it is named for rather
  # than 401'ing incidentally (bad route, missing record, an unrelated filter).
  describe "fails closed" do
    def error_message
      JSON.parse(response.body)["error"]
    end

    it "401s at the cert check when no header is sent at all" do
      get path
      expect(response).to have_http_status(:unauthorized)
      expect(error_message).to eq("valid mTLS client certificate required")
    end

    it "401s at CN resolution on a well-formed header whose CN matches no Worker" do
      header = emitted_header(env: { "DEV_WORKER_NODE_INSTANCE_ID" => "019f7cb5-0000-7000-8000-000000000ccc" })
      get path, headers: { Security::MtlsTrust::SUBJECT_HEADER => header }

      expect(response).to have_http_status(:unauthorized)
      # Not the cert-check message: the header parsed fine, the CN just missed.
      expect(error_message).to eq("Worker not found for mTLS subject")
    end

    it "401s at the active? check when the resolved Worker is inactive" do
      inactive_cn = "019f7cb5-0000-7000-8000-000000000dde"
      inactive = create(:worker, account: account, status: "suspended", node_instance_id: inactive_cn)
      header = emitted_header(env: { "DEV_WORKER_NODE_INSTANCE_ID" => inactive_cn })

      get path, headers: { Security::MtlsTrust::SUBJECT_HEADER => header }

      expect(response).to have_http_status(:unauthorized)
      # Proves resolution SUCCEEDED and the liveness gate is what rejected it.
      expect(Worker.find_by(node_instance_id: inactive_cn)).to eq(inactive)
      expect(error_message).to eq("Worker is not active")
    end

    it "401s at the cert check on a header that is not the emitter's format" do
      get path, headers: { Security::MtlsTrust::SUBJECT_HEADER => "not-a-subject-string" }
      expect(response).to have_http_status(:unauthorized)
      expect(error_message).to eq("valid mTLS client certificate required")
    end
  end
end
