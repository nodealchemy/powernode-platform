# frozen_string_literal: true

class CreateChatGatewayTables < ActiveRecord::Migration[8.0]
  def change
    # Chat Channels - Platform connections
    create_table :chat_channels, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :default_agent, foreign_key: { to_table: :ai_agents }, type: :uuid, index: true

      t.string :platform, null: false  # whatsapp, telegram, discord, slack, mattermost
      t.string :name, null: false
      t.string :status, default: "disconnected"  # connected, disconnected, connecting, error
      t.string :webhook_token, null: false  # Unique token for webhook verification
      t.string :vault_path  # Path in HashiCorp Vault for credentials
      t.jsonb :configuration, default: {}  # Platform-specific configuration
      t.integer :rate_limit_per_minute, default: 60
      t.integer :message_count, default: 0
      t.integer :session_count, default: 0

      t.datetime :connected_at
      t.datetime :last_message_at
      t.datetime :last_error_at
      t.text :last_error

      t.timestamps
    end

    add_index :chat_channels, :platform
    add_index :chat_channels, :status
    add_index :chat_channels, :webhook_token, unique: true
    add_index :chat_channels, [ :account_id, :platform, :name ], unique: true

    add_check_constraint :chat_channels, "platform IN ('whatsapp', 'telegram', 'discord', 'slack', 'mattermost')", name: "chat_channels_platform_check"
    add_check_constraint :chat_channels, "status IN ('connected', 'disconnected', 'connecting', 'error')", name: "chat_channels_status_check"

    # Chat Sessions - User conversation mapping
    create_table :chat_sessions, id: :uuid do |t|
      t.references :channel, null: false, foreign_key: { to_table: :chat_channels }, type: :uuid, index: true
      t.references :ai_conversation, foreign_key: { to_table: :ai_conversations }, type: :uuid, index: true
      t.references :assigned_agent, foreign_key: { to_table: :ai_agents }, type: :uuid, index: true

      t.string :platform_user_id, null: false  # External user ID from platform
      t.string :platform_username  # Display name if available
      t.string :status, default: "active"  # active, idle, closed, blocked
      t.jsonb :context_window, default: {}  # Sliding context for agent
      t.jsonb :user_metadata, default: {}  # Platform-specific user info
      t.integer :message_count, default: 0
      t.integer :agent_handoff_count, default: 0

      t.datetime :last_activity_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :chat_sessions, :platform_user_id
    add_index :chat_sessions, :status
    add_index :chat_sessions, [ :channel_id, :platform_user_id ], unique: true
    add_index :chat_sessions, :last_activity_at

    add_check_constraint :chat_sessions, "status IN ('active', 'idle', 'closed', 'blocked')", name: "chat_sessions_status_check"

    # Chat Messages - Message tracking
    create_table :chat_messages, id: :uuid do |t|
      t.references :session, null: false, foreign_key: { to_table: :chat_sessions }, type: :uuid, index: true
      t.references :ai_message, foreign_key: { to_table: :ai_messages }, type: :uuid, index: true

      t.string :direction, null: false  # inbound, outbound
      t.string :message_type, default: "text"  # text, image, audio, video, document, location, sticker
      t.text :content  # Original content
      t.text :sanitized_content  # Content with injection protection
      t.string :delivery_status, default: "pending"  # pending, sent, delivered, read, failed
      t.string :platform_message_id  # External message ID from platform
      t.jsonb :platform_metadata, default: {}  # Platform-specific message data

      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at

      t.timestamps
    end

    add_index :chat_messages, :direction
    add_index :chat_messages, :message_type
    add_index :chat_messages, :delivery_status
    add_index :chat_messages, :platform_message_id
    add_index :chat_messages, [ :session_id, :created_at ]

    add_check_constraint :chat_messages, "direction IN ('inbound', 'outbound')", name: "chat_messages_direction_check"
    add_check_constraint :chat_messages, "message_type IN ('text', 'image', 'audio', 'video', 'document', 'location', 'sticker')", name: "chat_messages_type_check"
    add_check_constraint :chat_messages, "delivery_status IN ('pending', 'sent', 'delivered', 'read', 'failed')", name: "chat_messages_delivery_status_check"

    # Chat Message Attachments - Media files
    create_table :chat_message_attachments, id: :uuid do |t|
      t.references :message, null: false, foreign_key: { to_table: :chat_messages }, type: :uuid, index: true
      t.references :file_object, foreign_key: { to_table: :file_objects }, type: :uuid, index: true

      t.string :attachment_type, null: false  # image, audio, video, document
      t.string :mime_type
      t.string :filename
      t.string :platform_file_id  # External file ID for retrieval
      t.string :storage_url  # Internal storage URL
      t.bigint :file_size
      t.jsonb :metadata, default: {}  # Duration, dimensions, etc.
      t.text :transcription  # For audio/voice messages

      t.boolean :scanned_for_malware, default: false
      t.boolean :malware_detected, default: false
      t.datetime :scanned_at

      t.timestamps
    end

    add_index :chat_message_attachments, :attachment_type
    add_index :chat_message_attachments, :platform_file_id

    add_check_constraint :chat_message_attachments, "attachment_type IN ('image', 'audio', 'video', 'document')", name: "chat_attachments_type_check"

    # Chat Blacklists - Blocked users
    create_table :chat_blacklists, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :channel, foreign_key: { to_table: :chat_channels }, type: :uuid, index: true
      t.references :blocked_by, foreign_key: { to_table: :users }, type: :uuid, index: true

      t.string :platform_user_id, null: false
      t.string :reason
      t.string :block_type, default: "temporary"  # temporary, permanent
      t.datetime :expires_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :chat_blacklists, [ :account_id, :platform_user_id ]
    add_index :chat_blacklists, [ :channel_id, :platform_user_id ], unique: true, where: "channel_id IS NOT NULL"
    add_index :chat_blacklists, :expires_at, where: "expires_at IS NOT NULL"

    add_check_constraint :chat_blacklists, "block_type IN ('temporary', 'permanent')", name: "chat_blacklists_type_check"
  end
end
