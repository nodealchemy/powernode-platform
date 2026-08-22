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
      Worker.where(is_system: true).first || Worker.find_by(name: WORKER_NAME)
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

    def reaffirm(worker)
      updates = {}
      updates[:account_id] = @account.id if worker.account_id != @account.id
      updates[:is_system]  = true unless worker.is_system?
      worker.update_columns(updates) if updates.any?
      bind_dev_sentinel(worker)
      worker
    end

    # Deterministic token from the environment in prod; generated otherwise.
    def worker_token
      ENV["WORKER_TOKEN"].presence || "swt_#{SecureRandom.urlsafe_base64(32)}"
    end

    # No-op outside development; in prod the worker presents a real cert.
    def bind_dev_sentinel(worker)
      return unless Rails.env.development?

      sentinel = ENV.fetch("DEV_WORKER_NODE_INSTANCE_ID", DEV_SENTINEL_NODE_ID)
      worker.update_columns(node_instance_id: sentinel) if worker.node_instance_id != sentinel
    end
  end
end
