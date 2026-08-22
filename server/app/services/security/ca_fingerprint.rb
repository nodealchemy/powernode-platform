# frozen_string_literal: true

require "openssl"

module Security
  # SHA-256 fingerprint of a certificate's DER encoding — the only sound
  # identity for a CA.
  #
  # A subject DN is NOT an identity. It is a name the CA's own operator
  # chooses, so two independently generated self-signed roots can carry
  # byte-identical subject AND issuer DNs over completely different keys —
  # which is exactly what every hub running the local adapter did before
  # InternalCaService started stamping a hub-specific subject.
  #
  # This is not merely an attribution problem. OpenSSL's X509_STORE looks the
  # issuer up BY SUBJECT NAME, so two same-named roots in one trust store
  # collide: the one added FIRST wins and every leaf issued by the other is
  # rejected with "certificate signature failure" (measured). Go's
  # crypto/x509 — what Traefik uses for the client-auth bundle — tries all
  # same-subject candidates and does not share that limitation, so the
  # collision bites on the Ruby side; see Security::MtlsClientVerifier for
  # exactly which anchor sets can reach it.
  #
  # Anywhere code asks "is this the same CA?", "have I already trusted this
  # CA?", or "WHICH anchor did this leaf chain to?", it must key on this
  # fingerprint and never on the DN.
  module CaFingerprint
    PREFIX = "sha256:"

    module_function

    # "sha256:<64 lowercase hex>" for an OpenSSL::X509::Certificate; nil for
    # anything else, so callers can treat nil as "not identifiable".
    def of(cert)
      return nil unless cert.is_a?(::OpenSSL::X509::Certificate)

      "#{PREFIX}#{::OpenSSL::Digest::SHA256.hexdigest(cert.to_der)}"
    end

    # Same, from a PEM string. Returns nil when the PEM does not parse —
    # callers that are assembling trust material must KEEP unparseable input
    # rather than dropping it (see Acme::TraefikConfigWriter).
    def of_pem(pem)
      of(::OpenSSL::X509::Certificate.new(pem.to_s))
    rescue ::OpenSSL::X509::CertificateError, ::ArgumentError, ::TypeError
      nil
    end
  end
end
