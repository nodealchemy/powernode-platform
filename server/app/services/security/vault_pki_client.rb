# frozen_string_literal: true

module Security
  # Thin facade over the Vault gem for PKI engine operations. Wraps the
  # raw HTTP API so callers (System::InternalCaService::VaultCaAdapter)
  # don't need to know the Vault gem's quirks (string vs symbol keys,
  # Vault::Secret vs Hash returns, etc.).
  #
  # Audit plan P1.4 introduces this wrapper so the adapter has a
  # narrow, testable interface that's easy to mock in specs.
  #
  # Authentication: if `vault_client` is supplied, uses it directly.
  # Otherwise constructs a fresh ::Vault::Client pointing at `address`
  # with `token` — this dev/test path bypasses the production
  # Security::VaultClient AppRole login so smoke tests against a dev
  # vault don't need AppRole bootstrap.
  class VaultPkiClient
    class PkiError < StandardError; end

    DEFAULT_MOUNT = "pki_int"
    DEFAULT_ROLE  = "node"

    attr_reader :mount, :role

    def initialize(mount: DEFAULT_MOUNT, role: DEFAULT_ROLE,
                   address: nil, token: nil, vault_client: nil)
      @mount = mount
      @role  = role
      @vault = vault_client || build_default_client(address, token)
    end

    # Issues a certificate by submitting the supplied CSR to
    # `<mount>/sign/<role>`. Returns a hash with the issued cert + chain
    # + serial. Never returns the private key (CSR-based flow, the caller
    # holds the key).
    def sign(csr_pem:, ttl_seconds:, common_name: nil, sans: [])
      params = { csr: csr_pem, ttl: "#{ttl_seconds}s", format: "pem" }
      params[:common_name] = common_name if common_name
      params[:alt_names]   = Array(sans).join(",") if Array(sans).any?

      secret = call_write("sign/#{@role}", params)
      data = extract_data(secret)

      {
        certificate:    data["certificate"]    || data[:certificate],
        ca_chain:       Array(data["ca_chain"] || data[:ca_chain]),
        issuing_ca:     data["issuing_ca"]     || data[:issuing_ca],
        serial_number:  data["serial_number"]  || data[:serial_number],
        expiration:     data["expiration"]     || data[:expiration]
      }
    rescue StandardError => e
      raise PkiError, "Vault PKI sign failed (mount=#{@mount} role=#{@role}): #{e.message}"
    end

    # Revokes a previously-issued certificate by its serial number.
    # Returns the revocation_time per Vault's response. Idempotent: revoking
    # an already-revoked serial returns the original revocation_time.
    def revoke(serial_number:)
      secret = call_write("revoke", { serial_number: serial_number })
      data = extract_data(secret)
      {
        revocation_time:     data["revocation_time"]     || data[:revocation_time],
        revocation_time_rfc3339: data["revocation_time_rfc3339"] || data[:revocation_time_rfc3339]
      }
    rescue StandardError => e
      raise PkiError, "Vault PKI revoke failed (serial=#{serial_number}): #{e.message}"
    end

    # Fetches the CA certificate chain in PEM format. This is the
    # intermediate (or root) cert + its chain that downstream callers
    # need to validate certs issued by this mount.
    #
    # The /ca/pem endpoint returns raw PEM (not a Vault::Secret wrapping)
    # so the gem's logical.read chokes when it tries to JSON-parse. We
    # bypass via direct HTTP GET using the gem's configured transport.
    def root_certificate_pem
      response = @vault.get("/v1/#{@mount}/ca/pem")
      body = response.respond_to?(:body) ? response.body : response.to_s
      raise PkiError, "Vault returned empty CA PEM at #{@mount}/ca/pem" if body.nil? || body.empty?

      body
    rescue PkiError
      raise
    rescue StandardError => e
      raise PkiError, "Vault PKI ca chain fetch failed: #{e.message}"
    end

    # Returns the role configuration hash (used by preflight_check to
    # verify the mount + role both exist).
    def role_config
      secret = @vault.logical.read("#{@mount}/roles/#{@role}")
      raise PkiError, "role '#{@role}' not configured at mount '#{@mount}'" if secret.nil?
      extract_data(secret)
    rescue PkiError
      raise
    rescue StandardError => e
      raise PkiError, "Vault PKI role lookup failed: #{e.message}"
    end

    private

    def call_write(path_suffix, params)
      result = @vault.logical.write("#{@mount}/#{path_suffix}", params)
      raise PkiError, "Vault write returned nil (path=#{@mount}/#{path_suffix})" if result.nil?
      result
    end

    def extract_data(secret)
      # Vault::Secret#data is a Hash with symbol keys; we normalize to
      # strings AND symbols both being checked at call sites for safety.
      return secret if secret.is_a?(Hash)
      secret.respond_to?(:data) ? secret.data : {}
    end

    # Prefer the AppRole-authenticated client from Security::VaultClient
    # — production wires the backend's identity that way and the bare
    # `Vault::Client.new(token: nil)` fallback issues unauthenticated
    # requests that Vault rejects with 403. Explicit token override (for
    # smoke tests against a dev vault) still wins when supplied.
    def build_default_client(address, token)
      explicit_token = token || ENV["VAULT_TOKEN"]
      if explicit_token.present?
        addr = address || ENV.fetch("VAULT_ADDR", "https://127.0.0.1:8200")
        return ::Vault::Client.new(address: addr, token: explicit_token)
      end

      if defined?(::Security::VaultClient) && ::Security::VaultClient.instance.client
        return ::Security::VaultClient.instance.client
      end

      addr = address || ENV.fetch("VAULT_ADDR", "https://127.0.0.1:8200")
      ::Vault::Client.new(address: addr)
    end
  end
end
