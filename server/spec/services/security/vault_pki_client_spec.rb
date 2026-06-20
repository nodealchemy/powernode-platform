# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Security::VaultPkiClient — a thin facade over the
# Vault gem's PKI engine. These examples pin CURRENT behavior: which Vault
# paths/params the client builds and how it parses the (stubbed) responses.
#
# SAFETY: no real Vault is ever contacted and no real key/cert material is
# used. The Vault client is injected as a test double via the `vault_client:`
# constructor kwarg, so `build_default_client` / `::Vault::Client.new` are
# never reached. All PEM strings below are obvious fakes.
RSpec.describe Security::VaultPkiClient do
  # Fake, non-sensitive PEM blobs — never real certificate material.
  let(:fake_cert)      { "-----BEGIN CERTIFICATE-----\nTESTCERT\n-----END CERTIFICATE-----" }
  let(:fake_issuing)   { "-----BEGIN CERTIFICATE-----\nTESTISSUER\n-----END CERTIFICATE-----" }
  let(:fake_ca_pem)    { "-----BEGIN CERTIFICATE-----\nTESTCA\n-----END CERTIFICATE-----" }

  let(:vault_logical) { instance_double(Vault::Logical) }
  # The real client also exposes #get (used by root_certificate_pem), so the
  # double needs both seams. instance_double(Vault::Client) verifies these
  # methods actually exist on the gem's client class.
  let(:vault_client)  { instance_double(Vault::Client, logical: vault_logical) }

  let(:mount) { "pki_int" }
  let(:role)  { "node" }
  let(:client) { described_class.new(mount: mount, role: role, vault_client: vault_client) }

  # A Vault::Secret-like stub: responds to #data with a symbol-keyed Hash,
  # matching what extract_data expects from the real gem.
  def vault_secret(data)
    double("Vault::Secret", data: data)
  end

  describe "construction" do
    it "exposes the configured mount and role" do
      expect(client.mount).to eq("pki_int")
      expect(client.role).to eq("node")
    end

    it "defaults mount/role when not supplied" do
      c = described_class.new(vault_client: vault_client)
      expect(c.mount).to eq(described_class::DEFAULT_MOUNT)
      expect(c.role).to eq(described_class::DEFAULT_ROLE)
      expect(described_class::DEFAULT_MOUNT).to eq("pki_int")
      expect(described_class::DEFAULT_ROLE).to eq("node")
    end
  end

  describe "#sign" do
    let(:sign_data) do
      {
        certificate:   fake_cert,
        ca_chain:      [fake_issuing],
        issuing_ca:    fake_issuing,
        serial_number: "11:22:33:44",
        expiration:    1_700_000_000
      }
    end

    it "writes the CSR to <mount>/sign/<role> with ttl in seconds + pem format" do
      expect(vault_logical).to receive(:write).with(
        "pki_int/sign/node",
        hash_including(csr: "CSRDATA", ttl: "3600s", format: "pem")
      ).and_return(vault_secret(sign_data))

      client.sign(csr_pem: "CSRDATA", ttl_seconds: 3600, common_name: "node.local", sans: [])
    end

    it "passes common_name through when supplied" do
      expect(vault_logical).to receive(:write).with(
        "pki_int/sign/node",
        hash_including(common_name: "node.local")
      ).and_return(vault_secret(sign_data))

      client.sign(csr_pem: "CSRDATA", ttl_seconds: 60, common_name: "node.local", sans: [])
    end

    it "joins SANs into a comma-separated alt_names param" do
      expect(vault_logical).to receive(:write).with(
        "pki_int/sign/node",
        hash_including(alt_names: "a.local,b.local")
      ).and_return(vault_secret(sign_data))

      client.sign(csr_pem: "CSRDATA", ttl_seconds: 60, common_name: nil, sans: ["a.local", "b.local"])
    end

    it "omits common_name and alt_names when not provided / empty" do
      expect(vault_logical).to receive(:write) do |_path, params|
        expect(params).not_to have_key(:common_name)
        expect(params).not_to have_key(:alt_names)
        vault_secret(sign_data)
      end

      client.sign(csr_pem: "CSRDATA", ttl_seconds: 60, common_name: nil, sans: [])
    end

    it "returns the parsed certificate, chain and serial from the response" do
      allow(vault_logical).to receive(:write).and_return(vault_secret(sign_data))

      result = client.sign(csr_pem: "CSRDATA", ttl_seconds: 3600, common_name: "node.local", sans: [])

      expect(result).to eq(
        certificate:   fake_cert,
        ca_chain:      [fake_issuing],
        issuing_ca:    fake_issuing,
        serial_number: "11:22:33:44",
        expiration:    1_700_000_000
      )
    end

    it "tolerates string-keyed response data (Vault gem variance)" do
      string_keyed = {
        "certificate"   => fake_cert,
        "ca_chain"      => [fake_issuing],
        "issuing_ca"    => fake_issuing,
        "serial_number" => "aa:bb",
        "expiration"    => 42
      }
      allow(vault_logical).to receive(:write).and_return(vault_secret(string_keyed))

      result = client.sign(csr_pem: "CSRDATA", ttl_seconds: 60, common_name: nil, sans: [])
      expect(result[:certificate]).to eq(fake_cert)
      expect(result[:serial_number]).to eq("aa:bb")
    end

    it "wraps a nil Vault write (call_write guard) in PkiError" do
      allow(vault_logical).to receive(:write).and_return(nil)

      expect { client.sign(csr_pem: "CSRDATA", ttl_seconds: 60, common_name: nil, sans: []) }
        .to raise_error(described_class::PkiError, /sign failed.*mount=pki_int role=node/)
    end

    it "wraps any Vault error in PkiError with mount/role context" do
      allow(vault_logical).to receive(:write)
        .and_raise(Vault::HTTPError.new("pki", double(code: 400, body: "bad csr")))

      expect { client.sign(csr_pem: "CSRDATA", ttl_seconds: 60, common_name: nil, sans: []) }
        .to raise_error(described_class::PkiError, /sign failed \(mount=pki_int role=node\)/)
    end
  end

  describe "#revoke" do
    let(:revoke_data) do
      { revocation_time: 1_700_000_500, revocation_time_rfc3339: "2023-11-14T22:01:40Z" }
    end

    it "writes the serial to <mount>/revoke" do
      expect(vault_logical).to receive(:write)
        .with("pki_int/revoke", { serial_number: "11:22:33:44" })
        .and_return(vault_secret(revoke_data))

      client.revoke(serial_number: "11:22:33:44")
    end

    it "returns the parsed revocation timestamps" do
      allow(vault_logical).to receive(:write).and_return(vault_secret(revoke_data))

      result = client.revoke(serial_number: "11:22:33:44")
      expect(result).to eq(
        revocation_time:         1_700_000_500,
        revocation_time_rfc3339: "2023-11-14T22:01:40Z"
      )
    end

    it "wraps Vault errors in PkiError with the serial in the message" do
      allow(vault_logical).to receive(:write)
        .and_raise(Vault::HTTPError.new("pki", double(code: 500, body: "boom")))

      expect { client.revoke(serial_number: "de:ad:be:ef") }
        .to raise_error(described_class::PkiError, /revoke failed \(serial=de:ad:be:ef\)/)
    end

    it "wraps a nil Vault write in PkiError" do
      allow(vault_logical).to receive(:write).and_return(nil)

      expect { client.revoke(serial_number: "de:ad:be:ef") }
        .to raise_error(described_class::PkiError, /revoke failed/)
    end
  end

  describe "#root_certificate_pem" do
    it "GETs /v1/<mount>/ca/pem and returns the response body" do
      response = double("HttpResponse", body: fake_ca_pem)
      expect(vault_client).to receive(:get).with("/v1/pki_int/ca/pem").and_return(response)

      expect(client.root_certificate_pem).to eq(fake_ca_pem)
    end

    it "falls back to to_s when the response has no #body" do
      expect(vault_client).to receive(:get).with("/v1/pki_int/ca/pem").and_return(fake_ca_pem)

      expect(client.root_certificate_pem).to eq(fake_ca_pem)
    end

    it "raises PkiError when the CA PEM body is empty" do
      response = double("HttpResponse", body: "")
      allow(vault_client).to receive(:get).and_return(response)

      expect { client.root_certificate_pem }
        .to raise_error(described_class::PkiError, /empty CA PEM/)
    end

    it "raises PkiError when the CA PEM body is nil" do
      response = double("HttpResponse", body: nil)
      allow(vault_client).to receive(:get).and_return(response)

      expect { client.root_certificate_pem }
        .to raise_error(described_class::PkiError, /empty CA PEM/)
    end

    it "wraps transport errors in PkiError" do
      allow(vault_client).to receive(:get).and_raise(StandardError.new("connection refused"))

      expect { client.root_certificate_pem }
        .to raise_error(described_class::PkiError, /ca chain fetch failed: connection refused/)
    end
  end

  describe "#role_config" do
    let(:role_data) { { allow_any_name: true, max_ttl: "72h", key_type: "rsa" } }

    it "reads <mount>/roles/<role> and returns the role configuration" do
      expect(vault_logical).to receive(:read)
        .with("pki_int/roles/node")
        .and_return(vault_secret(role_data))

      expect(client.role_config).to eq(role_data)
    end

    it "returns a plain Hash response unchanged (extract_data passthrough)" do
      allow(vault_logical).to receive(:read).and_return(role_data)

      expect(client.role_config).to eq(role_data)
    end

    it "raises PkiError when the role is not configured (nil read)" do
      allow(vault_logical).to receive(:read).and_return(nil)

      expect { client.role_config }
        .to raise_error(described_class::PkiError, /role 'node' not configured at mount 'pki_int'/)
    end

    it "wraps Vault read errors in PkiError" do
      allow(vault_logical).to receive(:read)
        .and_raise(Vault::HTTPError.new("pki", double(code: 403, body: "denied")))

      expect { client.role_config }
        .to raise_error(described_class::PkiError, /role lookup failed/)
    end
  end
end
