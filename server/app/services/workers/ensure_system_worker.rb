# frozen_string_literal: true

module Workers
  # Idempotently ensures the single global system Worker exists, bound to the
  # given account.
  #
  # The system worker authenticates worker→backend API calls
  # (WorkerJobService.system_worker_jwt). It is a bootstrap invariant, not a seed
  # artifact: it must exist in every install. Created on first-account bootstrap
  # (Setup::FirstAdminService) and re-affirmed by db:seed, so core/prod (wizard)
  # and demo/dev (seeds) both get it. Safe to call repeatedly.
  class EnsureSystemWorker
    WORKER_NAME = "System Worker"
    SYSTEM_ROLE = "system_worker"
    # Dev-only sentinel node id the worker injects via the mTLS client-cert
    # header (BackendApiClient, dev only) so header-based auth survives rebuilds.
    #
    # Because this literal is PUBLISHED, a row still carrying it outside
    # development is a credential anyone can read off GitHub. `bind_dev_sentinel`
    # therefore clears exactly this value whenever it runs outside development;
    # see there.
    #
    # DUPLICATED, BY NECESSITY, in the worker as
    # DevMtlsHeader::DEV_SENTINEL_NODE_ID
    # (worker/app/services/dev_mtls_header.rb). The two apps are separate
    # Ruby processes with separate bundles and no shared load path, so there is
    # no constant that can genuinely reach both — change this literal and you
    # MUST change that one. The two are pinned together by
    # server/spec/security/dev_mtls_header_contract_spec.rb, which drives the
    # worker's real emitter through this server's real parser.
    DEV_SENTINEL_NODE_ID = "00000000-0000-7000-8000-000000000001"

    # @param account [Account, nil] account to bind to; defaults to the first account.
    # @return [Worker, nil] the system worker, or nil when no account exists yet.
    def self.call(account: nil)
      new(account: account).call
    end

    # The single global system worker, or nil. Same resolution `call` uses.
    def self.system_worker
      Worker.where(is_system: true).first || Worker.find_by(name: WORKER_NAME)
    end

    # Revokes the published development sentinel from an already-bootstrapped
    # database, CREATING NOTHING.
    #
    # `call` cannot serve this: it requires an Account and creates the system
    # worker when absent, which is wrong at boot. And it is not reachable on the
    # database this exists for — its two callers are `db:seed` (not part of a
    # production boot) and Setup::FirstAdminService, which raises
    # AlreadyBootstrapped before it ever reaches EnsureSystemWorker once a user
    # exists. A database bootstrapped in development and later promoted has both
    # a user and the sentinel, so without this seam the clear below would never
    # run there. config/initializers/worker_dev_sentinel_revocation.rb calls it.
    #
    # Deliberately carries NO Rails.env check: each call path decides the
    # environment exactly once — the initializer for boot, #bind_dev_sentinel for
    # the bootstrap path — so there is no second guard to mask the first.
    #
    # @param worker [Worker, nil] defaults to the system worker.
    # @return [Boolean] true when a sentinel was actually cleared.
    def self.revoke_dev_sentinel!(worker = nil)
      worker ||= system_worker
      return false unless worker
      return false unless worker.node_instance_id == DEV_SENTINEL_NODE_ID

      worker.update_columns(node_instance_id: nil)
      Rails.logger.warn(
        "[Workers::EnsureSystemWorker] cleared the development mTLS sentinel from " \
        "system worker #{worker.id} in #{Rails.env}. DEV_SENTINEL_NODE_ID is a " \
        "published constant, so until now any caller able to present it as a " \
        "forwarded client-cert subject CN would have authenticated as this worker. " \
        "This database was bootstrapped in development; audit it accordingly."
      )
      audit_sentinel_revocation(worker)
      true
    end

    # Revoking an mTLS identity is a key operation, so it goes to the audit log
    # and not only to the app log. Never records the credential value itself.
    # Failure here must not abort the revocation — the clear has already
    # committed and is the security-relevant half.
    def self.audit_sentinel_revocation(worker)
      Audit::LoggingService.instance.log(
        action: "worker.mtls_dev_sentinel_revoked",
        resource: worker,
        account: worker.account,
        details: { reason: "published development sentinel found outside development", environment: Rails.env.to_s }
      )
    rescue StandardError => e
      Rails.logger.error("[Workers::EnsureSystemWorker] sentinel revocation audit failed: #{e.class}: #{e.message}")
      nil
    end
    private_class_method :audit_sentinel_revocation

    def initialize(account: nil)
      @account = account || Account.first
    end

    def call
      return nil unless @account

      worker = existing_system_worker
      worker ? reaffirm(worker) : create_worker
    rescue StandardError => e
      Rails.logger.error("[Workers::EnsureSystemWorker] #{e.class}: #{e.message}")
      nil
    end

    private

    def existing_system_worker
      self.class.system_worker
    end

    def create_worker
      worker = Worker.create_worker!(
        name: WORKER_NAME,
        description: "System worker for background processing and API communication",
        account: @account,
        is_system: true,
        roles: [ SYSTEM_ROLE ],
        token: worker_token
      )
      bind_dev_sentinel(worker)
      Rails.logger.info("[Workers::EnsureSystemWorker] created system worker #{worker.id}")
      worker
    end

    # The sentinel binding runs FIRST, ahead of the account/is_system fixups.
    # Those write to `is_system`, which carries a unique partial index, and to
    # `account_id`, which carries an FK — either can raise, and `call`'s blanket
    # `rescue StandardError` would then swallow the revocation silently. A
    # security-critical clear must not sit downstream of an unrelated fallible
    # write.
    def reaffirm(worker)
      bind_dev_sentinel(worker)
      updates = {}
      updates[:account_id] = @account.id if worker.account_id != @account.id
      updates[:is_system]  = true unless worker.is_system?
      worker.update_columns(updates) if updates.any?
      worker
    end

    # Deterministic token from the environment in prod; generated otherwise.
    def worker_token
      ENV["WORKER_TOKEN"].presence || "swt_#{SecureRandom.urlsafe_base64(32)}"
    end

    # Binds the dev sentinel in development, and REVOKES it everywhere else.
    #
    # The binding has to be symmetric. `workers.node_instance_id` is the mTLS
    # worker credential — MtlsClientAuthentication#authenticate_worker_via_mtls!
    # resolves the principal with `Worker.find_by(node_instance_id: cn)`, and on
    # the no-PEM posture the forwarded Subject CN is trusted without
    # re-verification, so possession of the CN STRING is possession of the
    # credential. DEV_SENTINEL_NODE_ID is a fixed literal in a public MIT
    # repository.
    #
    # An env-guarded write with no matching env-guarded unwrite is therefore a
    # one-way door: this method used to `return unless Rails.env.development?`,
    # which declined to WRITE the sentinel outside development but left one an
    # earlier development run had already written. Bootstrap a database in
    # development (the documented local workflow — db/seeds.rb and
    # Setup::FirstAdminService both run against whatever database is in front of
    # them), later run that same database in production, and it carries a system
    # Worker whose credential is published.
    #
    # `revoke_dev_sentinel!` clears ONLY the published literal, never an
    # arbitrary value: outside development a system worker's node_instance_id is
    # a legitimately enrolled NodeInstance id (extensions/system's
    # powernode:worker:link_node_instances), and an unconditional null would
    # de-authenticate a live worker fleet on every /api/v1/internal route.
    # Over-clearing is an outage; under-clearing leaves a value this repository
    # does not disclose.
    #
    # RULING on an operator-set ENV["DEV_WORKER_NODE_INSTANCE_ID"]: it is NOT
    # cleared, and is not consulted when clearing. The process doing the
    # clearing is not the process that wrote the row, so its env says nothing
    # about what is in the column; and in the one case where that var IS set
    # outside development, honouring it would null a binding an operator
    # deliberately configured. The published constant is the disclosed
    # credential; a private override is not, and core cannot tell an override
    # apart from a real enrolled id — which is also why there is no warning on
    # the surviving-value case: on a correctly provisioned platform that IS the
    # healthy state, and a warning that fires on every healthy install would
    # train operators past the real alarm above it.
    def bind_dev_sentinel(worker)
      return self.class.revoke_dev_sentinel!(worker) unless Rails.env.development?

      sentinel = ENV.fetch("DEV_WORKER_NODE_INSTANCE_ID", DEV_SENTINEL_NODE_ID)
      worker.update_columns(node_instance_id: sentinel) if worker.node_instance_id != sentinel
    end
  end
end
