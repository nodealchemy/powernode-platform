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

    # Dedicated dynamic file for the host's OWN self-signed login ingress
    # (see `ensure_host_login_ingress!`). Distinct from the per-account
    # `acme-<id>.yaml` files so the two coexist in the watched directory: the
    # host login is the universal HTTPS front door, per-account ACME routers
    # are additive. The `00-` prefix is cosmetic (load order only).
    HOST_LOGIN_FILENAME = "00-host-login.yaml"

    # Path-prefixes routed to the Rails backend on the host login ingress;
    # every other path falls through to the frontend catch-all. `/sidekiq`
    # is routed separately to the worker-web upstream (the dashboard).
    HOST_LOGIN_BACKEND_PREFIXES = %w[/api /up /cable /agent /rails/health].freeze

    # Default location the on-host powernode-agent writes this node's enrolled
    # mTLS material to (matches the worker's WorkerCertManager default). The
    # `ca-chain.crt` here is the internal CA that signed the worker's client
    # cert; the host-login ingress verifies worker client certs against it so a
    # co-located Sidekiq worker can authenticate its backend calls. A
    # filesystem seam only — no extension code dependency. Overridable via
    # WORKER_PKI_DIR (same env the worker reads).
    AGENT_PKI_DIR_DEFAULT = "/persist/var/lib/powernode/pki"

    # Name of the Traefik middleware that forwards the verified client-cert CN
    # (X-Forwarded-Tls-Client-Cert-Info). Defined in the host-login dynamic
    # config and referenced by the backend routers when worker mTLS is on.
    PASS_TLS_CLIENT_CERT_MW = "pass-tls-client-cert"

    # Name of the Traefik middleware that DELETES any client-supplied
    # X-Forwarded-Tls-Client-Cert[-Info] header before a backend router sees it.
    # Applied (first) on EVERY backend router, unconditionally.
    #
    # Why unconditional: Traefik's passTLSClientCert only *overwrites* those
    # headers when a client cert was actually negotiated — v3.7.1 calls
    # req.Header.Set() solely inside `len(req.TLS.PeerCertificates) > 0`, and
    # never req.Header.Del(). clientAuth here is OPTIONAL
    # (VerifyClientCertIfGiven), so a cert-less caller's forged CN header would
    # otherwise pass through untouched and Security::MtlsTrust#verify_request
    # would trust it on the no-PEM path (imp 019f71e3-2a9c). The strip runs
    # BEFORE PASS_TLS_CLIENT_CERT_MW so only a proxy-authenticated (handshake-
    # verified) CN can reach the backend.
    STRIP_FORWARDED_CLIENT_CERT_MW = "strip-forwarded-client-cert"

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

      # ------------------------------------------------------------------
      # Host login ingress (universal — core AND extension mode)
      # ------------------------------------------------------------------

      # Writes the host's OWN self-signed login ingress: a self-signed serving
      # cert + host-agnostic, TLS-terminating routers, so the operator can
      # ALWAYS reach the control-plane UI + API over HTTPS — independent of any
      # ACME certificate.
      #
      # Why this exists separately from `write!`: in extension mode `write!`
      # delegates entirely to the registered ACME writer, which emits routers
      # ONLY for a valid System::AcmeCertificate. A hub that has not issued a
      # cert for its own hostname would therefore have NO login ingress at all.
      # This method NEVER consults the extension seam — it is the guaranteed
      # front door every self-hosted install gets. Per-account ACME routers
      # (added when an operator later exposes a service) are ADDITIVE: Traefik
      # merges the separate dynamic files, and the `host-login-*` router names
      # here never collide with the ACME writer's `<slug>-*` names.
      #
      # Host-agnostic (PathPrefix rules, no Host() match) so the appliance is
      # reachable at ANY name/IP it is served on — external hostname, SDWAN
      # overlay name, LAN IP, or localhost — with zero per-host config. That is
      # what makes it work for ops-hub.ipnode.us and every future hub the same.
      #
      # Idempotent: reuses an existing self-signed cert (no fingerprint churn
      # across reboots — important when `cert_dir` is durable storage) and
      # rewrites the dynamic YAML deterministically.
      def ensure_host_login_ingress!(dynamic_dir: nil, cert_dir: nil)
        dyn = dynamic_dir || default_dynamic_dir
        crt = cert_dir || default_cert_dir
        cert_path, key_path = ensure_baseline_cert!(cert_dir: crt)
        client_auth_ca = prepare_client_auth_ca(cert_dir: crt)
        FileUtils.mkdir_p(dyn)
        output_path = File.join(dyn, HOST_LOGIN_FILENAME)
        File.write(output_path, YAML.dump(host_login_config(cert_path, key_path, client_auth_ca: client_auth_ca)))
        # This file is NON-SECRET (router defs + cert PATHS, no keys) and MUST be
        # readable by the unprivileged traefik user. chmod explicitly (NOT
        # File.write(perm:), which is masked by the process umask) so a stray
        # restrictive umask can never leave it 0600 → unreadable by traefik → 404.
        File.chmod(0o644, output_path)
        mirrored = mirror_host_login_durably(output_path, cert_dir: crt)
        { output_path: output_path, cert_file: cert_path, key_file: key_path,
          client_auth_ca: client_auth_ca, durable_path: mirrored }
      end

      # Copy the rendered host-login config next to the certs it references, so
      # the reverse proxy can restore it BEFORE this app exists on the next boot.
      #
      # Why: `dynamic_dir` is /etc/traefik/dynamic, which on a module-composed
      # node is an overlay whose upper layer is tmpfs — it is empty at every
      # boot. This file can only be regenerated once Rails is up, measured at
      # ~2 minutes on ops-hub, and until it lands Traefik has no clientAuth and
      # therefore never asks for a client certificate. Every agent handshake in
      # that window produces a certless connection (see the 401 incident and
      # transport.Client.Do). Everything this YAML *references* is already
      # durable — the baseline cert/key and the internal CA all live in
      # `cert_dir` — so the config was the only volatile part.
      #
      # Best-effort by construction: a node with no durable cert_dir (no
      # /persist) simply has nothing to mirror, and the proxy-side restore is
      # itself guarded on every referenced path existing. Never raises — failing
      # to pre-seed the NEXT boot must not break ingress on THIS one.
      def mirror_host_login_durably(output_path, cert_dir:)
        durable_dir = durable_dynamic_dir_for(cert_dir)
        return nil unless durable_dir

        FileUtils.mkdir_p(durable_dir)
        target = File.join(durable_dir, HOST_LOGIN_FILENAME)
        tmp = "#{target}.tmp-#{Process.pid}"
        FileUtils.cp(output_path, tmp)
        File.chmod(0o644, tmp)
        File.rename(tmp, target) # atomic: the proxy may read this concurrently
        target
      rescue StandardError => e
        Rails.logger.warn("[IngressConfigWriter] durable mirror skipped: #{e.class}: #{e.message}") if defined?(Rails)
        begin
          File.delete(tmp) if tmp && File.exist?(tmp)
        rescue StandardError
          nil
        end
        nil
      end

      # Sibling of the cert dir: <root>/certs -> <root>/dynamic. Derived rather
      # than hardcoded because cert_dir is operator-configurable
      # (POWERNODE_TRAEFIK_CERT_DIR, and rails-start.sh picks /persist/... or
      # /var/lib/... depending on whether /persist is a mountpoint).
      def durable_dynamic_dir_for(cert_dir)
        return nil if cert_dir.to_s.strip.empty?

        parent = File.dirname(File.expand_path(cert_dir))
        return nil if parent == "/" || parent.empty?

        File.join(parent, "dynamic")
      end

      # The dynamic-config hash `ensure_host_login_ingress!` renders. Public so
      # tests can assert the shape without filesystem side effects.
      #
      # `client_auth_ca` (a traefik-readable internal-CA path, or nil) toggles
      # worker mTLS: when present the default TLS store requests+verifies client
      # certs against it (VerifyClientCertIfGiven, so cert-less browser login
      # still works) and the pass-tls-client-cert middleware — applied at the
      # ROUTER level on the backend routers below — forwards the verified leaf
      # cert AND its CN to the backend (the /api router covers
      # /api/v1/internal + /api/v1/system/*).
      # Applied per-router, NOT relied on at the websecure entrypoint:
      # write_static_config! emits that entrypoint reference, but a composed hub
      # node's traefik static config (from the reverse-proxy module) does NOT, so
      # relying on it silently drops the CN and every worker call 401s.
      #
      # Independent of `client_auth_ca`, the backend routers ALWAYS carry the
      # strip middleware that deletes any inbound forwarded-client-cert header,
      # so a forged CN can never reach MtlsTrust#verify_request's no-PEM path
      # (imp 019f71e3-2a9c). When no CA is present the backend simply receives no
      # CN and worker auth fails closed — the correct posture with no verifiable CA.
      def host_login_config(cert_path, key_path, client_auth_ca: nil)
        # Backend routers ALWAYS strip any client-supplied forwarded-client-cert
        # header first (STRIP_FORWARDED_CLIENT_CERT_MW), so a cert-less caller
        # can't forge the CN that MtlsTrust#verify_request trusts. pass-tls
        # (which only re-adds the CN when a real cert was negotiated) is layered
        # AFTER the strip, and only when clientAuth is active (a CA is present).
        backend_mw = [ STRIP_FORWARDED_CLIENT_CERT_MW ]
        backend_mw << PASS_TLS_CLIENT_CERT_MW if client_auth_ca
        routers = {}
        HOST_LOGIN_BACKEND_PREFIXES.each do |prefix|
          routers["host-login-#{router_slug_for(prefix)}"] =
            host_login_router("PathPrefix(`#{prefix}`)", "powernode-backend", middlewares: backend_mw)
        end
        routers["host-login-sidekiq"]  = host_login_router("PathPrefix(`/sidekiq`)", "powernode-worker-web")
        routers["host-login-frontend"] = host_login_router("PathPrefix(`/`)", "powernode-frontend")
        tls = { "certificates" => [ { "certFile" => cert_path, "keyFile" => key_path, "stores" => [ "default" ] } ] }
        if client_auth_ca
          tls["options"] = {
            "default" => {
              "clientAuth" => {
                "caFiles"        => [ client_auth_ca ],
                "clientAuthType" => "VerifyClientCertIfGiven"
              }
            }
          }
        end
        {
          "tls"  => tls,
          "http" => {
            "routers"     => routers,
            "services"    => render_services,
            "middlewares" => strip_forwarded_client_cert_middleware.merge(
              # The CN-forwarding middleware, referenced by the backend routers
              # above (when worker mTLS is on) and by the websecure entrypoint that
              # write_static_config! emits. It only *sets* the CN when a client
              # cert is negotiated (never strips a forged one — hence the strip
              # middleware above), so it is always safe to define.
              pass_tls_client_cert_middleware
            )
          }
        }
      end

      # The strip middleware, as a one-entry `http.middlewares` fragment.
      #
      # DELETES any client-supplied forwarded-client-cert header at the trust
      # boundary: an empty customRequestHeaders value makes Traefik's headers
      # middleware call req.Header.Del(name) unconditionally (v3.7.1). Strips
      # exactly the two headers MtlsTrust consumes so only Traefik-populated,
      # handshake-verified values reach the backend.
      #
      # Emitted by BOTH dynamic files core writes — the host-login file AND the
      # per-account baseline file — because each must stand alone, not because
      # they coexist. They do NOT: `ensure_host_login_ingress!` has exactly one
      # caller (the system extension's rails-start.sh), and in extension mode the
      # per-account file comes from the extension's writer, not from the baseline
      # below. So each file is written in a mode where the other is absent, and a
      # cross-file reference would leave its routers referencing an undefined
      # middleware. Both definitions come from THIS method, so if some future
      # topology does put them in one directory they are byte-identical and
      # Traefik's skip-duplicates merge is a no-op either way.
      def strip_forwarded_client_cert_middleware
        {
          STRIP_FORWARDED_CLIENT_CERT_MW => {
            "headers" => {
              "customRequestHeaders" => {
                ::Security::MtlsTrust::PEM_HEADER     => "",
                ::Security::MtlsTrust::SUBJECT_HEADER => ""
              }
            }
          }
        }
      end

      # The client-cert-forwarding middleware, as a one-entry `http.middlewares`
      # fragment. Emitted by every dynamic file whose routers reference it, for
      # the same stand-alone reason as the strip above.
      #
      # `pem: true` forwards the FULL verified leaf certificate on
      # X-Forwarded-Tls-Client-Cert, which is what gives the Rails layer a
      # cryptographic second factor. Without it Traefik populates only the
      # `info` header (the subject CN), so Security::MtlsTrust#verify_request
      # always fell through to its no-PEM branch and TRUSTED that CN — the
      # ingress chain-check was the sole gate — and `require_pem: true`, the
      # posture credential-revealing endpoints ask for, could never be satisfied
      # because the header it demands was never emitted (imp 01a028ab-f39b).
      #
      # `info.subject.commonName` STAYS on: FederationApi::BaseController
      # resolves the calling peer from that header before its per-peer signature
      # check, and verify_request's no-PEM fallback still serves routes fronted
      # by an ingress core did not write.
      #
      # Wire format (Traefik v3.7.1 pkg/middlewares/passtlsclientcert): the PEM
      # is sanitized — BEGIN/END lines and all newlines deleted — then
      # url-escaped, i.e. percent-escaped bare base64. MtlsTrust#reconstruct_pem
      # rewraps exactly that; spec/services/security/mtls_trust_spec.rb pins the
      # shape so this switch can't silently start emitting something the backend
      # cannot parse. Size: ~1-2 KB per cert before escaping, ~3 KB after, well
      # under Puma's 112 KiB Puma::Const::MAX_HEADER budget for the whole block.
      def pass_tls_client_cert_middleware
        {
          PASS_TLS_CLIENT_CERT_MW => {
            "passTLSClientCert" => {
              "pem"  => true,
              "info" => { "subject" => { "commonName" => true } }
            }
          }
        }
      end

      private

      # A single host-login router. tls:{} makes it an HTTPS router (served
      # over :443 with the default cert store); without it the router is
      # HTTP-only and 404s HTTPS requests on a bare TLS entrypoint.
      def host_login_router(rule, service, middlewares: nil)
        router = { "rule" => rule, "service" => service, "entryPoints" => [ ENTRYPOINT ], "tls" => {} }
        # Fresh array + fresh strings per router: a shared object would make
        # YAML.dump emit anchors/aliases across the routers (valid, but ugly and
        # not all parsers enable alias resolution).
        router["middlewares"] = middlewares.map(&:dup) if middlewares.present?
        router
      end

      # Composes the client-auth trust bundle written next to the serving cert
      # (internal-ca.crt) and returned as the host-login TLS clientAuth caFile.
      #
      # DUAL-TRUST — the bundle unions every CA a legitimate client cert may
      # chain to:
      #   (a) the enrolled agent CA chain (<pki>/ca-chain.crt) — the CA THIS
      #       node enrolled against. Keeps a control-plane / worker whose certs
      #       chain to it validating (unchanged from before).
      #   (b) this node's OWN local internal-CA root
      #       (POWERNODE_CA_LOCAL_DIR/root.crt), when it runs one — so certs
      #       this node's InternalCaService signs for the nodes IT enrolls also
      #       pass clientAuth. A Vault-less hub signs with its own local CA yet
      #       still holds a chain-(a) cert from its bootstrap enrollment;
      #       trusting both keeps existing mTLS working while admitting the
      #       hub's own issued nodes.
      #
      # Sourced by path convention (POWERNODE_CA_LOCAL_DIR mirrors how the agent
      # chain is read from WORKER_PKI_DIR) so core stays decoupled from the
      # system extension's InternalCaService. Returns nil only when NEITHER
      # source is present (pure core mode) — the ingress then omits clientAuth,
      # unchanged. Deterministic + deduped so the bundle is byte-stable across
      # reboots (no fingerprint churn when cert_dir is durable). Best-effort:
      # any failure degrades to whatever it could read (or nil).
      def prepare_client_auth_ca(cert_dir:)
        blocks = client_auth_ca_sources.filter_map { |path| read_ca_source(path) }

        certs = dedup_ca_pem_blocks(blocks)
        return nil if certs.empty?

        FileUtils.mkdir_p(cert_dir)
        dest = File.join(cert_dir, "internal-ca.crt")
        File.write(dest, certs.join)
        dest
      rescue StandardError => e
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger.warn("[IngressConfigWriter] client-auth CA prep skipped: #{e.class}: #{e.message}")
        end
        nil
      end

      # Reads one CA source, returning its PEM (or nil for a missing path / a
      # file with no cert). Best-effort PER SOURCE: an existing-but-unreadable
      # source (transient FS error, a perms glitch) is skipped so the bundle
      # degrades to the sources it COULD read — NOT nil'd wholesale. Nil'ing the
      # whole bundle would drop clientAuth entirely and FAIL-OPEN the mTLS gate;
      # dropping just the unreadable source keeps the gate up on whatever
      # remains (e.g. the enrolled agent chain when only the local root glitches).
      def read_ca_source(path)
        return nil unless File.file?(path)

        pem = File.read(path)
        return nil unless pem.include?("BEGIN CERTIFICATE")

        pem
      rescue StandardError => e
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger.warn("[IngressConfigWriter] client-auth CA source skipped (#{path}): #{e.class}: #{e.message}")
        end
        nil
      end

      # Ordered CA sources unioned into the client-auth trust bundle:
      #   1. the enrolled agent chain (WORKER_PKI_DIR / AGENT_PKI_DIR_DEFAULT)
      #   2. this node's own local internal-CA root, when POWERNODE_CA_LOCAL_DIR
      #      is set (the same var that anchors LocalCaAdapter's persisted root)
      # Both are path conventions; the caller skips paths that don't exist.
      def client_auth_ca_sources
        sources = [ File.join(ENV["WORKER_PKI_DIR"].presence || AGENT_PKI_DIR_DEFAULT, "ca-chain.crt") ]
        if (local_dir = ENV["POWERNODE_CA_LOCAL_DIR"].presence)
          sources << File.join(local_dir, "root.crt")
        end
        sources
      end

      # Split concatenated PEM blobs into individual certificate blocks and drop
      # duplicates by SHA-256(DER), preserving first-seen order. Prevents a
      # doubled cert when sources overlap and keeps the emitted bundle stable.
      # An unparseable block is skipped rather than aborting the whole bundle.
      def dedup_ca_pem_blocks(blobs)
        seen = {}
        blobs.each_with_object([]) do |blob, out|
          blob.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).each do |block|
            normalized = block.end_with?("\n") ? block : "#{block}\n"
            begin
              fingerprint = OpenSSL::Digest::SHA256.hexdigest(OpenSSL::X509::Certificate.new(normalized).to_der)
            rescue OpenSSL::X509::CertificateError
              next
            end
            next if seen[fingerprint]

            seen[fingerprint] = true
            out << normalized
          end
        end
      end

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
          "routers"     => render_routers(host),
          "services"    => self.class.render_services,
          # Self-contained: the backend routers above reference BOTH middlewares,
          # so this file defines both. It must not lean on the host-login file —
          # in core mode nothing writes that file at all (its only caller is the
          # system extension's rails-start.sh), so a cross-file reference here
          # would leave every backend router in error, and the
          # pass-tls-client-cert@file reference write_static_config! puts on the
          # websecure entrypoint would have nothing to resolve either.
          "middlewares" => self.class.strip_forwarded_client_cert_middleware
                                     .merge(self.class.pass_tls_client_cert_middleware)
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
        router = {
          "rule"        => rule,
          "service"     => service,
          "entryPoints" => [ ENTRYPOINT ],
          # tls:{} makes this an HTTPS router — REQUIRED so Traefik serves it
          # over the :443 (TLS) entrypoint using the default cert store. A
          # router with no tls section is HTTP-only and 404s every HTTPS
          # request on a bare TLS entrypoint (imp 019f6c3d-aab2).
          "tls"         => {}
        }
        # Every router that reaches the Rails backend strips a client-supplied
        # forwarded-client-cert header, for the same reason the host-login
        # backend routers do: MtlsTrust#verify_request's no-PEM branch trusts
        # the forwarded CN, so an un-stripped router lets a cert-less caller
        # authenticate as any worker whose CN it can guess. These routers match
        # `Host(...) && PathPrefix(...)`, a LONGER rule than the host-login
        # `PathPrefix(...)` routers, so they win on Traefik's rule-length
        # priority — they cannot inherit the host-login strip.
        #
        # pass-tls MUST follow the strip, exactly as on the host-login backend
        # routers. Traefik PREPENDS an entrypoint's middlewares to the router's
        # own chain, and write_static_config! puts pass-tls-client-cert@file on
        # `websecure`. A strip-only router therefore runs
        # `pass-tls (sets CN) → strip (deletes it)` and the backend sees NO CN
        # at all — worker mTLS auth would lose its identity outright, which is
        # worse than the forgery this strip exists to prevent.
        if service == "powernode-backend"
          router["middlewares"] = [ STRIP_FORWARDED_CLIENT_CERT_MW.dup, PASS_TLS_CLIENT_CERT_MW.dup ]
        end
        [ "#{slug}-#{suffix}", router ]
      end.to_h
    end
  end
end
