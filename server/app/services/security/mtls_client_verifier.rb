# frozen_string_literal: true

require "openssl"

module Security
  # Cryptographically verifies a forwarded mTLS client-cert PEM against a
  # specific set of trust anchors, returning the verified subject CN.
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
  # expected CA's public key (OpenSSL::X509::Store#verify) is sound.
  class MtlsClientVerifier
    Result = ::Struct.new(:verified?, :subject_cn, :error, keyword_init: true)

    class << self
      def verify(cert_pem:, anchors:)
        new(cert_pem: cert_pem, anchors: anchors).verify
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

      store = ::OpenSSL::X509::Store.new
      anchor_count = 0
      @anchors.each do |pem|
        parse_all(pem).each do |ca|
          store.add_cert(ca)
          anchor_count += 1
        rescue ::OpenSSL::X509::StoreError
          anchor_count += 1 # already present — still a usable anchor
        end
      end
      return failure("no usable trust anchor") if anchor_count.zero?

      # Store#verify checks the signature chain AND the validity window.
      unless store.verify(leaf)
        return failure("certificate does not chain to the expected CA (#{store.error_string})")
      end

      Result.new(verified?: true, subject_cn: subject_cn(leaf))
    end

    private

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
