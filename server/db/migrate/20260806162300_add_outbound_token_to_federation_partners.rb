# frozen_string_literal: true

# Cross-plane MCP invocation: a plane that CALLS a federation partner must present
# the partner's shared bearer secret. `federation_token_hash` is a one-way bcrypt
# digest used to VERIFY an inbound token, so it cannot supply the plaintext the
# caller has to send. This column holds that outbound secret, encrypted at rest
# via Security::CredentialEncryptionService (namespace "federation") — mirroring
# how McpServer stores its OAuth tokens. Nullable: only partners this plane calls
# out to need it; discovery-only rows leave it blank.
class AddOutboundTokenToFederationPartners < ActiveRecord::Migration[8.1]
  def change
    add_column :federation_partners, :outbound_token_encrypted, :string
  end
end
