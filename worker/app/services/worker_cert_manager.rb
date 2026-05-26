# frozen_string_literal: true

require 'openssl'

# Reads the on-disk mTLS material that the on-host powernode-agent
# maintains. Workers are deployed as NodeInstances (Stage 8b); the agent
# is responsible for:
#   - initial enrollment (POST /api/v1/system/node_api/enroll)
#   - cert rotation (CertRotator goroutine, refresh at 75% TTL)
#   - atomic file replacement on rotation
#
# This class only READS — no rotation thread, no enrollment, no refresh
# endpoint calls. The Sidekiq worker process just consumes whatever the
# agent has written to /persist/var/lib/powernode/pki/ at request time.
# Faraday clients re-read on each `ssl_options` call so a fresh rotation
# is picked up without a worker restart.
class WorkerCertManager
  # Default path the agent writes to (per
  # extensions/system/agent/internal/enroll/storage.go).
  DEFAULT_PKI_DIR = '/persist/var/lib/powernode/pki'

  class << self
    def instance
      @instance ||= new
    end

    def reset!
      @instance = nil
    end
  end

  attr_reader :cert_path, :key_path, :ca_path

  def initialize(dir: nil)
    @dir = dir || ENV.fetch('WORKER_PKI_DIR', DEFAULT_PKI_DIR)
    @cert_path = File.join(@dir, 'node.crt')
    @key_path  = File.join(@dir, 'node.key')
    @ca_path   = File.join(@dir, 'ca-bundle.crt')
  end

  # Faraday `ssl:` options hash. Re-reads cert + key from disk each call
  # so post-rotation requests pick up the agent's new material atomically
  # (no in-process cache to invalidate). In test env (no PKI on disk)
  # returns a pass-through hash; specs that exercise the TLS path mock
  # WebMock at the request layer.
  #
  # SSL verification uses the system trust store (no ca_file set) — the
  # PLATFORM's server cert is signed by Let's Encrypt (or the public CA
  # in use), NOT by the internal CA. The internal CA bundle only matters
  # on the server-side: Traefik uses it to VERIFY the client cert this
  # worker presents. On the client side, we trust the platform's server
  # cert via the OS trust store.
  def ssl_options
    return { verify: false } if test_env? && !File.exist?(@cert_path)
    {
      client_cert: OpenSSL::X509::Certificate.new(File.read(@cert_path)),
      client_key:  OpenSSL::PKey.read(File.read(@key_path)),
      verify:      true
    }
  end

  # CN encoded in the leaf cert (= the backing NodeInstance.id). Used by
  # diagnostics + healthz endpoints.
  def common_name
    cert.subject.to_a.find { |k, *| k == 'CN' }&.[](1)
  end

  # Leaf cert NotAfter — surfaces to ops dashboards.
  def not_after
    cert.not_after
  end

  private

  def cert
    OpenSSL::X509::Certificate.new(File.read(@cert_path))
  end

  def test_env?
    (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.test?) ||
      ENV['RAILS_ENV'] == 'test'
  end
end
