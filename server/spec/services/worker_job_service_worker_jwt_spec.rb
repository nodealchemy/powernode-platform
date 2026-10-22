# frozen_string_literal: true

require "rails_helper"

# Server-to-worker job auth is separate from user-token rotation. The worker
# verifies the JWTs the server sends it with ENV["JWT_SECRET_KEY"] (HS256)
# and has no path to JwtKeyStore, so those JWTs are always signed with
# JWT_SECRET_KEY. Rotating the user-token HMAC secret must leave them alone;
# the worker secret rotates through the secrets file and a restart.
RSpec.describe WorkerJobService, ".system_worker_jwt" do
  let(:env_secret) { Rails.application.config.jwt_secret_key }
  let(:worker) { instance_double(Worker, id: SecureRandom.uuid, active?: true) }

  before do
    Thread.current[:_system_worker_jwt] = nil
    Security::JwtKeyStore.clear_cache!
    allow(Worker).to receive(:system_worker).and_return(worker)
    # spec/support/worker_job_service_stub.rb stubs this globally.
    allow(described_class).to receive(:system_worker_jwt).and_call_original
  end

  after do
    Thread.current[:_system_worker_jwt] = nil
    Security::JwtKeyStore.clear_cache!
  end

  # The worker's own check (worker/app/controllers/jobs_controller.rb).
  def worker_accepts?(token)
    decoded = JWT.decode(token, env_secret, true, algorithm: "HS256")[0]
    decoded["type"] == "worker" && decoded["sub"].present?
  rescue JWT::DecodeError
    false
  end

  it "is accepted by the worker's verification" do
    expect(worker_accepts?(described_class.system_worker_jwt)).to be(true)
  end

  it "is still accepted by the worker after a user-token HS256 rotation" do
    allow(Rails.application.config).to receive(:jwt_algorithm).and_return("HS256")
    Security::JwtKeyStore.rotate_hmac!(grace_hours: 24)
    Thread.current[:_system_worker_jwt] = nil

    expect(worker_accepts?(described_class.system_worker_jwt)).to be(true)
  end

  it "is signed with JWT_SECRET_KEY even under RS256, which is all the worker can verify" do
    allow(Rails.application.config).to receive(:jwt_algorithm).and_return("RS256")

    expect(worker_accepts?(described_class.system_worker_jwt)).to be(true)
  end
end
