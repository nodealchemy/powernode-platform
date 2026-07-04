# frozen_string_literal: true

# x-com-provider campaign (I2): OAuth 2.0 credential storage foundation.
#
# Ai::DataSourceCredential already holds simple API key/secret pairs via Rails 8
# `encrypts`. OAuth2 Authorization-Code providers (starting with X.com) need two
# more things on the same row: the app's registered client_id/client_secret, and
# the per-user access/refresh tokens minted by the provider's OAuth callback (a
# later increment). Mirrors the existing encrypted_api_key/encrypted_api_secret
# column shape (plain string, encrypted at the Rails layer) so `encrypts` keeps
# working the same way for the new columns.
class AddOauth2FieldsToAiDataSourceCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_data_source_credentials, :encrypted_client_id, :string
    add_column :ai_data_source_credentials, :encrypted_client_secret, :string
    add_column :ai_data_source_credentials, :encrypted_access_token, :string
    add_column :ai_data_source_credentials, :encrypted_refresh_token, :string
    add_column :ai_data_source_credentials, :access_token_expires_at, :datetime
    add_column :ai_data_source_credentials, :oauth_scopes, :jsonb, null: false, default: []
  end
end
