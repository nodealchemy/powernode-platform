# frozen_string_literal: true

# Shared Faraday client builder for the Docker Engine API, used by the Swarm
# cluster jobs and the Docker host-sync job. Each built a byte-equivalent TLS
# Faraday client from the backend-provided connection details, differing only
# in request timeouts (two copies also carried a redundant ssl_options
# intermediate that this consolidates away).
#
# Includers must define a DOCKER_API_VERSION constant (the Engine API version
# segment of the base URL). It is read via self.class so each job keeps its own
# pinned version (e.g. swarm jobs v1.41, host-sync v1.45).
module DockerClientConcern
  extend ActiveSupport::Concern

  private

  # Build a Faraday client for the Docker Engine API from backend-provided
  # connection details (host/port + optional TLS material). timeout/open_timeout
  # default to the common 60s/10s; callers override per job.
  def build_docker_client(connection, timeout: 60, open_timeout: 10)
    scheme = connection["tls_enabled"] ? "https" : "http"
    base_url = "#{scheme}://#{connection['host']}:#{connection['port']}/#{self.class::DOCKER_API_VERSION}"

    Faraday.new(url: base_url) do |f|
      if connection["tls_enabled"]
        f.ssl.client_cert = OpenSSL::X509::Certificate.new(connection["client_cert"])
        f.ssl.client_key = OpenSSL::PKey::RSA.new(connection["client_key"])
        f.ssl.ca_file = connection["ca_cert_path"] if connection["ca_cert_path"]
        f.ssl.verify = connection.fetch("tls_verify", true)
      end
      f.options.timeout = timeout
      f.options.open_timeout = open_timeout
      f.adapter Faraday.default_adapter
    end
  end
end
