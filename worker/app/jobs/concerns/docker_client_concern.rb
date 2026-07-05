# frozen_string_literal: true

require "tempfile"

# Shared Faraday client builder for the Docker Engine API, used by the Swarm
# cluster jobs and the Docker host-sync job. Each built a byte-equivalent TLS
# Faraday client from the backend-provided connection details, differing only
# in request timeouts (two copies also carried a redundant ssl_options
# intermediate that this consolidates away).
#
# Includers must define a DOCKER_API_VERSION constant (the Engine API version
# segment of the base URL). It is read via self.class so each job keeps its own
# pinned version (e.g. swarm jobs v1.41, host-sync v1.45).
#
# Docker::HealthCheckJob keeps its own #build_docker_client (it hits both an
# unversioned endpoint (/_ping) and a versioned one (/v1.45/info) through the
# same connection, so it can't bake DOCKER_API_VERSION into base_url) but
# includes this concern to reuse the TLS-parsing helpers below.
module DockerClientConcern
  extend ActiveSupport::Concern

  private

  # Build a Faraday client for the Docker Engine API from backend-provided
  # connection details. The internal connection endpoints
  # (Api::V1::Internal::Devops::DockerController#connection /
  # SwarmController#connection) render {api_endpoint:, api_version:,
  # encrypted_tls_credentials:, tls_verify:, ...} — NOT a
  # host/port/tls_enabled/client_cert/client_key shape. timeout/open_timeout
  # default to the common 60s/10s; callers override per job.
  def build_docker_client(connection, timeout: 60, open_timeout: 10)
    tls_credentials = parse_tls_credentials(connection["encrypted_tls_credentials"])
    tls_verify = connection.fetch("tls_verify", true)
    base_url = "#{normalize_endpoint_scheme(connection['api_endpoint'], tls_verify, tls_credentials)}/#{self.class::DOCKER_API_VERSION}"

    Faraday.new(url: base_url) do |f|
      f.ssl.verify = tls_verify
      configure_tls(f, tls_credentials) if tls_credentials
      f.options.timeout = timeout
      f.options.open_timeout = open_timeout
      f.adapter Faraday.default_adapter
    end
  end

  # #build_docker_client bakes DOCKER_API_VERSION into base_url (e.g.
  # "https://host:2376/v1.41"). Faraday's URL joining follows RFC 3986: a
  # request path starting with "/" REPLACES base_url's path component
  # entirely instead of appending to it, so an absolute path silently drops
  # the baked-in version segment (Faraday.new(url: "https://host:2376/v1.41")
  # .get("/nodes") hits "https://host:2376/nodes", not ".../v1.41/nodes").
  # Every docker.get/post/put/delete call against a client built by
  # #build_docker_client MUST route its path through this helper — which
  # simply strips the leading slash so Faraday appends rather than replaces —
  # instead of passing a raw absolute path. Mirrors
  # Devops::Docker::ApiClient#versioned_path (server-side counterpart).
  def docker_path(path)
    path.sub(%r{\A/}, "")
  end

  # DockerHost/SwarmCluster#api_endpoint permits Docker's own "tcp://"
  # DOCKER_HOST convention, but "tcp" isn't an HTTP scheme Faraday
  # understands — its net_http adapter only enables TLS when
  # url.scheme == "https", so a raw tcp:// base_url would silently send
  # plaintext HTTP at dockerd's TLS-only listener. Mirrors
  # Devops::Docker::ApiClient#normalize_base_url (server-side counterpart).
  def normalize_endpoint_scheme(endpoint, tls_verify, tls_credentials)
    return endpoint unless endpoint.to_s.start_with?("tcp://")

    scheme = tls_verify || tls_credentials.present? ? "https" : "http"
    endpoint.sub(/\Atcp:\/\//, "#{scheme}://")
  end

  def configure_tls(faraday, tls_credentials)
    # A CA-only credential (server-verify-only TLS, no client mutual-auth
    # cert/key) is a legitimately reachable stored shape — Devops::
    # TlsCredentialParams#build_tls_credentials packs the blob whenever ANY
    # of tls_ca/tls_cert/tls_key is present, not all three. An asymmetric
    # pair (only one of client_cert/client_key present) is never legitimate,
    # so it's rejected loudly instead of silently falling back to CA-only
    # (which would look like working TLS while quietly skipping the
    # mutual-auth the operator configured).
    client_cert = tls_credentials[:client_cert]
    client_key = tls_credentials[:client_key]
    if client_cert.present? && client_key.present?
      faraday.ssl.client_cert = OpenSSL::X509::Certificate.new(client_cert)
      faraday.ssl.client_key = OpenSSL::PKey.read(clean_pem_key(client_key))
    elsif client_cert.present? || client_key.present?
      raise ArgumentError, "Invalid TLS credentials: client_cert and client_key must both be present, or both absent for server-verify-only TLS"
    end
    return if tls_credentials[:ca_cert].blank?

    # Write the CA cert to a tempfile for Faraday SSL verification. Stashed on
    # the Faraday connection itself (not a job-instance ivar) so its lifetime
    # is scoped 1:1 to the client it belongs to — jobs that loop over many
    # hosts/clusters per #execute build one client per iteration, and a
    # job-level ivar would get clobbered by each new iteration before GC ever
    # runs the previous tempfile's finalizer.
    ca_tempfile = Tempfile.new([ "docker-ca", ".pem" ])
    ca_tempfile.write(tls_credentials[:ca_cert])
    ca_tempfile.flush
    faraday.instance_variable_set(:@docker_client_ca_tempfile, ca_tempfile)
    faraday.ssl.ca_file = ca_tempfile.path
  end

  # Two producers pack the encrypted_tls_credentials blob under different key
  # names:
  #   - Devops::TlsCredentialParams (externally-registered hosts/clusters):
  #     ca_cert / client_cert / client_key
  #   - System::DockerDaemonProvisionerService (managed hosts, auto-
  #     registration): ca_chain_pem / client_cert_pem / client_key_pem
  # Accept either shape.
  def parse_tls_credentials(encrypted_tls_credentials)
    return nil if encrypted_tls_credentials.blank?

    creds = JSON.parse(encrypted_tls_credentials)
    {
      ca_cert: creds["ca_cert"] || creds["ca_chain_pem"],
      client_cert: creds["client_cert"] || creds["client_cert_pem"],
      client_key: creds["client_key"] || creds["client_key_pem"]
    }
  rescue JSON::ParserError
    nil
  end

  # Strip Docker Swarm metadata lines (kek-version, raft-dek, etc.) from PEM keys
  def clean_pem_key(key_pem)
    return key_pem if key_pem.blank?

    key_pem.lines.reject { |line| line.match?(/\A[a-z]+-[a-z]+:/i) || line.strip.empty? }.join
  end
end
