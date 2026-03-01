# frozen_string_literal: true

class CreateMarketingCampaignTables < ActiveRecord::Migration[8.0]
  def change
    # Marketing Campaigns
    create_table :marketing_campaigns, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :uuid, index: true

      t.string :name, null: false
      t.string :slug, null: false
      t.string :campaign_type, null: false # email, social, chat, sms, multi_channel
      t.string :status, default: "draft" # draft, scheduled, active, paused, completed, archived
      t.jsonb :channels, default: []
      t.integer :budget_cents, default: 0
      t.integer :spent_cents, default: 0
      t.jsonb :target_audience, default: {}
      t.datetime :scheduled_at
      t.jsonb :tags, default: []
      t.jsonb :settings, default: {}

      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :paused_at

      t.timestamps
    end

    add_index :marketing_campaigns, :slug, unique: true
    add_index :marketing_campaigns, :campaign_type
    add_index :marketing_campaigns, :status
    add_index :marketing_campaigns, :scheduled_at, where: "scheduled_at IS NOT NULL"
    add_index :marketing_campaigns, [:account_id, :name], unique: true

    add_check_constraint :marketing_campaigns,
      "campaign_type IN ('email', 'social', 'chat', 'sms', 'multi_channel')",
      name: "marketing_campaigns_type_check"
    add_check_constraint :marketing_campaigns,
      "status IN ('draft', 'scheduled', 'active', 'paused', 'completed', 'archived')",
      name: "marketing_campaigns_status_check"

    # Marketing Campaign Contents
    create_table :marketing_campaign_contents, id: :uuid do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :marketing_campaigns }, type: :uuid, index: true
      t.references :approved_by, foreign_key: { to_table: :users }, type: :uuid, index: true

      t.string :channel, null: false
      t.string :variant_name, default: "default"
      t.string :subject
      t.text :body
      t.string :preview_text
      t.jsonb :media_urls, default: []
      t.string :cta_text
      t.string :cta_url
      t.jsonb :platform_specific, default: {}
      t.boolean :ai_generated, default: false
      t.string :status, default: "draft" # draft, approved, rejected

      t.datetime :approved_at

      t.timestamps
    end

    add_index :marketing_campaign_contents, [:campaign_id, :channel, :variant_name],
      unique: true, name: "idx_campaign_contents_unique"
    add_index :marketing_campaign_contents, :channel

    add_check_constraint :marketing_campaign_contents,
      "status IN ('draft', 'approved', 'rejected')",
      name: "marketing_contents_status_check"

    # Marketing Content Calendars
    create_table :marketing_content_calendars, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :campaign, foreign_key: { to_table: :marketing_campaigns }, type: :uuid, index: true

      t.string :title, null: false
      t.string :entry_type, default: "post" # post, email, social, event, reminder
      t.date :scheduled_date, null: false
      t.time :scheduled_time
      t.boolean :all_day, default: false
      t.string :color
      t.string :status, default: "planned" # planned, scheduled, published, cancelled
      t.string :recurrence_rule
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :marketing_content_calendars, :scheduled_date
    add_index :marketing_content_calendars, [:account_id, :scheduled_date]

    add_check_constraint :marketing_content_calendars,
      "entry_type IN ('post', 'email', 'social', 'event', 'reminder')",
      name: "marketing_calendar_type_check"
    add_check_constraint :marketing_content_calendars,
      "status IN ('planned', 'scheduled', 'published', 'cancelled')",
      name: "marketing_calendar_status_check"

    # Marketing Email Lists
    create_table :marketing_email_lists, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true

      t.string :name, null: false
      t.string :slug, null: false
      t.string :list_type, default: "standard" # standard, dynamic, segment
      t.jsonb :dynamic_filter, default: {}
      t.integer :subscriber_count, default: 0
      t.boolean :double_opt_in, default: true
      t.string :welcome_email_subject
      t.text :welcome_email_body

      t.timestamps
    end

    add_index :marketing_email_lists, [:account_id, :slug], unique: true
    add_index :marketing_email_lists, :list_type

    add_check_constraint :marketing_email_lists,
      "list_type IN ('standard', 'dynamic', 'segment')",
      name: "marketing_email_lists_type_check"

    # Marketing Email Subscribers
    create_table :marketing_email_subscribers, id: :uuid do |t|
      t.references :email_list, null: false, foreign_key: { to_table: :marketing_email_lists }, type: :uuid, index: true

      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :status, default: "pending" # pending, subscribed, unsubscribed, bounced, complained
      t.string :source
      t.jsonb :custom_fields, default: {}
      t.jsonb :tags, default: []
      t.jsonb :preferences, default: {}
      t.integer :bounce_count, default: 0
      t.string :confirmation_token

      t.datetime :subscribed_at
      t.datetime :unsubscribed_at
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :marketing_email_subscribers, [:email_list_id, :email], unique: true
    add_index :marketing_email_subscribers, :status
    add_index :marketing_email_subscribers, :email
    add_index :marketing_email_subscribers, :confirmation_token, unique: true, where: "confirmation_token IS NOT NULL"

    add_check_constraint :marketing_email_subscribers,
      "status IN ('pending', 'subscribed', 'unsubscribed', 'bounced', 'complained')",
      name: "marketing_subscribers_status_check"

    # Marketing Campaign Email Lists (join table)
    create_table :marketing_campaign_email_lists, id: :uuid do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :marketing_campaigns }, type: :uuid, index: true
      t.references :email_list, null: false, foreign_key: { to_table: :marketing_email_lists }, type: :uuid, index: true

      t.timestamps
    end

    add_index :marketing_campaign_email_lists, [:campaign_id, :email_list_id],
      unique: true, name: "idx_campaign_email_lists_unique"

    # Marketing Social Media Accounts
    create_table :marketing_social_media_accounts, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :connected_by, foreign_key: { to_table: :users }, type: :uuid, index: true

      t.string :platform, null: false # twitter, linkedin, facebook, instagram
      t.string :platform_account_id, null: false
      t.string :platform_username
      t.string :status, default: "connected" # connected, disconnected, expired, error
      t.string :vault_path
      t.jsonb :scopes, default: []
      t.datetime :token_expires_at
      t.integer :post_count, default: 0
      t.integer :rate_limit_remaining
      t.datetime :rate_limit_reset_at

      t.timestamps
    end

    add_index :marketing_social_media_accounts, [:account_id, :platform, :platform_account_id],
      unique: true, name: "idx_social_accounts_unique"
    add_index :marketing_social_media_accounts, :platform
    add_index :marketing_social_media_accounts, :status

    add_check_constraint :marketing_social_media_accounts,
      "platform IN ('twitter', 'linkedin', 'facebook', 'instagram')",
      name: "marketing_social_platform_check"
    add_check_constraint :marketing_social_media_accounts,
      "status IN ('connected', 'disconnected', 'expired', 'error')",
      name: "marketing_social_status_check"

    # Marketing Campaign Metrics
    create_table :marketing_campaign_metrics, id: :uuid do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :marketing_campaigns }, type: :uuid, index: true

      t.string :channel, null: false
      t.date :metric_date, null: false
      t.integer :sends, default: 0
      t.integer :deliveries, default: 0
      t.integer :opens, default: 0
      t.integer :unique_opens, default: 0
      t.integer :clicks, default: 0
      t.integer :conversions, default: 0
      t.integer :unsubscribes, default: 0
      t.integer :bounces, default: 0
      t.integer :impressions, default: 0
      t.integer :engagements, default: 0
      t.integer :reach, default: 0
      t.integer :revenue_cents, default: 0
      t.integer :cost_cents, default: 0
      t.jsonb :custom_metrics, default: {}

      t.timestamps
    end

    add_index :marketing_campaign_metrics, [:campaign_id, :channel, :metric_date],
      unique: true, name: "idx_campaign_metrics_unique"
    add_index :marketing_campaign_metrics, :metric_date
  end
end
