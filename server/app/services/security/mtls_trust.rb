# frozen_string_literal: true

require "cgi"

module Security
  # The platform's own internal-CA trust root for verifying mTLS client certs
  # presented on node / worker / internal / cable routes.
  #
  # Federation mTLS Phase 2 (symmetric) adds peer CAs to the shared Traefik
  # client-auth bundle, so Traefik's chain-check no longer proves a presented
  # cert was issued by US. These routes must re-verify the forwarded leaf
  # against OUR CA so a peer-CA-signed cert can't impersonate a worker.
  #
  # The CA itself is minted by the system extension's InternalCaService, but
  # core must not depend on the extension — so the CA bundle is supplied via an
  # injectable provider. The extension's engine sets it at boot
  # (System::Mtls engine initializer); absent the extension, core falls back to
  # reading the on-disk CA file the reverse-proxy writes. Dependency points
  # extension → core, never the reverse.
  module MtlsTrust
    SUBJECT_HEADER = "X-Forwarded-Tls-Client-Cert-Info"
    PEM_HEADER     = "X-Forwarded-Tls-Client-Cert"
    OWN_CA_PEM_ENV = "POWERNODE_INTERNAL_CA_PEM" # path to our-CA-only PEM (fallback)

    class << self
      attr_writer :own_ca_provider

      def own_ca_provider
        @own_ca_provider ||= -> { default_own_ca_pem }
      end

      # Our CA bundle (PEM). nil when neither the extension provider nor the
      # on-disk fallback is available — callers fail closed on nil.
      def own_ca_pem
        own_ca_provider.call
      rescue StandardError => e
        ::Rails.logger.warn("[MtlsTrust] own_ca provider failed: #{e.class}: #{e.message}")
        nil
      end

      def reset!
        @own_ca_provider = nil
      end

      # True when the request carries ANY mTLS client-cert material. Lets the
      # cable arm distinguish "no cert → fall through to user-JWT" from "cert
      # present but invalid → reject".
      def client_cert_presented?(request)
        request.headers[PEM_HEADER].present? || request.headers[SUBJECT_HEADER].present?
      end

      # Verify the request's forwarded client cert against OUR CA and return
      # the verified subject CN, or nil if absent / unverifiable.
      #
      # `require_pem:` selects the trust posture, and the DEFAULT (false) is
      # deliberately unchanged — federation and node routes depend on the
      # forwarded-CN fallback and are not part of this opt-in:
      #
      #   false (default) — cryptographic when a PEM is forwarded, otherwise
      #     the forwarded subject CN is trusted (see the no-PEM branch below).
      #     That fallback is only as strong as the ingress: it trusts a header
      #     the client controls unless the proxy strips it first, and core can
      #     only guarantee that strip on the routers it writes itself.
      #
      #   true — CRYPTOGRAPHIC ONLY. Returns nil in the no-PEM posture rather
      #     than trusting the header. Callers that hand back secret material
      #     (e.g. the decrypted SMTP/provider credentials on
      #     Api::V1::EmailSettingsController#show) MUST use this so a forged
      #     X-Forwarded-Tls-Client-Cert-Info naming a known worker CN cannot
      #     reach a reveal path even if it survives the ingress.
      def verify_request(request, require_pem: false)
        pem = forwarded_pem(request)
        if pem.present?
          result = MtlsClientVerifier.verify(cert_pem: pem, anchors: [ own_ca_pem ])
          return result.verified? ? result.subject_cn : nil
        end

        return nil if require_pem

        # No full cert forwarded → no peer CAs are in the Traefik client-auth
        # bundle (the writer couples peer-CA trust with pem-forwarding), so
        # Traefik's own chain-check against our-CA-only is authoritative and we
        # trust the forwarded subject CN. Once symmetric federation is enabled
        # the PEM is always forwarded, so this path is inert in that posture.
        forwarded_subject_cn(request)
      end

      # Verify the request's forwarded cert against the GIVEN anchors (rather
      # than our CA) and return the verified subject CN. Returns :no_pem when no
      # full cert was forwarded (caller decides the graceful behavior) and nil
      # on verification failure. Used by federation auth to bind a presented
      # cert to its specific peer's CA (symmetric peers sign with their own).
      def verify_request_against(request, anchors:)
        result = verify_request_against_detailed(request, anchors: anchors)
        return :no_pem if result == :no_pem

        result.verified? ? result.subject_cn : nil
      end

      # Same check, but hands back the full MtlsClientVerifier::Result so the
      # caller can attribute the outcome: `anchor_fingerprint` names WHICH CA
      # signed a verified leaf, and `error` carries OpenSSL's reason when it
      # didn't. Callers rendering a refusal should use this — "not issued by
      # this peer's CA" is unactionable on its own, because before CAs carried
      # a hub-specific subject every hub's root presented the SAME DN and only
      # the fingerprint could tell two of them apart.
      # Returns :no_pem when no full cert was forwarded (unchanged posture).
      def verify_request_against_detailed(request, anchors:)
        pem = forwarded_pem(request)
        return :no_pem if pem.blank?

        MtlsClientVerifier.verify(cert_pem: pem, anchors: Array(anchors))
      end

      # SHA-256 fingerprint of OUR internal CA root, for diagnostics and for
      # operators comparing a peer's advertised anchor against ours. nil when
      # no CA material is available (the fail-closed posture own_ca_pem
      # already has).
      def own_ca_fingerprint
        MtlsClientVerifier.anchor_fingerprints([ own_ca_pem ]).first
      end

      # The subject CN from Traefik's passTLSClientCert Info header (URL-encoded
      # `Subject="CN=<value>"`). The single home for forwarded-CN parsing — used
      # by verify_request's no-PEM path AND by FederationApi::BaseController to
      # resolve the calling peer before its per-peer signature check.
      def forwarded_subject_cn(request)
        info = request.headers[SUBJECT_HEADER].presence
        return nil unless info

        decoded = ::CGI.unescape(info)
        match = decoded.match(/\bCN\s*=\s*"?([^,"]+)"?/i)
        match && match[1]&.strip
      end

      private

      def forwarded_pem(request)
        raw = request.headers[PEM_HEADER].presence
        return nil unless raw

        # Traefik forwards ONE escaped block PER PEER CERTIFICATE, joined with a
        # comma (getCertificate loops over req.TLS.PeerCertificates). Today every
        # client on these routes presents a bare leaf — the worker sets a single
        # `client_cert` and the Go agent writes a leaf-only node.crt — but that is
        # a filesystem convention, not an enforced invariant: TLS's key-pair
        # loader reads EVERY block in the cert file, so concatenating a chain into
        # node.crt would silently start sending two. Without this split the joined
        # value reconstructs into a PEM containing a literal comma, OpenSSL
        # rejects it, and verify_request returns nil — a silent 401 with no
        # diagnostic. Take the LEAF (first element); a comma appears in neither
        # encoding's alphabet (CGI/query escaping emits %2C; base64 has no comma),
        # so this never truncates a single-cert value.
        raw = raw.split(",").first.to_s.strip
        return nil if raw.empty?

        # Traefik's passTLSClientCert(pem:true) forwards EITHER a percent-encoded
        # PEM (with %-escapes incl. the BEGIN/END markers + newlines) OR a bare
        # base64 DER body (standard base64 with +,/,= — NOT url-encoded; this is
        # what powernode-reverse-proxy emits). Only unescape the former:
        # CGI.unescape turns a literal '+' into a space, which reconstruct_pem's
        # whitespace strip then deletes — silently corrupting bare-base64 DER.
        # '%' never appears in base64, so it cleanly discriminates the encodings.
        decoded = raw.include?("%") ? ::CGI.unescape(raw) : raw
        reconstruct_pem(decoded)
      end

      # Traefik's passTLSClientCert(pem:true) forwards the leaf either as a full
      # PEM or as a bare base64 body (version-dependent); normalize both.
      def reconstruct_pem(decoded)
        return decoded if decoded.include?("BEGIN CERTIFICATE")

        body = decoded.gsub(/\s+/, "")
        return nil if body.empty?

        "-----BEGIN CERTIFICATE-----\n#{body.scan(/.{1,64}/).join("\n")}\n-----END CERTIFICATE-----\n"
      end

      def default_own_ca_pem
        path = ::ENV[OWN_CA_PEM_ENV].presence
        path && ::File.exist?(path) ? ::File.read(path) : nil
      end
    end
  end
end
