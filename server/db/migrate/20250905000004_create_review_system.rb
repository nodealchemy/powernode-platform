# frozen_string_literal: true

class CreateReviewSystem < ActiveRecord::Migration[8.0]
  def change
    # Create app_reviews table - Core review functionality
    create_table :app_reviews, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.integer :rating, null: false
      t.string :title, limit: 255
      t.text :content
      t.integer :helpful_count, default: 0

      # Enhanced review features
      t.string :version_reviewed, limit: 50
      t.string :platform, limit: 50
      t.string :reviewer_name, limit: 100
      t.boolean :is_verified, default: false
      t.string :status, default: 'published', limit: 50
      t.text :moderation_notes
      t.datetime :reviewed_at
      t.datetime :published_at

      # Multi-dimensional ratings
      t.integer :usability_rating
      t.integer :features_rating
      t.integer :support_rating
      t.integer :value_rating

      # Review quality scoring
      t.decimal :quality_score, precision: 5, scale: 2
      t.text :sentiment_analysis
      t.jsonb :tags, default: []
      t.jsonb :metadata, default: {}

      t.timestamps null: false

      t.index [ :app_id, :account_id ], unique: true, name: 'idx_app_reviews_on_app_account_unique'
      t.index [ :rating ], name: 'idx_app_reviews_on_rating'
      t.index [ :status ], name: 'idx_app_reviews_on_status'
      t.index [ :published_at ], name: 'idx_app_reviews_on_published_at'
      t.index [ :helpful_count ], name: 'idx_app_reviews_on_helpful_count'
      t.index [ :quality_score ], name: 'idx_app_reviews_on_quality_score'
      t.index [ :is_verified ], name: 'idx_app_reviews_on_is_verified'
      t.index [ :created_at ], name: 'idx_app_reviews_on_created_at'
    end

    # Create review_helpfulness_votes table - User feedback on reviews
    create_table :review_helpfulness_votes, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_review, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.boolean :is_helpful, null: false
      t.integer :weight, default: 1
      t.timestamps null: false

      t.index [ :app_review_id, :account_id ], unique: true, name: 'idx_review_helpfulness_votes_on_review_account_unique'
      t.index [ :is_helpful ], name: 'idx_review_helpfulness_votes_on_is_helpful'
    end

    # Create review_responses table - Developer responses to reviews
    create_table :review_responses, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_review, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :responder, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.text :content, null: false
      t.string :status, default: 'published', limit: 50
      t.datetime :published_at
      t.timestamps null: false

      t.index [ :app_review_id ], name: 'idx_review_responses_on_app_review_id'
      t.index [ :responder_id ], name: 'idx_review_responses_on_responder_id'
      t.index [ :status ], name: 'idx_review_responses_on_status'
      t.index [ :published_at ], name: 'idx_review_responses_on_published_at'
    end

    # Create review_media_attachments table - Images, videos for reviews
    create_table :review_media_attachments, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_review, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :file_type, null: false, limit: 50
      t.string :file_url, null: false, limit: 1000
      t.string :file_name, limit: 255
      t.integer :file_size
      t.string :caption, limit: 500
      t.integer :display_order, default: 0
      t.timestamps null: false

      t.index [ :app_review_id, :display_order ], name: 'idx_review_media_attachments_on_review_display_order'
      t.index [ :file_type ], name: 'idx_review_media_attachments_on_file_type'
    end

    # Create review_aggregation_cache table - Performance optimization
    create_table :review_aggregation_cache, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.decimal :average_rating, precision: 3, scale: 2, default: 0.0
      t.integer :total_reviews, default: 0
      t.integer :five_star_count, default: 0
      t.integer :four_star_count, default: 0
      t.integer :three_star_count, default: 0
      t.integer :two_star_count, default: 0
      t.integer :one_star_count, default: 0

      # Multi-dimensional averages
      t.decimal :average_usability_rating, precision: 3, scale: 2
      t.decimal :average_features_rating, precision: 3, scale: 2
      t.decimal :average_support_rating, precision: 3, scale: 2
      t.decimal :average_value_rating, precision: 3, scale: 2

      # Additional metrics
      t.integer :verified_reviews_count, default: 0
      t.decimal :average_quality_score, precision: 5, scale: 2
      t.integer :total_helpful_votes, default: 0
      t.integer :response_count, default: 0
      t.decimal :response_rate, precision: 5, scale: 2, default: 0.0

      t.datetime :last_calculated_at, null: false
      t.timestamps null: false

      t.index [ :app_id ], unique: true, name: 'idx_review_aggregation_cache_on_app_id_unique'
      t.index [ :average_rating ], name: 'idx_review_aggregation_cache_on_average_rating'
      t.index [ :total_reviews ], name: 'idx_review_aggregation_cache_on_total_reviews'
      t.index [ :last_calculated_at ], name: 'idx_review_aggregation_cache_on_last_calculated_at'
    end

    # Create review_moderation_actions table - Moderation audit trail
    create_table :review_moderation_actions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_review, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :moderator, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :action_type, null: false, limit: 50
      t.string :previous_status, limit: 50
      t.string :new_status, limit: 50
      t.text :reason
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :app_review_id ], name: 'idx_review_moderation_actions_on_app_review_id'
      t.index [ :moderator_id ], name: 'idx_review_moderation_actions_on_moderator_id'
      t.index [ :action_type ], name: 'idx_review_moderation_actions_on_action_type'
      t.index [ :created_at ], name: 'idx_review_moderation_actions_on_created_at'
    end

    # Add check constraints
    add_check_constraint :app_reviews, 'rating >= 1 AND rating <= 5', name: 'valid_overall_rating'
    add_check_constraint :app_reviews, 'usability_rating IS NULL OR (usability_rating >= 1 AND usability_rating <= 5)', name: 'valid_usability_rating'
    add_check_constraint :app_reviews, 'features_rating IS NULL OR (features_rating >= 1 AND features_rating <= 5)', name: 'valid_features_rating'
    add_check_constraint :app_reviews, 'support_rating IS NULL OR (support_rating >= 1 AND support_rating <= 5)', name: 'valid_support_rating'
    add_check_constraint :app_reviews, 'value_rating IS NULL OR (value_rating >= 1 AND value_rating <= 5)', name: 'valid_value_rating'
    add_check_constraint :app_reviews, "status IN ('draft', 'published', 'hidden', 'flagged', 'removed')", name: 'valid_review_status'
    add_check_constraint :app_reviews, 'quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 100)', name: 'valid_quality_score'

    add_check_constraint :review_helpfulness_votes, 'weight > 0', name: 'valid_vote_weight'

    add_check_constraint :review_responses, "status IN ('draft', 'published', 'hidden', 'removed')", name: 'valid_response_status'

    add_check_constraint :review_media_attachments, "file_type IN ('image', 'video', 'document')", name: 'valid_media_type'
    add_check_constraint :review_media_attachments, 'file_size IS NULL OR file_size > 0', name: 'valid_file_size'
    add_check_constraint :review_media_attachments, 'display_order >= 0', name: 'valid_display_order'

    add_check_constraint :review_aggregation_cache, 'average_rating >= 0 AND average_rating <= 5', name: 'valid_cached_average_rating'
    add_check_constraint :review_aggregation_cache, 'total_reviews >= 0', name: 'valid_total_reviews'
    add_check_constraint :review_aggregation_cache, 'five_star_count >= 0 AND four_star_count >= 0 AND three_star_count >= 0 AND two_star_count >= 0 AND one_star_count >= 0', name: 'valid_rating_counts'
    add_check_constraint :review_aggregation_cache, 'response_rate >= 0 AND response_rate <= 100', name: 'valid_response_rate'

    add_check_constraint :review_moderation_actions, "action_type IN ('publish', 'hide', 'flag', 'remove', 'approve', 'reject', 'edit')", name: 'valid_moderation_action'

    # Create review_notifications table
    create_table :review_notifications, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_review, null: false, foreign_key: true, type: :uuid
      t.references :recipient, null: false, foreign_key: { to_table: :accounts }, type: :uuid
      t.references :triggered_by, null: true, foreign_key: { to_table: :accounts }, type: :uuid
      t.string :notification_type, null: false, limit: 100
      t.jsonb :delivery_channels, default: [], null: false
      t.string :priority, limit: 20, default: 'normal'
      t.string :status, limit: 20, default: 'pending'
      t.jsonb :template_data, default: {}, null: false
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.integer :retry_count, default: 0
      t.text :failure_reason
      t.jsonb :delivery_results, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :app_review_id ], name: 'idx_review_notifications_on_app_review_id'
      t.index [ :recipient_id ], name: 'idx_review_notifications_on_recipient_id'
      t.index [ :triggered_by_id ], name: 'idx_review_notifications_on_triggered_by_id'
      t.index [ :notification_type ], name: 'idx_review_notifications_on_notification_type'
      t.index [ :status ], name: 'idx_review_notifications_on_status'
      t.index [ :priority ], name: 'idx_review_notifications_on_priority'
      t.index [ :scheduled_at ], name: 'idx_review_notifications_on_scheduled_at'
      t.index [ :created_at ], name: 'idx_review_notifications_on_created_at'
      t.index [ :delivery_channels ], using: :gin, name: 'idx_review_notifications_on_delivery_channels'
    end

    # Create review_notification_deliveries table
    create_table :review_notification_deliveries, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :review_notification, null: false, foreign_key: true, type: :uuid
      t.string :delivery_channel, null: false, limit: 50
      t.string :status, limit: 20, default: 'pending'
      t.datetime :attempted_at
      t.datetime :delivered_at
      t.text :response_data
      t.text :error_message
      t.integer :attempt_count, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :review_notification_id ], name: 'idx_review_notification_deliveries_on_review_notification_id'
      t.index [ :delivery_channel ], name: 'idx_review_notification_deliveries_on_delivery_channel'
      t.index [ :status ], name: 'idx_review_notification_deliveries_on_status'
      t.index [ :attempted_at ], name: 'idx_review_notification_deliveries_on_attempted_at'
      t.index [ :delivered_at ], name: 'idx_review_notification_deliveries_on_delivered_at'
    end

    # Add check constraints for review notifications
    add_check_constraint :review_notifications, "notification_type IN ('new_review', 'review_response', 'review_flagged', 'review_approved', 'review_rejected', 'review_milestone', 'helpful_vote', 'review_digest', 'admin_alert')", name: 'valid_notification_type'
    add_check_constraint :review_notifications, "priority IN ('low', 'normal', 'high', 'urgent')", name: 'valid_notification_priority'
    add_check_constraint :review_notifications, "status IN ('pending', 'sent', 'failed', 'cancelled')", name: 'valid_notification_status'
    add_check_constraint :review_notifications, 'retry_count >= 0', name: 'valid_retry_count'

    add_check_constraint :review_notification_deliveries, "delivery_channel IN ('email', 'sms', 'push', 'webhook', 'slack')", name: 'valid_delivery_channel'
    add_check_constraint :review_notification_deliveries, "status IN ('pending', 'delivered', 'failed', 'cancelled')", name: 'valid_delivery_status'
    add_check_constraint :review_notification_deliveries, 'attempt_count >= 0', name: 'valid_delivery_attempt_count'
  end
end
