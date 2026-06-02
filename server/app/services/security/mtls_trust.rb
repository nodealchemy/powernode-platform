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
      def verify_request(request)
        pem = forwarded_pem(request)
        if pem.present?
          result = MtlsClientVerifier.verify(cert_pem: pem, anchors: [ own_ca_pem ])
          return result.verified? ? result.subject_cn : nil
        end

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
        pem = forwarded_pem(request)
        return :no_pem if pem.blank?

        result = MtlsClientVerifier.verify(cert_pem: pem, anchors: Array(anchors))
        result.verified? ? result.subject_cn : nil
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

        reconstruct_pem(::CGI.unescape(raw))
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
