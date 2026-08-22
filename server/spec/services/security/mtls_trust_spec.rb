# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe Security::MtlsTrust do
  def build_ca(cn)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 1
    cert.not_before = Time.now - 3600; cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}"); cert.issuer = cert.subject
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, nil)
    [ key, cert ]
  end

  def sign_leaf(cn, ca_key, ca_cert)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 2
    cert.not_before = Time.now - 3600; cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}"); cert.issuer = ca_cert.subject
    cert.public_key = key
    cert.sign(ca_key, nil)
    cert
  end

  let(:our) { build_ca("Powernode Internal CA") }

  # Override the provider, restoring whatever was injected at boot afterwards.
  around do |example|
    original = described_class.own_ca_provider
    described_class.own_ca_provider = -> { our[1].to_pem }
    example.run
    described_class.own_ca_provider = original
  end

  def req(headers)
    instance_double(ActionDispatch::Request, headers: headers)
  end

  describe ".own_ca_pem (injectable provider)" do
    it "returns the injected CA bundle" do
      expect(described_class.own_ca_pem).to eq(our[1].to_pem)
    end
  end

  describe ".verify_request" do
    it "returns the CN for a cert signed by our CA (full PEM header)" do
      leaf = sign_leaf("node-instance-9", our[0], our[1])
      r = req(described_class::PEM_HEADER => CGI.escape(leaf.to_pem))
      expect(described_class.verify_request(r)).to eq("node-instance-9")
    end

    # The EXACT wire format Traefik's passTLSClientCert(pem: true) emits, which
    # Core::IngressConfigWriter now switches on (imp 01a028ab-f39b). Traefik
    # sanitizes the PEM first -- it deletes the `-----BEGIN/END CERTIFICATE-----`
    # lines and every newline -- and then url-escapes the remainder, so the
    # header is percent-escaped bare base64 (`+`->%2B, `/`->%2F, `=`->%3D) and
    # NEVER carries the PEM markers. This test pins that shape end to end: if
    # MtlsTrust could not reconstruct it, enabling `pem: true` in the ingress
    # would turn every worker call from "CN trusted" into "verification failed".
    it "reconstructs the sanitized+url-escaped PEM that Traefik passTLSClientCert(pem:true) emits" do
      leaf = sign_leaf("node-instance-9", our[0], our[1])
      sanitized = leaf.to_pem.gsub(/-----[A-Z ]+-----/, "").gsub(/\s+/, "")
      wire = CGI.escape(sanitized) # == Go url.QueryEscape over the base64 alphabet

      # Guard the premise: this really is the shape described above.
      expect(wire).not_to include("BEGIN CERTIFICATE")
      expect(wire).not_to include("\n")
      expect(wire).to match(/\A[A-Za-z0-9%]+\z/)

      r = req(described_class::PEM_HEADER => wire)
      expect(described_class.verify_request(r)).to eq("node-instance-9")
      # and it satisfies the cryptographic-only posture, which the no-PEM
      # deployment could never reach.
      expect(described_class.verify_request(r, require_pem: true)).to eq("node-instance-9")
    end

    it "reconstructs a RAW bare-base64 DER cert as the reverse proxy actually forwards it" do
      # powernode-reverse-proxy / Traefik passTLSClientCert(pem:true) forwards
      # the leaf as bare base64 DER — no BEGIN/END, standard base64 (+,/,=),
      # and NOT url-encoded. Regression (two-platform live mTLS smoke,
      # 2026-06-02): CGI.unescape turns a literal '+' into a space which the
      # whitespace strip then deletes, corrupting the DER so verification fails.
      leaf = nil
      bare = nil
      10.times do
        leaf = sign_leaf("node-instance-9", our[0], our[1])
        bare = Base64.strict_encode64(leaf.to_der)
        break if bare.include?("+")
      end
      expect(bare).to include("+"), "need a '+' in the base64 to exercise the bug"
      r = req(described_class::PEM_HEADER => bare) # RAW — exactly as forwarded, not CGI.escaped
      expect(described_class.verify_request(r)).to eq("node-instance-9")
    end

    # Traefik emits one escaped block PER PEER CERTIFICATE, comma-joined. Every
    # client on these routes presents a bare leaf today, but that rests on a
    # filesystem convention (node.crt holds one block) that nothing enforces —
    # and the joined value would otherwise reconstruct into a comma-bearing PEM
    # that OpenSSL rejects, i.e. a SILENT 401 with no diagnostic (imp
    # 01a028ab-f39b review). Take the leaf, which Traefik forwards first.
    it "takes the LEAF when Traefik comma-joins a presented chain" do
      leaf = sign_leaf("node-instance-9", our[0], our[1])
      other = build_ca("Some Intermediate")
      sanitize = ->(pem) { CGI.escape(pem.gsub(/-----[A-Z ]+-----/, "").gsub(/\s+/, "")) }
      wire = [ sanitize.call(leaf.to_pem), sanitize.call(other[1].to_pem) ].join(",")

      expect(wire).to include(",")
      expect(described_class.verify_request(wire.then { |w| req(described_class::PEM_HEADER => w) })).to eq("node-instance-9")
    end

    it "returns nil when the forwarded cert header is only a comma" do
      r = req(described_class::PEM_HEADER => ",")
      expect(described_class.verify_request(r)).to be_nil
    end

    it "returns nil for a cert signed by a FOREIGN CA that cloned our CN" do
      foreign = build_ca("Powernode Internal CA")
      leaf = sign_leaf("node-instance-9", foreign[0], foreign[1])
      r = req(described_class::PEM_HEADER => CGI.escape(leaf.to_pem))
      expect(described_class.verify_request(r)).to be_nil
    end

    it "returns nil when neither a PEM nor an Info header is present" do
      expect(described_class.verify_request(req({}))).to be_nil
    end

    it "falls back to the proxy-verified Info CN when no PEM is forwarded" do
      # Pre-symmetric posture: Traefik's chain-check (our-CA-only bundle) is
      # authoritative, so the forwarded CN is trusted without a re-verify.
      r = req(described_class::SUBJECT_HEADER => CGI.escape(%(Subject="CN=node-instance-7")))
      expect(described_class.verify_request(r)).to eq("node-instance-7")
    end
  end

  describe ".client_cert_presented?" do
    it "distinguishes cert-present from no-cert (for the cable JWT fallthrough)" do
      expect(described_class.client_cert_presented?(req(described_class::PEM_HEADER => "x"))).to be(true)
      expect(described_class.client_cert_presented?(req(described_class::SUBJECT_HEADER => "y"))).to be(true)
      expect(described_class.client_cert_presented?(req({}))).to be(false)
    end
  end
end
