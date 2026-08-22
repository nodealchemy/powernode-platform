# frozen_string_literal: true

require "openssl"

module Security
  # Cryptographically verifies a forwarded mTLS client-cert PEM against a
  # specific set of trust anchors, returning the verified subject CN AND the
  # fingerprint of the anchor that actually signed it.
  #
  # Federation mTLS Phase 2 (symmetric) adds peer CAs to the shared Traefik
  # client-auth bundle, so the proxy's chain-check no longer proves "signed by
  # OUR CA" — only "signed by our CA OR some peer's." Every route that resolves
  # identity from a cert CN must therefore RE-verify the leaf against the anchor
  # that is correct for THAT route:
  #   - node / worker / internal / cable → our own CA (reject peer-signed certs)
  #   - federation                       → the resolved peer's trusted_ca_pem
  #
  # Anchor-agnostic by design (the caller supplies the anchors) so this core
  # primitive never depends on the system extension's InternalCaService.
  #
  # Issuer-CN comparison is deliberately NOT used: a hostile peer controls its
  # own CA's CN and could clone ours. Only a signature check against the
  # expected CA's public key (OpenSSL::X509::Store) is sound. For the same
  # reason the RESULT reports the matched anchor by SHA-256 fingerprint
  # (Security::CaFingerprint), never by its subject DN.
  #
  # SAME-DN ANCHOR COLLISION (measured): OpenSSL's X509_STORE resolves a
  # leaf's issuer BY SUBJECT NAME. Put two self-signed roots with identical
  # subject DNs and different keys into ONE store and only the root added
  # FIRST is ever tried — leaves issued by the second fail with "certificate
  # signature failure" even though their CA is genuinely trusted, and which
  # one loses depends on insertion order. Every hub minting
  # "CN=Powernode Internal CA (local-dev)" made that collision easy to build.
  #
  # SCOPE, precisely: today no caller hands this class a multi-root anchor
  # set. `MtlsTrust.verify_request` passes our CA alone, and
  # `verify_request_against` passes ONE peer's trusted_ca_pem. The combined
  # client-auth bundle (our CA + every peer CA) is consumed by Traefik, whose
  # Go crypto/x509 tries ALL same-subject candidate parents and so has no
  # equivalent first-match limitation. The retry below is therefore
  # defense-in-depth, not a fix for a live break: it becomes load-bearing the
  # moment a single anchor entry legitimately carries two roots — which is
  # exactly the shape of a CA-ROTATION OVERLAP BUNDLE (old root + new root,
  # both trusted for the window), and legacy hubs can only ever adopt a
  # hub-specific subject via such a rotation.
  #
  # So: when the combined store fails and more than one self-signed anchor was
  # supplied, retry each root INDIVIDUALLY before reporting failure. Each
  # attempt strictly NARROWS the anchor set, so nothing is accepted that the
  # single-store form would not also have accepted from that root.
  class MtlsClientVerifier
    Result = ::Struct.new(:verified?, :subject_cn, :error,
                          :anchor_fingerprint, :anchor_subject,
                          keyword_init: true)

    class << self
      def verify(cert_pem:, anchors:)
        new(cert_pem: cert_pem, anchors: anchors).verify
      end

      # SHA-256 fingerprints of every parseable cert in the supplied anchor
      # material, in order. Diagnostics use this to say WHICH CAs a route
      # would have accepted, without ever printing a DN as if it were an
      # identity.
      def anchor_fingerprints(anchors)
        new(cert_pem: nil, anchors: anchors).anchor_certs.filter_map { |c| CaFingerprint.of(c) }
      end
    end

    def initialize(cert_pem:, anchors:)
      @cert_pem = cert_pem
      @anchors  = Array(anchors)
    end

    def verify
      return failure("no client certificate presented") if @cert_pem.blank?

      leaf = parse_one(@cert_pem)
      return failure("malformed client certificate") unless leaf

      certs = anchor_certs
      return failure("no usable trust anchor") if certs.empty?

      # Fast path: one store holding every anchor. Correct and sufficient
      # whenever the anchors' subject DNs are distinct.
      result = verify_against(leaf, certs)
      return result if result.verified?

      # Slow path: a same-DN collision can make the combined store reject a
      # leaf whose CA IS present. Retry each self-signed root on its own
      # (carrying any intermediates along) before believing the rejection.
      roots = certs.select { |c| self_signed?(c) }
      if roots.size > 1
        intermediates = certs.reject { |c| self_signed?(c) }
        roots.each do |root|
          retried = verify_against(leaf, [ root ] + intermediates)
          return retried if retried.verified?
        end
      end

      result
    end

    # Every parseable certificate across all supplied anchor entries. Public
    # so .anchor_fingerprints can reuse the parsing.
    def anchor_certs
      @anchor_certs ||= @anchors.flat_map { |pem| parse_all(pem) }
    end

    private

    # Verify `leaf` against exactly `certs` as trust anchors, reporting which
    # of them the chain actually terminated at.
    def verify_against(leaf, certs)
      store = ::OpenSSL::X509::Store.new
      certs.each do |ca|
        store.add_cert(ca)
      rescue ::OpenSSL::X509::StoreError
        nil # already present — still a usable anchor
      end

      # StoreContext (rather than Store#verify) so the verified CHAIN is
      # available afterwards: its terminal element is the anchor that signed
      # this leaf, which is the only sound answer to "which CA was this?".
      ctx = ::OpenSSL::X509::StoreContext.new(store, leaf)
      # #verify checks the signature chain AND the validity window.
      unless ctx.verify
        return failure("certificate does not chain to the expected CA (#{ctx.error_string})")
      end

      anchor = Array(ctx.chain).last
      Result.new(verified?: true,
                 subject_cn: subject_cn(leaf),
                 anchor_fingerprint: CaFingerprint.of(anchor),
                 anchor_subject: anchor&.subject&.to_s)
    end

    def self_signed?(cert)
      cert.subject == cert.issuer
    end

    def parse_one(pem)
      ::OpenSSL::X509::Certificate.new(pem)
    rescue ::OpenSSL::X509::CertificateError, ::ArgumentError, ::TypeError
      nil
    end

    # A trust anchor may be a bundle (root + intermediates); add them all.
    def parse_all(pem)
      return [] if pem.blank?

      pem.to_s.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
         .filter_map { |block| parse_one(block) }
    end

    def subject_cn(cert)
      entry = cert.subject.to_a.find { |name, _, _| name == "CN" }
      entry && entry[1]
    end

    def failure(message)
      Result.new(verified?: false, subject_cn: nil, error: message)
    end
  end
end
