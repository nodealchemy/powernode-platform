# frozen_string_literal: true

module Devops
  # Shared strong-params handling for DevOps controllers that accept raw TLS
  # material (CA cert / client cert / client key) and pack it into a single
  # JSON blob stored in the +encrypted_tls_credentials+ attribute.
  #
  # Extracted from Docker::HostsController and Swarm::ClustersController, which
  # carried byte-identical copies. Keeping the packing in one place means a
  # change to how TLS credentials are packed/stored applies to every consumer
  # instead of being missed in one controller.
  module TlsCredentialParams
    extend ActiveSupport::Concern

    private

    # Moves the permitted :tls_ca / :tls_cert / :tls_key params into a single
    # :encrypted_tls_credentials JSON blob (keys ca_cert / client_cert /
    # client_key). Leaves the blob unset when none of the three are present.
    def build_tls_credentials(permitted)
      tls_ca = permitted.delete(:tls_ca)
      tls_cert = permitted.delete(:tls_cert)
      tls_key = permitted.delete(:tls_key)

      if tls_ca.present? || tls_cert.present? || tls_key.present?
        permitted[:encrypted_tls_credentials] = {
          ca_cert: tls_ca,
          client_cert: tls_cert,
          client_key: tls_key
        }.to_json
      end

      permitted
    end
  end
end
