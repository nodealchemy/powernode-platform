# frozen_string_literal: true

# On Sidekiq server boot, verify the on-host agent has provisioned PKI
# material we can read. Workers are deployed as NodeInstances (Stage 8b),
# so cert lifecycle is the agent's responsibility — we only check that
# the files exist and surface CN + expiry to the log.
#
# In test env we skip — specs stub WorkerCertManager.instance.
return if defined?(::Rails) && ::Rails.env.test?
return if ENV['WORKER_CERT_MANAGER_DISABLED'] == 'true'

Sidekiq.configure_server do |_|
  begin
    require_relative '../../app/services/worker_cert_manager'
    manager = WorkerCertManager.instance
    Rails.logger.info(
      "[WorkerCertManager] using agent-managed PKI " \
      "(CN=#{manager.common_name} expires=#{manager.not_after.iso8601})"
    ) if defined?(Rails)
  rescue StandardError => e
    # If the agent hasn't written cert material yet (e.g., enrollment in
    # progress, host misconfigured), fail loud — the worker can't auth
    # to the platform without it.
    raise "[WorkerCertManager] startup failed: #{e.class}: #{e.message}"
  end
end
