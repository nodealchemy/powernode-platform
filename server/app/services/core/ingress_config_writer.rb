# frozen_string_literal: true

require "yaml"
require "fileutils"
require "openssl"
require "socket"
require "securerandom"

module Core
  # Core-mode ingress baseline for the bundled Traefik reverse proxy — the
  # zero-extension HTTPS entrypoint every self-hosted install gets regardless
  # of which extensions are loaded.
  #
  # Owns three things:
  #
  #   1. The static Traefik config + the "services" block + the URL-
  #      resolution / path-resolution / host-rule helpers. These have zero
  #      System:: dependency (pure ENV + Rails.root + AdminSetting, all
  #      already core), so they live HERE as the single source of truth.
  #      `Acme::TraefikConfigWriter` (system extension) DELEGATES to these
  #      (thin one-line forwarders) instead of duplicating them, so the two
  #      writers can't drift apart.
  #   2. The provider seam: `write!` asks
  #      `Powernode::ExtensionRegistry.provider(:ingress_certs)` /
  #      `provider(:ingress_routers)` and, when BOTH are registered by the
  #      same writer, hands the ENTIRE per-account write to it, unchanged —
  #      this is what guarantees byte-identical output whenever the system
  #      extension is loaded (the exact same code path that ran before this
  #      seam existed). Nil ⇒ baseline (core mode).
  #   3. A baseline per-account dynamic file for when no provider is
  #      registered: a self-signed host cert + the four generic routers
  #      (api/agent/cable/frontend). Advanced routers (mTLS-bearing node/
  #      federation/worker APIs + the Sidekiq dashboard) are system-extension
  #      only — a pure-core install never serves them because the models/
  #      controllers behind them don't exist in core.
  #
  # Doc: docs/operations/reverse-proxy.md §7-8 (approved 2026-07-06, campaign
  # 019f3458 increment 8).
  class IngressConfigWriter
    class WriteError < StandardError; end

    SYSTEM_PREFIX = "/etc/traefik"

    # The four generic, extension-agnostic routers every core-mode install
    # needs. Same [name suffix, path prefix, logical service] shape as the
    # system extension's (now much larger) ROUTER_SPECS, intentionally NOT
    # shared code — the extension's full 10-router list stays the single
    # source of truth for extension-mode output (see `extension_writer`),
    # so there is no risk of the two lists drifting apart mid-composition.
    BASELINE_ROUTER_SPECS = [
      [ "api",      "/api",   "powernode-backend"  ],
      [ "agent",    "/agent", "powernode-backend"  ],
      [ "cable",    "/cable", "powernode-backend"  ],
      [ "frontend", nil,      "powernode-frontend" ]
    ].freeze

    ENTRYPOINT = "websecure"

    BASELINE_CERT_FILENAME = "core-self-signed.crt"
    BASELINE_KEY_FILENAME  = "core-self-signed.key"

    class << self
      # ------------------------------------------------------------------
      # Static config + services — lifted from Acme::TraefikConfigWriter.
      # Zero System:: dependency; Acme::TraefikConfigWriter's methods of the
      # same name now delegate here.
      # ------------------------------------------------------------------

      def write_static_config!(dynamic_dir: nil, output_path: nil)
        dynamic_dir ||= default_dynamic_dir
        out = output_path || default_static_config_path
        FileUtils.mkdir_p(File.dirname(out))
        config = {
          "entryPoints" => {
            "web" => {
              "address" => ":80",
              "http" => {
                "redirections" => {
                  "entryPoint" => {
                    "to"        => "websecure",
                    "scheme"    => "https",
                    "permanent" => true
                  }
                }
              }
            },
            "websecure" => {
              "address" => ":443",
              "http"    => {
                "middlewares" => [ "pass-tls-client-cert@file" ]
              }
            }
          },
          "providers" => {
            "file" => {
              "directory" => dynamic_dir,
              "watch"     => true
            }
          },
          "log"       => { "level" => ENV["POWERNODE_TRAEFIK_LOG_LEVEL"].presence || "INFO" },
          "accessLog" => {},
          "api"       => { "dashboard" => false, "insecure" => false }
        }
        File.write(out, YAML.dump(config))
        out
      end

      def default_static_config_path
        return ENV["POWERNODE_TRAEFIK_STATIC_CONFIG"] if ENV["POWERNODE_TRAEFIK_STATIC_CONFIG"].present?

        File.join(File.dirname(default_dynamic_dir), "traefik.yaml")
      end

      def default_dynamic_dir
        return ENV["POWERNODE_TRAEFIK_DYNAMIC_DIR"] if ENV["POWERNODE_TRAEFIK_DYNAMIC_DIR"].present?
        return "#{SYSTEM_PREFIX}/dynamic" if can_use_system_prefix?

        rails_fallback_dir("dynamic")
      end

      def default_cert_dir
        return ENV["POWERNODE_TRAEFIK_CERT_DIR"] if ENV["POWERNODE_TRAEFIK_CERT_DIR"].present?
        return "#{SYSTEM_PREFIX}/certs" if can_use_system_prefix?

        rails_fallback_dir("certs")
      end

      def default_ca_dir
        return ENV["POWERNODE_TRAEFIK_CA_DIR"] if ENV["POWERNODE_TRAEFIK_CA_DIR"].present?
        return "#{SYSTEM_PREFIX}/ca" if can_use_system_prefix?

        rails_fallback_dir("ca")
      end

      def backend_url
        ENV["POWERNODE_PROXY_BACKEND_URL"].presence || "http://127.0.0.1:3000"
      end

      def frontend_url
        ENV["POWERNODE_PROXY_FRONTEND_URL"].presence || "http://127.0.0.1:3001"
      end

      def worker_web_url
        ENV["POWERNODE_PROXY_WORKER_WEB_URL"].presence || "http://127.0.0.1:4567"
      end

      def extra_hosts
        from_env = ENV["POWERNODE_PROXY_EXTRA_HOSTS"].to_s.split(",")
        (from_env + trusted_proxy_hosts).map(&:strip).reject(&:empty?).uniq
      end

      def trusted_proxy_hosts
        return [] unless defined?(::AdminSetting)

        cfg = ::AdminSetting.reverse_proxy_url_config
        return [] unless cfg.is_a?(Hash)

        hosts = Array(cfg[:trusted_hosts]) | Array(cfg["trusted_hosts"])
        hosts.filter_map do |raw|
          h = raw.to_s.strip
          next if h.empty? || h.include?("*")
          h = h.sub(/:\d+\z/, "") if h.count(":") <= 1
          next if h.empty? || %w[localhost 127.0.0.1 ::1].include?(h)

          h
        end.uniq
      rescue StandardError
        []
      end

      def host_rule_for(primary_host, extra_hosts: nil)
        extras = extra_hosts || self.extra_hosts
        hosts = [ primary_host ] + extras
        return "Host(`#{primary_host}`)" if hosts.size == 1

        formatted = hosts.map { |h| "Host(`#{h}`)" }.join(" || ")
        "(#{formatted})"
      end

      # Deterministic, human-readable Traefik router name prefix for a host.
      # Same collapsing rule as Acme::TraefikConfigWriter.router_slug_for
      # (kept as an independent copy, not a delegation, since it's a trivial
      # string transform with no shared state to drift).
      def router_slug_for(host)
        host.to_s.gsub(/[^a-zA-Z0-9]+/, "-").gsub(/(^-|-$)/, "")
      end

      def render_services
        {
          "powernode-backend" => {
            "loadBalancer" => {
              "servers" => [ { "url" => backend_url } ],
              "passHostHeader" => true
            }
          },
          "powernode-frontend" => {
            "loadBalancer" => {
              "servers" => [ { "url" => frontend_url } ],
              "passHostHeader" => true
            }
          },
          "powernode-worker-web" => {
            "loadBalancer" => {
              "servers" => [ { "url" => worker_web_url } ],
              "passHostHeader" => true
            }
          }
        }
      end

      # ------------------------------------------------------------------
      # Provider seam
      # ------------------------------------------------------------------

      # Writes the per-account dynamic YAML. Delegates the ENTIRE write to
      # the registered extension writer when the seam is fully present;
      # otherwise renders the core baseline (self-signed cert + 4 generic
      # routers). Same filename convention either way ("acme-<id>.yaml") so
      # the dynamic directory's file listing doesn't depend on which mode
      # produced it — Traefik's file provider just watches the directory.
      def write!(account:, dynamic_dir: nil, cert_dir: nil)
        dynamic_dir ||= default_dynamic_dir
        cert_dir    ||= default_cert_dir

        writer = extension_writer
        return writer.write!(account: account, dynamic_dir: dynamic_dir, cert_dir: cert_dir) if writer

        new(account: account, dynamic_dir: dynamic_dir, cert_dir: cert_dir).write!
      end

      # Bootstrap step for the shared mTLS dynamic config (CA + _mtls.yaml),
      # required ONLY in extension mode (baseline routers set no tls.options,
      # so no mtls file is ever referenced in core mode). No-ops in core mode.
      def bootstrap_shared_dynamic!(ca_dir: nil, dynamic_dir: nil)
        writer = extension_writer
        return unless writer

        writer.write_internal_ca!(ca_dir: ca_dir) if writer.respond_to?(:write_internal_ca!)
        return unless writer.respond_to?(:write_mtls_shared_dynamic!)

        writer.write_mtls_shared_dynamic!(dynamic_dir: dynamic_dir, ca_dir: ca_dir)
      end

      # The registered writer, only when BOTH facets of the seam are
      # registered BY THE SAME OBJECT. A provider registering only one facet
      # isn't a supported topology — there is no safe way to compose
      # "someone else's certs" with "someone else's routers" — so that
      # combination falls through to the baseline rather than guessing.
      def extension_writer
        certs_provider   = ::Powernode::ExtensionRegistry.provider(:ingress_certs)
        routers_provider = ::Powernode::ExtensionRegistry.provider(:ingress_routers)
        return nil unless certs_provider && routers_provider
        return nil unless certs_provider == routers_provider

        certs_provider
      end

      # ------------------------------------------------------------------
      # Baseline self-signed cert (core mode only)
      # ------------------------------------------------------------------

      def baseline_cert_file_path(cert_dir: nil)
        File.join(cert_dir || default_cert_dir, BASELINE_CERT_FILENAME)
      end

      def baseline_key_file_path(cert_dir: nil)
        File.join(cert_dir || default_cert_dir, BASELINE_KEY_FILENAME)
      end

      # The host the baseline self-signed cert is issued for. Operator-set
      # via POWERNODE_INGRESS_HOST (e.g. a LAN hostname); falls back to the
      # machine's hostname, then "localhost".
      def baseline_host
        ENV["POWERNODE_INGRESS_HOST"].presence || Socket.gethostname.presence || "localhost"
      end

      # Idempotent: reuses an existing structurally-valid self-signed pair,
      # generating fresh material only on first boot (or after deletion).
      # Mirrors the established local-cert precedent in
      # System::InternalCaService::LocalCaAdapter (in-process OpenSSL
      # generation + on-disk persistence for infra TLS material when no
      # Vault-backed PKI is configured) — regenerating on every launcher
      # invocation would rotate the fingerprint on every restart.
      def ensure_baseline_cert!(cert_dir: nil)
        dir = cert_dir || default_cert_dir
        FileUtils.mkdir_p(dir)
        cert_path = baseline_cert_file_path(cert_dir: dir)
        key_path  = baseline_key_file_path(cert_dir: dir)
        return [ cert_path, key_path ] if reusable_pair?(cert_path, key_path)

        key, cert = generate_self_signed_pair(baseline_host)
        File.write(cert_path, cert.to_pem)
        File.write(key_path, key.to_pem, perm: 0o600)
        [ cert_path, key_path ]
      end

      private

      def can_use_system_prefix?
        File.directory?(SYSTEM_PREFIX) && File.writable?(SYSTEM_PREFIX)
      end

      def rails_fallback_dir(sub)
        if defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root
          env = (::Rails.respond_to?(:env) && ::Rails.env) ? ::Rails.env.to_s : "shared"
          ::Rails.root.join("tmp", "traefik", env, sub).to_s
        else
          File.join(Dir.tmpdir, "powernode-traefik", sub)
        end
      end

      def reusable_pair?(cert_path, key_path)
        return false unless File.file?(cert_path) && File.file?(key_path)

        cert_pem = File.read(cert_path)
        key_pem  = File.read(key_path)
        return false if cert_pem.blank? || key_pem.blank?

        OpenSSL::X509::Certificate.new(cert_pem)
        OpenSSL::PKey.read(key_pem)
        true
      rescue StandardError
        false
      end

      def generate_self_signed_pair(host)
        key = OpenSSL::PKey::RSA.new(2048)
        name = OpenSSL::X509::Name.parse("/CN=#{host}")
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = SecureRandom.random_number(2**63)
        cert.subject = name
        cert.issuer = name
        cert.public_key = key.public_key
        cert.not_before = Time.current
        cert.not_after  = Time.current + (825 * 24 * 3600) # ~825 days
        ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
        cert.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
        cert.add_extension(ef.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
        cert.add_extension(ef.create_extension("extendedKeyUsage", "serverAuth", false))
        cert.add_extension(ef.create_extension("subjectAltName", "DNS:#{host}", false))
        cert.sign(key, OpenSSL::Digest.new("SHA256"))
        [ key, cert ]
      end

      public
    end

    def initialize(account:, dynamic_dir:, cert_dir:)
      @account = account
      @dynamic_dir = dynamic_dir
      @cert_dir = cert_dir
    end

    # Baseline write: a single self-signed host cert + the 4 generic routers.
    # Always present (core mode has no "materialization" concept to gate on —
    # the baseline cert is generated up front), so the http section always
    # renders.
    def write!
      cert_path, key_path = self.class.ensure_baseline_cert!(cert_dir: @cert_dir)
      host = self.class.baseline_host

      hash = {
        "tls" => {
          "certificates" => [
            { "certFile" => cert_path, "keyFile" => key_path, "stores" => [ "default" ] }
          ]
        },
        "http" => {
          "routers"  => render_routers(host),
          "services" => self.class.render_services
        }
      }

      FileUtils.mkdir_p(@dynamic_dir)
      output_path = File.join(@dynamic_dir, "acme-#{@account.id}.yaml")
      File.write(output_path, YAML.dump(hash))

      { output_path: output_path, cert_count: 1 }
    rescue StandardError => e
      raise WriteError, "IngressConfigWriter failed: #{e.class}: #{e.message}"
    end

    private

    def render_routers(host)
      hosts_matcher = self.class.host_rule_for(host)
      slug = self.class.router_slug_for(host)
      BASELINE_ROUTER_SPECS.map do |suffix, path_prefix, service|
        rule = path_prefix.nil? ? hosts_matcher : "#{hosts_matcher} && PathPrefix(`#{path_prefix}`)"
        [ "#{slug}-#{suffix}", {
          "rule"        => rule,
          "service"     => service,
          "entryPoints" => [ ENTRYPOINT ]
        } ]
      end.to_h
    end
  end
end
