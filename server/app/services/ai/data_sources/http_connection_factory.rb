# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "uri"
require "openssl"
require "tempfile"
require "digest"
require "faraday/follow_redirects"

module Ai
  module DataSources
    # SSRF-guarded Faraday connection factory for outbound data-source requests.
    #
    # Builds a Faraday::Connection with:
    #   - bounded open/read timeouts
    #   - a hard cap on response body size (raises if exceeded)
    #   - transparent gzip/deflate handling
    #   - a contactable User-Agent: "Powernode/<ver> (+<contact>; agent:<slug>)"
    #   - SSRF protection: every request URL is resolved and pinned, and any
    #     resolved IP in a private / loopback / link-local / unique-local CIDR
    #     (IPv4 and IPv6) is REJECTED. Redirects are re-validated on each hop so
    #     a public host cannot 30x-bounce into the internal network.
    #
    # OWASP coverage:
    #   ASI08 - Excessive Agency (egress control on agent-initiated fetches)
    #   A10:2021 - Server-Side Request Forgery (SSRF)
    class HttpConnectionFactory
      # Raised when a URL (or a redirect target) resolves to a disallowed
      # address, fails to resolve, or uses a disallowed scheme.
      class SsrfError < StandardError; end

      # Raised when a response body exceeds MAX_RESPONSE_BYTES.
      class ResponseTooLargeError < StandardError; end

      # Raised when configuration["mtls"] declares "required": true but the
      # client certificate / private key could not be loaded from Vault. The
      # message is deliberately non-secret (no path, no key, no cert) — it only
      # signals that a hard requirement was unmet. QueryService's rescue turns
      # this into an error envelope rather than letting a misconfigured-but-
      # required source fall back to an unauthenticated TLS attempt.
      class MtlsConfigError < StandardError; end

      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 20
      DEFAULT_MAX_REDIRECTS = 5

      # Hard ceiling on a single response body (10 MiB). Endpoints can lower
      # this via data_source.configuration["max_response_bytes"] but never raise it.
      MAX_RESPONSE_BYTES = 10 * 1024 * 1024

      ALLOWED_SCHEMES = %w[http https].freeze

      # Serializes writes to the @ca_tempfiles memo (mTLS CA tempfiles). Load-time
      # constant so the mutex itself is created exactly once (no ||= init race).
      CA_TEMPFILE_MUTEX = Mutex.new

      # Private / reserved / loopback / link-local / unique-local ranges that an
      # outbound data-source fetch must never reach. Covers IPv4 + IPv6,
      # including IPv4-mapped IPv6 (::ffff:0:0/96) and 6to4/Teredo prefixes.
      BLOCKED_CIDRS = [
        # --- IPv4 ---
        "0.0.0.0/8",        # "this" network
        "10.0.0.0/8",       # RFC1918 private
        "100.64.0.0/10",    # RFC6598 CGNAT
        "127.0.0.0/8",      # loopback
        "169.254.0.0/16",   # link-local
        "172.16.0.0/12",    # RFC1918 private
        "192.0.0.0/24",     # IETF protocol assignments
        "192.0.2.0/24",     # TEST-NET-1
        "192.168.0.0/16",   # RFC1918 private
        "198.18.0.0/15",    # benchmarking
        "198.51.100.0/24",  # TEST-NET-2
        "203.0.113.0/24",   # TEST-NET-3
        "224.0.0.0/4",      # multicast
        "240.0.0.0/4",      # reserved
        "255.255.255.255/32", # broadcast
        # --- IPv6 ---
        "::/128",           # unspecified
        "::1/128",          # loopback
        "::ffff:0:0/96",    # IPv4-mapped IPv6
        "64:ff9b::/96",     # NAT64 well-known
        "100::/64",         # discard-only
        "2001:10::/28",     # ORCHID
        "2001:20::/28",     # ORCHIDv2
        "2001:db8::/32",    # documentation
        "2002::/16",        # 6to4
        "fc00::/7",         # unique-local (ULA)
        "fe80::/10",        # link-local
        "ff00::/8"          # multicast
      ].map { |cidr| IPAddr.new(cidr) }.freeze

      class << self
        # Build an SSRF-guarded Faraday connection for a data source.
        #
        # @param data_source [Ai::DataSource]
        # @param agent [Ai::Agent, nil] originating agent (for User-Agent attribution)
        # @return [Faraday::Connection]
        def build(data_source:, agent: nil, max_redirects: nil)
          config = data_source.respond_to?(:configuration) ? (data_source.configuration || {}) : {}

          open_timeout = positive_int(config["open_timeout_seconds"], DEFAULT_OPEN_TIMEOUT)
          read_timeout = positive_int(config["read_timeout_seconds"], DEFAULT_READ_TIMEOUT)
          # A caller MAY force a redirect limit (a credential broker passes 0 so a
          # token endpoint is never followed cross-host with a secret in the body).
          # nil => fall back to the per-source config (DEFAULT_MAX_REDIRECTS), so the
          # default path is byte-for-byte unchanged.
          max_redirects = if max_redirects.nil?
                            positive_int(config["max_redirects"], DEFAULT_MAX_REDIRECTS)
                          else
                            [max_redirects.to_i, 0].max
                          end
          max_bytes = response_size_cap(config["max_response_bytes"])

          base_url = data_source.respond_to?(:api_base_url) ? data_source.api_base_url : nil

          # Outbound mTLS client-cert (Phase 4b-2b). OFF by default: when no
          # configuration["mtls"] block is present (or it is disabled), this
          # returns {} and the Faraday options below carry NO ssl: key, so the
          # connection is byte-for-byte identical to the pre-mTLS build. When
          # enabled, the hash holds OpenSSL::X509::Certificate + OpenSSL::PKey
          # objects loaded from Vault (never the raw PEM strings from config).
          ssl_options = client_ssl_options(data_source)

          faraday_options = { url: base_url.presence }
          faraday_options[:ssl] = ssl_options if ssl_options.present?

          Faraday.new(**faraday_options) do |conn|
            # Pin every outbound request URL before it leaves the process.
            conn.use Ai::DataSources::HttpConnectionFactory::SsrfGuardMiddleware

            # Transparent gzip/deflate. When faraday-gzip is bundled we use its
            # middleware (advertises Accept-Encoding + inflates the body). When
            # it is absent we deliberately leave Accept-Encoding UNSET so the
            # net_http adapter applies its built-in transparent gzip handling
            # (Net::HTTP only auto-inflates when it set the header itself).
            conn.request :gzip if gzip_available?

            # Re-validate the target of every redirect hop. faraday-follow_redirects
            # invokes the callback with (old_env, new_request_env); new_request_env[:url]
            # holds the absolute redirect target, which we resolve-and-pin again.
            conn.response :follow_redirects,
                          limit: max_redirects,
                          callback: method(:validate_redirect!)

            # Enforce the response-size cap. Registered innermost (just above the
            # adapter) so its on_complete fires first against the materialized
            # response body; gzip middleware above it inflates before it returns
            # up the stack, and the Content-Length pre-check rejects oversized
            # declared bodies before allocation.
            conn.use Ai::DataSources::HttpConnectionFactory::ResponseSizeMiddleware, max_bytes: max_bytes

            conn.headers["User-Agent"] = user_agent(agent)

            conn.options.open_timeout = open_timeout
            conn.options.timeout = read_timeout

            conn.adapter Faraday.default_adapter
          end
        end

        # Resolve +url+'s host and raise SsrfError if any resolved address is in
        # a blocked CIDR, the scheme is disallowed, or DNS resolution fails.
        # This is the "resolve-and-pin" check; callers may invoke it directly
        # before issuing a request, and the middleware invokes it per hop.
        #
        # @param url [String, URI::Generic]
        # @return [true]
        def validate_url!(url)
          uri = url.is_a?(URI::Generic) ? url : URI.parse(url.to_s)

          unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
            raise SsrfError, "Disallowed URL scheme: #{uri.scheme.inspect}"
          end

          host = uri.host
          raise SsrfError, "URL is missing a host" if host.blank?

          addresses = resolve_host(host)
          raise SsrfError, "Host did not resolve to any address: #{host}" if addresses.empty?

          addresses.each do |addr|
            if blocked_address?(addr)
              # Do NOT echo the host into exceptions beyond what's needed; the
              # resolved IP is internal and must not be propagated downstream.
              raise SsrfError, "URL resolves to a disallowed (private/loopback/link-local) address"
            end
          end

          true
        rescue URI::InvalidURIError => e
          raise SsrfError, "Invalid URL: #{e.message}"
        rescue Resolv::ResolvError, SocketError => e
          raise SsrfError, "Could not resolve host: #{e.message}"
        end

        # Callback wired into faraday-follow_redirects. Re-validates the Location
        # target on every hop so a public host cannot redirect into the internal
        # network. Signature matches the gem's callback contract
        # (old_env, new_env) — we only need the new target.
        def validate_redirect!(_old_env, new_env)
          target = new_env[:url] || new_env["url"]
          validate_url!(target) if target
        end

        # Build the contactable User-Agent string.
        # Format: "Powernode/<ver> (+<contact>; agent:<slug>)"
        def user_agent(agent = nil)
          slug = agent.respond_to?(:slug) && agent.slug.present? ? agent.slug : "none"
          "Powernode/#{app_version} (+#{contact_uri}; agent:#{slug})"
        end

        # @return [Boolean] true if +ip+ falls in any blocked CIDR.
        def blocked_address?(ip)
          addr = ip.is_a?(IPAddr) ? ip : IPAddr.new(ip.to_s)
          # Normalize IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1) to its IPv4 form
          # so the IPv4 CIDRs also catch it.
          native = native_ipv4(addr)
          blocked = BLOCKED_CIDRS.any? { |cidr| cidr.include?(addr) }
          blocked ||= BLOCKED_CIDRS.any? { |cidr| cidr.include?(native) } if native
          blocked
        rescue IPAddr::Error
          # Unparseable address is treated as unsafe.
          true
        end

        private

        # Resolve a host to an array of IPAddr. If the host is already a literal
        # IP, return it directly (no DNS round-trip) — still subject to CIDR check.
        def resolve_host(host)
          literal = parse_literal_ip(host)
          return [literal] if literal

          resolved = []
          Resolv::DNS.open do |dns|
            dns.timeouts = 3
            resolved.concat(dns.getaddresses(host).map { |r| safe_ipaddr(r.to_s) }.compact)
          end
          # Fallback to the system resolver if DNS returned nothing (e.g. /etc/hosts).
          if resolved.empty?
            resolved.concat(
              Resolv.getaddresses(host).map { |a| safe_ipaddr(a) }.compact
            )
          end
          resolved.uniq(&:to_s)
        end

        def parse_literal_ip(host)
          stripped = host.to_s.delete_prefix("[").delete_suffix("]")
          IPAddr.new(stripped)
        rescue IPAddr::Error
          nil
        end

        def safe_ipaddr(str)
          IPAddr.new(str)
        rescue IPAddr::Error
          nil
        end

        # Extract the embedded IPv4 from an IPv4-mapped IPv6 address, else nil.
        def native_ipv4(addr)
          return nil unless addr.ipv6?
          return nil unless addr.ipv4_mapped? || IPAddr.new("::ffff:0:0/96").include?(addr)

          IPAddr.new(addr.to_i & 0xffffffff, Socket::AF_INET)
        rescue IPAddr::Error, NoMethodError
          nil
        end

        def positive_int(value, fallback)
          int = Integer(value, exception: false)
          int && int.positive? ? int : fallback
        end

        # Endpoints may lower the cap but never exceed MAX_RESPONSE_BYTES.
        def response_size_cap(value)
          requested = Integer(value, exception: false)
          return MAX_RESPONSE_BYTES unless requested&.positive?

          [requested, MAX_RESPONSE_BYTES].min
        end

        def app_version
          if Rails.application.config.respond_to?(:version) && Rails.application.config.version.present?
            Rails.application.config.version
          else
            "1.0.0"
          end
        end

        # Contact URI advertised in the User-Agent so remote operators can reach
        # us. Configurable via ENV; defaults to the public project page.
        def contact_uri
          ENV["POWERNODE_CONTACT_URI"].presence || "https://github.com/nodealchemy/powernode-platform"
        end

        def gzip_available?
          return @gzip_available unless @gzip_available.nil?

          @gzip_available =
            begin
              require "faraday/gzip"
              true
            rescue LoadError
              false
            end
        end

        # ----------------------------------------------------------------------
        # Outbound mTLS (Phase 4b-2b)
        #
        # CONFIG SHAPE (data_source.configuration["mtls"], a jsonb sub-hash;
        # string OR symbol keys tolerated). The cert/key are NEVER in the config
        # itself — only a Vault reference is:
        #
        #   "mtls" => {
        #     "enabled"     => true,            # off unless truthy
        #     "required"    => false,           # true => fail closed (raise) on load error
        #     "vault_path"  => "secret/data/…", # explicit Vault KV path (preferred)
        #     "credential_id" => "<uuid>",      # OR convention lookup by id
        #     "cert_key"    => "cert_pem",      # field name in the Vault secret (default cert_pem)
        #     "key_key"     => "key_pem",       # field name in the Vault secret (default key_pem)
        #     "ca_key"      => "ca_pem"         # optional CA chain field in the Vault secret
        #   }
        #
        # Returns the Faraday `ssl:` hash ({ client_cert:, client_key:[, ca_file:] })
        # or {} when mTLS is disabled / unconfigured / (optionally) failed to load.
        # ----------------------------------------------------------------------
        def client_ssl_options(data_source)
          mtls = mtls_config(data_source)
          return {} if mtls.blank?
          return {} unless truthy?(jget(mtls, "enabled"))

          required = truthy?(jget(mtls, "required"))

          material = load_mtls_material(data_source, mtls)
          if material.nil?
            # Vault returned nothing usable. Required => fail closed; optional =>
            # degrade to a normal (no client cert) TLS attempt.
            raise MtlsConfigError, "mTLS is required for this data source but no client certificate is configured" if required

            return {}
          end

          build_ssl_hash(material, mtls, required)
        rescue MtlsConfigError
          raise
        rescue StandardError => e
          # NEVER echo cert/key material or the underlying message (it may embed
          # PEM bytes or a Vault path). Log the exception CLASS only.
          Rails.logger.error("[DataSources::HttpConnectionFactory] mTLS setup failed: #{e.class}")
          raise MtlsConfigError, "mTLS is required for this data source but the client certificate could not be loaded" if truthy?(jget(mtls, "required"))

          {}
        end

        # Read the mtls sub-hash off configuration, tolerating string OR symbol
        # keys at the top level. Returns nil when absent/!Hash.
        def mtls_config(data_source)
          config = data_source.respond_to?(:configuration) ? (data_source.configuration || {}) : {}
          return nil unless config.is_a?(Hash)

          mtls = config["mtls"] || config[:mtls]
          mtls.is_a?(Hash) ? mtls : nil
        end

        # Fetch the cert/key (and optional CA) PEM strings from Vault. The PEM
        # bytes live ONLY in Vault — config carries a vault_path / credential_id
        # reference. Returns { cert:, key:, ca: } of PEM strings, or nil when the
        # secret is missing the mandatory cert/key fields.
        def load_mtls_material(data_source, mtls)
          secret = read_vault_secret(data_source, mtls)
          return nil unless secret.is_a?(Hash)

          secret = secret.with_indifferent_access if secret.respond_to?(:with_indifferent_access)

          cert_field = jget(mtls, "cert_key").presence || "cert_pem"
          key_field  = jget(mtls, "key_key").presence || "key_pem"
          ca_field   = jget(mtls, "ca_key").presence  || "ca_pem"

          cert_pem = secret[cert_field] || secret[cert_field.to_sym]
          key_pem  = secret[key_field]  || secret[key_field.to_sym]
          ca_pem   = secret[ca_field]   || secret[ca_field.to_sym]

          return nil if cert_pem.blank? || key_pem.blank?

          { cert: cert_pem, key: key_pem, ca: ca_pem }
        end

        # Resolve the Vault secret hash for the mTLS material. Prefers an explicit
        # vault_path (read directly); otherwise falls back to the data_source
        # credential convention (account scope + credential_id). Returns the raw
        # secret Hash or nil. Raises nothing of its own — Vault errors propagate
        # to client_ssl_options' rescue, which logs e.class only.
        def read_vault_secret(data_source, mtls)
          vault_path = jget(mtls, "vault_path", "path").presence
          # cache: false — a client PRIVATE KEY must NEVER be persisted to Rails.cache
          # (Redis / Solid Cache). It is read fresh from Vault per connection build
          # (mTLS is rare and the connection is short-lived), honoring the absolute
          # vault-only-storage rule for key material.
          return ::Security::VaultClient.read_secret(vault_path, cache: false) if vault_path

          account_id = data_source.respond_to?(:account_id) ? data_source.account_id : nil
          credential_id = jget(mtls, "credential_id", "credential_reference").presence
          return nil if account_id.blank? || credential_id.blank?

          provider = ::Security::VaultCredentialProvider.new(account_id: account_id)
          provider.get_credential(credential_type: :data_source, credential_id: credential_id)
        end

        # Construct the Faraday ssl: hash from loaded PEM material. The private
        # key is parsed into an OpenSSL::PKey but NEVER logged or stringified.
        # A CA, when supplied, is written to a per-process tempfile (Faraday's
        # ssl.ca_file wants a path) whose handle is retained for the process
        # lifetime so it is not GC-unlinked mid-request.
        def build_ssl_hash(material, mtls, required)
          ssl = {
            client_cert: OpenSSL::X509::Certificate.new(material[:cert]),
            client_key: OpenSSL::PKey.read(clean_pem_key(material[:key]))
          }

          ca_pem = material[:ca]
          ssl[:ca_file] = write_ca_tempfile(ca_pem) if ca_pem.present?
          ssl
        rescue OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError => e
          # Malformed PEM. Same fail-closed-vs-degrade contract, message non-secret.
          Rails.logger.error("[DataSources::HttpConnectionFactory] mTLS material is invalid: #{e.class}")
          raise MtlsConfigError, "mTLS is required for this data source but the client certificate is invalid" if required

          {}
        end

        # Strip non-PEM metadata lines (e.g. Docker Swarm "kek-version:" headers)
        # that some exporters prepend, so OpenSSL::PKey.read sees clean PEM.
        # Mirrors Devops::Docker::ApiClient#clean_pem_key.
        def clean_pem_key(key_pem)
          return key_pem if key_pem.blank?

          key_pem.lines.reject { |line| line.match?(/\A[a-z]+-[a-z]+:/i) || line.strip.empty? }.join
        end

        # Faraday's ssl.ca_file expects a filesystem path. Persist the CA PEM to a
        # tempfile and retain the handle (keyed by content digest, deduplicated)
        # so it survives GC for the life of connections that reference it.
        def write_ca_tempfile(ca_pem)
          digest = Digest::SHA256.hexdigest(ca_pem)
          # Guard the class-level memo against concurrent read-modify-write (multiple
          # threads building mTLS connections at once would otherwise leak duplicate
          # tempfiles). The mutex is a load-time constant, so it has no ||= init race.
          CA_TEMPFILE_MUTEX.synchronize do
            @ca_tempfiles ||= {}
            existing = @ca_tempfiles[digest]
            return existing.path if existing && File.exist?(existing.path)

            file = Tempfile.new(["data-source-mtls-ca", ".pem"])
            file.write(ca_pem)
            file.flush
            @ca_tempfiles[digest] = file
            file.path
          end
        end

        # Tolerant truthy read for jsonb booleans that may round-trip as strings
        # ("true"/"1") or native booleans.
        def truthy?(value)
          case value
          when true then true
          when String then %w[true 1 yes on].include?(value.strip.downcase)
          when Integer then value == 1
          else false
          end
        end

        # Tolerant jsonb scalar read: first present value among +keys+, checking
        # both String and Symbol spellings. Mirrors the data-source pipeline's
        # jsonb key tolerance.
        def jget(hash, *keys)
          return nil unless hash.is_a?(Hash)

          keys.each do |key|
            [key.to_s, key.to_sym].each do |variant|
              value = hash[variant]
              return value unless value.nil?
            end
          end
          nil
        end
      end

      # Faraday middleware: validates (resolve-and-pin) the request URL on the
      # way out, before the adapter opens a socket. This guards the INITIAL
      # request; redirects are handled by the follow_redirects callback.
      class SsrfGuardMiddleware < Faraday::Middleware
        def call(env)
          Ai::DataSources::HttpConnectionFactory.validate_url!(env.url)
          @app.call(env)
        end
      end

      # Faraday middleware: rejects responses whose body exceeds +max_bytes+.
      # Runs as an outer wrapper so it sees the fully-decoded (post-gzip) body.
      class ResponseSizeMiddleware < Faraday::Middleware
        def initialize(app, max_bytes:)
          super(app)
          @max_bytes = max_bytes
        end

        def call(env)
          @app.call(env).on_complete do |response_env|
            enforce!(response_env)
          end
        end

        private

        def enforce!(response_env)
          declared = response_env.response_headers&.[]("content-length")
          if declared && Integer(declared, exception: false).to_i > @max_bytes
            raise ResponseTooLargeError,
                  "Response Content-Length #{declared} exceeds cap of #{@max_bytes} bytes"
          end

          body = response_env.body
          return unless body.respond_to?(:bytesize)

          if body.bytesize > @max_bytes
            raise ResponseTooLargeError,
                  "Response body #{body.bytesize} exceeds cap of #{@max_bytes} bytes"
          end
        end
      end
    end
  end
end
