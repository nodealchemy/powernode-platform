# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe Security::MtlsClientVerifier do
  # Build a self-signed Ed25519 CA + a leaf it signs. Mirrors how
  # InternalCaService issues, but inline so this core spec stays independent of
  # the system extension.
  def build_ca(cn)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cert.not_before = Time.now - 3600
    cert.not_after  = Time.now + 3600
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer     = cert.subject
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, nil)
    [ key, cert ]
  end

  def sign_leaf(cn, ca_key, ca_cert, not_after: Time.now + 3600)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 2
    cert.not_before = Time.now - 3600
    cert.not_after  = not_after
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer     = ca_cert.subject
    cert.public_key = key
    cert.sign(ca_key, nil)
    cert
  end

  let(:our_ca)   { build_ca("Powernode Internal CA") }
  let(:our_key)  { our_ca[0] }
  let(:our_cert) { our_ca[1] }

  it "verifies a leaf signed by the expected anchor and returns its CN" do
    leaf = sign_leaf("fed:abc-123", our_key, our_cert)
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])

    expect(result.verified?).to be(true)
    expect(result.subject_cn).to eq("fed:abc-123")
  end

  it "REJECTS a leaf signed by a foreign CA (impersonation guard)" do
    foreign_key, foreign_cert = build_ca("Powernode Internal CA") # same CN, different key!
    leaf = sign_leaf("node-instance-uuid", foreign_key, foreign_cert)

    # Anchor is OUR CA; the leaf was signed by the foreign CA that merely
    # cloned our CN — must fail on the SIGNATURE, not be fooled by the name.
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])

    expect(result.verified?).to be(false)
    expect(result.error).to be_present
  end

  it "rejects an expired leaf" do
    leaf = sign_leaf("fed:expired", our_key, our_cert, not_after: Time.now - 60)
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])
    expect(result.verified?).to be(false)
  end

  it "rejects a malformed cert PEM" do
    result = described_class.verify(cert_pem: "not a cert", anchors: [ our_cert.to_pem ])
    expect(result.verified?).to be(false)
    expect(result.error).to match(/malformed/)
  end

  it "rejects when no client certificate is presented" do
    result = described_class.verify(cert_pem: "", anchors: [ our_cert.to_pem ])
    expect(result.verified?).to be(false)
  end

  it "fails closed when no usable trust anchor is supplied" do
    leaf = sign_leaf("fed:abc", our_key, our_cert)
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ "garbage" ])
    expect(result.verified?).to be(false)
    expect(result.error).to match(/no usable trust anchor/)
  end

  # IMP-01a02b0c — a verified result must say WHICH anchor signed the leaf.
  # "verified against one of these N CAs" cannot attribute a federation
  # binding failure, and it silently answers the wrong question when two
  # anchors share a subject DN.
  describe "anchor attribution" do
    it "reports the SHA-256 fingerprint of the anchor that actually signed the leaf" do
      _other_key, other_cert = build_ca("Powernode Internal CA ops-hub-b")
      leaf = sign_leaf("fed:abc-123", our_key, our_cert)

      result = described_class.verify(cert_pem: leaf.to_pem,
                                      anchors: [ [ our_cert.to_pem, other_cert.to_pem ].join("\n") ])

      expect(result.verified?).to be(true)
      expect(result.anchor_fingerprint).to eq(Security::CaFingerprint.of(our_cert))
      expect(result.anchor_fingerprint).not_to eq(Security::CaFingerprint.of(other_cert))
      expect(result.anchor_subject).to eq(our_cert.subject.to_s)
    end

    it "carries no anchor identity on a failed verification" do
      foreign_key, foreign_cert = build_ca("Powernode Internal CA foreign")
      leaf = sign_leaf("node-x", foreign_key, foreign_cert)

      result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])

      expect(result.verified?).to be(false)
      expect(result.anchor_fingerprint).to be_nil
    end

    it "lists the fingerprints of the anchors a route would accept" do
      _other_key, other_cert = build_ca("Powernode Internal CA ops-hub-b")
      bundle = [ our_cert.to_pem, other_cert.to_pem ].join("\n")

      expect(described_class.anchor_fingerprints([ bundle ]))
        .to eq([ Security::CaFingerprint.of(our_cert), Security::CaFingerprint.of(other_cert) ])
    end
  end

  # Hubs provisioned before InternalCaService stamped a hub-specific subject
  # keep their legacy "/CN=Powernode Internal CA (local-dev)" root FOREVER —
  # renaming a live root would de-authenticate every cert chaining to it. So
  # two such hubs federating still put two same-DN, different-key roots into
  # one bundle. OpenSSL's X509_STORE resolves the issuer by subject NAME, so a
  # single combined store tries only the root that was added first and rejects
  # the other hub's leaves with "certificate signature failure" — order
  # decides which hub breaks. The verifier must not inherit that.
  describe "same-DN anchor collision (legacy hubs that cannot be renamed)" do
    def colliding_pair
      a_key, a_cert = build_ca("Powernode Internal CA (local-dev)")
      b_key, b_cert = build_ca("Powernode Internal CA (local-dev)")
      { a: [ a_key, a_cert ], b: [ b_key, b_cert ] }
    end

    it "verifies a leaf from EACH root out of one bundle, whichever order they appear in" do
      pair = colliding_pair
      a_key, a_cert = pair[:a]
      b_key, b_cert = pair[:b]
      expect(a_cert.subject.to_s).to eq(b_cert.subject.to_s) # premise: the DNs really do collide

      leaf_a = sign_leaf("node-a", a_key, a_cert)
      leaf_b = sign_leaf("node-b", b_key, b_cert)

      [ [ a_cert, b_cert ], [ b_cert, a_cert ] ].each do |ordered|
        bundle = ordered.map(&:to_pem).join("\n")

        result_a = described_class.verify(cert_pem: leaf_a.to_pem, anchors: [ bundle ])
        result_b = described_class.verify(cert_pem: leaf_b.to_pem, anchors: [ bundle ])

        order_label = ordered.map { |c| Security::CaFingerprint.of(c)[0, 14] }.join(",")
        expect(result_a.verified?).to be(true), "leaf_a rejected with anchor order #{order_label}"
        expect(result_b.verified?).to be(true), "leaf_b rejected with anchor order #{order_label}"
        # ...and each names ITS OWN root, which the shared DN cannot.
        expect(result_a.anchor_fingerprint).to eq(Security::CaFingerprint.of(a_cert))
        expect(result_b.anchor_fingerprint).to eq(Security::CaFingerprint.of(b_cert))
      end
    end

    # The retry loop swapped Store#verify for StoreContext#verify and now runs
    # N attempts instead of one. Neither may lose the validity-window check —
    # an expired leaf must still be refused after every retry is exhausted.
    it "still REJECTS an EXPIRED leaf after exhausting every colliding root" do
      pair = colliding_pair
      a_key, a_cert = pair[:a]
      _b_key, b_cert = pair[:b]
      leaf = sign_leaf("node-a", a_key, a_cert, not_after: Time.now - 60)

      result = described_class.verify(cert_pem: leaf.to_pem,
                                      anchors: [ [ a_cert.to_pem, b_cert.to_pem ].join("\n") ])

      expect(result.verified?).to be(false)
      expect(result.anchor_fingerprint).to be_nil
      expect(result.error).to match(/expired/i)
    end

    it "still REJECTS a leaf signed by neither root, however many collide" do
      pair = colliding_pair
      _a_key, a_cert = pair[:a]
      _b_key, b_cert = pair[:b]
      foreign_key, foreign_cert = build_ca("Powernode Internal CA (local-dev)")
      leaf = sign_leaf("impostor", foreign_key, foreign_cert)

      result = described_class.verify(cert_pem: leaf.to_pem,
                                      anchors: [ [ a_cert.to_pem, b_cert.to_pem ].join("\n") ])

      expect(result.verified?).to be(false)
      expect(result.anchor_fingerprint).to be_nil
    end
  end
end
