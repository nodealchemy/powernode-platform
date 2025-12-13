# frozen_string_literal: true

class KnowledgeBaseArticleView < ApplicationRecord
  # Authentication

  # Associations
  belongs_to :article, class_name: "KnowledgeBaseArticle", foreign_key: "article_id"
  belongs_to :user, optional: true

  # Validations
  validates :session_id, presence: true, if: -> { user_id.blank? }
  validates :ip_address, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/ }, allow_blank: true

  # Scopes
  scope :authenticated, -> { where.not(user_id: nil) }
  scope :anonymous, -> { where(user_id: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :unique_users, -> { select(:user_id).distinct.where.not(user_id: nil) }
  scope :unique_sessions, -> { select(:session_id).distinct.where.not(session_id: nil) }

  # Methods
  def anonymous?
    user_id.nil?
  end

  def authenticated?
    user_id.present?
  end

  def self.analytics_for_article(article_id, period: 30.days)
    views = for_period(period.ago, Time.current).where(article_id: article_id)

    {
      total_views: views.count,
      unique_users: views.unique_users.count,
      unique_sessions: views.unique_sessions.count,
      anonymous_views: views.anonymous.count,
      authenticated_views: views.authenticated.count,
      daily_breakdown: daily_views_breakdown(views)
    }
  end

  def self.top_articles(limit: 10, period: 30.days)
    for_period(period.ago, Time.current)
      .joins(:article)
      .group("knowledge_base_articles.id, knowledge_base_articles.title")
      .order("COUNT(*) DESC")
      .limit(limit)
      .count
  end

  private

  def self.daily_views_breakdown(views)
    views
      .group_by_day(:created_at)
      .count
      .transform_keys { |date| date.strftime("%Y-%m-%d") }
  end
end
