# frozen_string_literal: true

# Revokes the published development mTLS sentinel at boot, outside development.
#
# `Workers::EnsureSystemWorker::DEV_SENTINEL_NODE_ID` is a fixed literal in a
# public MIT repository, and `workers.node_instance_id` is the column
# MtlsClientAuthentication resolves the worker principal from — on the no-PEM
# posture the forwarded Subject CN is trusted without re-verification, so for a
# row carrying the sentinel, possession of that published string IS the
# credential.
#
# EnsureSystemWorker only unbinds it when something invokes the service, and on
# the database this exists for nothing does: `db:seed` is not part of a
# production boot, and Setup::FirstAdminService raises AlreadyBootstrapped
# before reaching it once a user exists. A database bootstrapped in development
# and later promoted has both a user and the sentinel, so the revocation needs a
# call site that runs on its own. This is that call site.
#
# Guards mirror config/initializers/setup_bootstrap.rb:
#   * NOT development      — that is the one environment where the binding is
#     legitimate and load-bearing (BackendApiClient presents it as the CN).
#     This is the ONLY environment decision on this path; the service seam
#     carries no second env check that could mask this one.
#   * `Rails::Server` defined — only under `rails server` / puma, never under
#     console, rake tasks, or the test suite.
#   * `workers` table present — never touch the DB before it is migrated
#     (db:create / db:migrate), and never block boot on errors.
Rails.application.config.after_initialize do
  next if Rails.env.development?
  next unless defined?(Rails::Server) || ENV["POWERNODE_FORCE_SENTINEL_REVOKE"] == "true"

  begin
    if ActiveRecord::Base.connection.table_exists?("workers")
      Workers::EnsureSystemWorker.revoke_dev_sentinel!
    end
  rescue StandardError => e
    Rails.logger.warn("[worker-sentinel] revocation skipped: #{e.class}: #{e.message}")
  end
end
