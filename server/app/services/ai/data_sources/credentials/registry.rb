# frozen_string_literal: true

module Ai
  module DataSources
    module Credentials
      # Resolves a dynamic credential broker for a data source's configured broker
      # type (data_source.auth_config["broker"]["type"]).
      #
      # CONTRACT (every broker conforms — see BaseBroker):
      #   broker.acquire(data_source:, base_credential:, config:)
      #     -> a credential satisfying the signer contract
      #        (#decrypted_api_key / #decrypted_api_secret / #[](name)), either a
      #        freshly-acquired BrokeredCredential or the base_credential unchanged.
      #
      # Generic fallback: an unknown or blank type resolves to StaticBroker, which
      # returns the base credential unchanged (no brokering). This MIRRORS
      # Ai::DataSources::Auth::SignerRegistry's NoneSigner fallback exactly, so a
      # source configured with an unrecognized broker type degrades safely to the
      # stored credential instead of raising.
      #
      # NOTE: the concrete broker classes other than StaticBroker may not be loaded
      # at definition time — that is fine, .for only constantizes the chosen class
      # on call (lazy), exactly like SignerRegistry.
      module Registry
        module_function

        # Canonical broker type => class map. Types are matched case-insensitively
        # after normalization. Blank/unknown => "static".
        BROKERS = {
          "static"                    => "Ai::DataSources::Credentials::StaticBroker",
          "oauth2_client_credentials" => "Ai::DataSources::Credentials::Oauth2ClientCredentialsBroker",
          "oauth2_authorization_code" => "Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker",
          "aws_sts"                   => "Ai::DataSources::Credentials::AwsStsBroker",
          "aws_sts_web_identity"      => "Ai::DataSources::Credentials::AwsStsWebIdentityBroker",
          "vault_dynamic"             => "Ai::DataSources::Credentials::VaultDynamicBroker",
          "presigned_url"             => "Ai::DataSources::Credentials::PresignedUrlBroker",
          "atproto_app_password"      => "Ai::DataSources::Credentials::AtprotoAppPasswordBroker"
        }.freeze

        # @param broker_type [String, Symbol, nil]
        # @return [#acquire] a broker instance conforming to the CONTRACT.
        def for(broker_type)
          class_name = BROKERS.fetch(normalize(broker_type), BROKERS["static"])
          class_name.constantize.new
        end

        # @return [Array<String>] the registered broker type names.
        def types
          BROKERS.keys
        end

        def normalize(broker_type)
          key = broker_type.to_s.strip.downcase
          key.empty? ? "static" : key
        end
        private_class_method :normalize
      end
    end
  end
end
