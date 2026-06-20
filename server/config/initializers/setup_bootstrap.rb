# frozen_string_literal: true

# First-run setup announcer.
#
# When the backend boots with no administrator, print a one-time, token-gated
# setup URL to the service console (see Setup::BootstrapService). Guards:
#   * `Rails::Server` defined  — only under `rails server` / puma, never under
#     console, rake tasks, or the test suite.
#   * `users` table present    — never touch the DB before it is migrated
#     (e.g. during `db:create` / `db:migrate`), and never block boot on errors.
#
# Under preload_app! this runs in the puma master, so the URL is logged once.
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) || ENV["POWERNODE_FORCE_SETUP_ANNOUNCE"] == "true"

  begin
    if ActiveRecord::Base.connection.table_exists?("users")
      Setup::BootstrapService.announce!
    end
  rescue StandardError => e
    Rails.logger.warn("[setup] first-run announce skipped: #{e.class}: #{e.message}")
  end
end
