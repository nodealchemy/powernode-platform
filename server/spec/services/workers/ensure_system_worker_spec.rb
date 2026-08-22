# frozen_string_literal: true

require "rails_helper"

# The subject here is the SYMMETRY of the development sentinel binding, not
# either steady state.
#
# `workers.node_instance_id` is the mTLS worker credential:
# MtlsClientAuthentication#authenticate_worker_via_mtls! resolves the principal
# with `Worker.find_by(node_instance_id: verified_cn)`, and on the no-PEM
# posture the forwarded Subject CN is trusted without re-verification, so
# possession of the CN STRING is possession of the credential.
# `DEV_SENTINEL_NODE_ID` is a fixed literal in a public MIT repository.
#
# A spec that only runs outside development and asserts nothing gets bound
# PASSES against the unfixed code. The bug is exclusively about a row that
# ALREADY carries the sentinel, so every oracle below drives a TRANSITION.
RSpec.describe Workers::EnsureSystemWorker do
  # A REAL enrolled NodeInstance id — what a production system worker linked by
  # extensions/system's powernode:worker:link_node_instances rake task carries.
  # Deliberately not the sentinel and not derived from it.
  REAL_ENROLLED_NODE_ID = "019f7cb5-1111-7000-8000-00000000feed"

  # `let!`, not `let`: the fixture MUST be created before any example stubs
  # Rails.env. Created lazily inside that window, `create(:account)` would run
  # with Rails.env reporting "production", which un-guards `Rails.env.test?`
  # checks it is supposed to be protected by — Account#broadcast_customer_change
  # and, more dangerously, the Redis test-database isolation in
  # config/initializers/redis.rb, which would target shared db 0.
  let!(:account) { create(:account) }

  # `def`, never `let`: a memoizing helper reads the column ONCE and would then
  # report the pre-transition value forever, passing against unfixed code.
  # Re-queried straight from the database because the service writes with
  # update_columns, which leaves any in-memory instance stale.
  def stored_node_instance_id(worker)
    Worker.uncached { Worker.where(id: worker.id).pick(:node_instance_id) }
  end

  # Re-stubbing Rails.env inside a single example IS the transition: the same
  # database row survives a process that used to be development and is now not.
  def ensure_in(env_name, for_account: nil)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(env_name))
    described_class.call(account: for_account || account)
  end

  def with_env_var(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end

  describe "the development sentinel across a development -> production transition" do
    # THE ORACLE. Bootstrap in development (the documented local workflow),
    # then run that same database outside development.
    it "clears a sentinel an earlier development run already wrote" do
      worker = ensure_in("development")
      expect(stored_node_instance_id(worker)).to eq(described_class::DEV_SENTINEL_NODE_ID)

      ensure_in("production")

      expect(stored_node_instance_id(worker)).to be_nil
    end

    it "warns when it finds and clears a sentinel outside development" do
      worker = ensure_in("development")
      expect(stored_node_instance_id(worker)).to eq(described_class::DEV_SENTINEL_NODE_ID)

      allow(Rails.logger).to receive(:warn)
      ensure_in("production")

      expect(Rails.logger).to have_received(:warn).with(/cleared the development mTLS sentinel/)
    end

    # Revoking an mTLS identity is a key operation, so it must reach the audit
    # log — and must not carry the credential into it.
    it "audits the revocation without recording the credential value" do
      ensure_in("development")

      logged = nil
      allow(Audit::LoggingService.instance).to receive(:log) { |**kwargs| logged = kwargs }
      ensure_in("production")

      expect(logged).to be_present
      expect(logged[:action]).to eq("worker.mtls_dev_sentinel_revoked")
      expect(logged.to_s).not_to include(described_class::DEV_SENTINEL_NODE_ID)
    end

    # ORDERING. `reaffirm` also fixes up account_id (FK) and is_system (unique
    # partial index); either write can raise, and `call`'s blanket
    # `rescue StandardError` swallows it. With the clear downstream of that
    # write, an unrelated failure silently leaves the published credential live.
    it "clears the sentinel even when the account fixup raises" do
      worker = ensure_in("development")
      other_account = create(:account)

      allow_any_instance_of(Worker).to receive(:update_columns).and_wrap_original do |orig, attrs|
        raise ActiveRecord::RecordNotUnique, "simulated fixup failure" if attrs.key?(:account_id) || attrs.key?(:is_system)

        orig.call(attrs)
      end

      ensure_in("production", for_account: other_account)

      expect(stored_node_instance_id(worker)).to be_nil
    end

    # THE NEGATIVE, and the one with outage potential. A production system
    # worker's node_instance_id is a legitimately enrolled NodeInstance id;
    # nulling it de-authenticates a live worker on every /api/v1/internal route.
    # This passes against the unfixed early-return too — its job is to fail
    # against an OVER-BROAD fix, and a mutation run confirms it does.
    #
    # There is deliberately no development leg here: in development the binding
    # legitimately OVERWRITES whatever is present, so a real id cannot survive a
    # development run by design.
    it "leaves a real enrolled node_instance_id untouched outside development" do
      worker = create(:worker, :system_worker,
                      account: account,
                      name: described_class::WORKER_NAME,
                      node_instance_id: REAL_ENROLLED_NODE_ID)

      ensure_in("production")
      ensure_in("production")

      expect(stored_node_instance_id(worker)).to eq(REAL_ENROLLED_NODE_ID)
    end

    # RULING on DEV_WORKER_NODE_INSTANCE_ID: an operator-chosen override is NOT
    # cleared. Only the published literal is. Deciding what to DESTROY from the
    # env of the *later* process is unsound — that process is not the one that
    # wrote the row, and in the single case where the var IS set there it would
    # null a binding the operator deliberately configured.
    it "leaves an operator-configured DEV_WORKER_NODE_INSTANCE_ID binding in place" do
      configured = "019f7cb5-2222-7000-8000-0000000000aa"
      worker = with_env_var("DEV_WORKER_NODE_INSTANCE_ID", configured) { ensure_in("development") }
      expect(stored_node_instance_id(worker)).to eq(configured)

      ensure_in("production")

      expect(stored_node_instance_id(worker)).to eq(configured)
    end
  end

  # The bootstrap callers do not reach a promoted database: db:seed is not part
  # of a production boot, and Setup::FirstAdminService raises AlreadyBootstrapped
  # before reaching this service once a user exists. This seam is what
  # config/initializers/worker_dev_sentinel_revocation.rb calls at boot, so it
  # must work with no Account argument and must create nothing.
  describe ".revoke_dev_sentinel!" do
    it "clears the sentinel with no account argument and no seed run" do
      worker = ensure_in("development")
      RSpec::Mocks.space.proxy_for(Rails).reset

      expect(described_class.revoke_dev_sentinel!).to be(true)

      expect(stored_node_instance_id(worker)).to be_nil
    end

    it "leaves a real enrolled node_instance_id untouched and reports no change" do
      worker = create(:worker, :system_worker,
                      account: account,
                      name: described_class::WORKER_NAME,
                      node_instance_id: REAL_ENROLLED_NODE_ID)

      expect(described_class.revoke_dev_sentinel!).to be(false)

      expect(stored_node_instance_id(worker)).to eq(REAL_ENROLLED_NODE_ID)
    end

    it "creates nothing when there is no system worker" do
      expect { described_class.revoke_dev_sentinel! }.not_to change(Worker, :count)
      expect(described_class.revoke_dev_sentinel!).to be(false)
    end
  end

  describe "steady states" do
    it "binds the sentinel in development" do
      worker = ensure_in("development")

      expect(stored_node_instance_id(worker)).to eq(described_class::DEV_SENTINEL_NODE_ID)
    end

    it "never binds the sentinel on a worker first created outside development" do
      worker = ensure_in("production")

      expect(worker).to be_present
      expect(stored_node_instance_id(worker)).to be_nil
    end
  end
end
