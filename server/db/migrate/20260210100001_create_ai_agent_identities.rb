# frozen_string_literal: true

class CreateAiAgentIdentities < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_identities, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.uuid :agent_id, null: false
      t.text :public_key, null: false
      t.text :encrypted_private_key, null: false
      t.string :key_fingerprint, null: false
      t.string :algorithm, null: false, default: "ed25519"
      t.string :status, null: false, default: "active"
      t.string :agent_uri
      t.jsonb :attestation_claims, default: {}
      t.jsonb :capabilities, default: []
      t.datetime :rotated_at
      t.datetime :revoked_at
      t.string :revocation_reason
      t.datetime :rotation_overlap_until
      t.datetime :expires_at
      t.timestamps
    end

    add_index :ai_agent_identities, :agent_id
    add_index :ai_agent_identities, :key_fingerprint, unique: true
    add_index :ai_agent_identities, :status
    add_index :ai_agent_identities, [:agent_id, :status]
  end
end
