# frozen_string_literal: true

class CommunityAgent < ApplicationRecord
  # Concerns
  include Auditable

  # Constants
  VISIBILITIES = %w[public unlisted private].freeze
  STATUSES = %w[pending active suspended deprecated].freeze
  CATEGORIES = %w[automation analysis integration custom].freeze

  # Associations
  belongs_to :owner_account, class_name: "Account"
  belongs_to :agent, class_name: "Ai::Agent"
  belongs_to :agent_card, class_name: "Ai::AgentCard", optional: true
  belongs_to :published_by, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", optional: true
  belongs_to :registered_by, class_name: "User", optional: true

  has_many :ratings, class_name: "CommunityAgentRating", dependent: :destroy
  has_many :reports, class_name: "CommunityAgentReport", dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :description, presence: true, length: { maximum: 1000 }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :protocol_version, presence: true
  validate :unique_agent_registration

  # Scopes
  scope :public_visible, -> { where(visibility: "public", status: "active") }
  scope :discoverable, -> { where(visibility: %w[public unlisted], status: "active") }
  scope :verified, -> { where(verified: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :top_rated, -> { where("rating_count >= 5").order(avg_rating: :desc) }
  scope :popular, -> { order(task_count: :desc) }
  scope :federated, -> { where(federated: true) }
  scope :published, -> { where(status: "active").where.not(published_at: nil) }

  # Callbacks
  before_validation :generate_slug, on: :create
  after_create :link_agent_card

  # Status methods
  def active?
    status == "active"
  end

  def pending?
    status == "pending"
  end

  def suspended?
    status == "suspended"
  end

  def public?
    visibility == "public"
  end

  # Lifecycle
  def activate!
    update!(status: "active", published_at: Time.current)
  end

  def suspend!(reason: nil)
    update!(
      status: "suspended",
      capabilities: capabilities.merge("suspension_reason" => reason)
    )
  end

  def deprecate!
    update!(status: "deprecated")
  end

  def verify!(verified_by_user)
    update!(
      verified: true,
      verified_at: Time.current,
      verified_by: verified_by_user
    )
  end

  # Publish the agent to the community
  def publish!
    update!(
      status: "active",
      published_at: Time.current,
      visibility: "public"
    )
  end

  # Unpublish the agent from the community
  def unpublish!
    update!(
      published_at: nil,
      visibility: "private"
    )
  end

  # Metrics
  def record_task!(success:)
    increment!(:task_count)
    if success
      increment!(:success_count)
    else
      increment!(:failure_count)
    end
    update_reputation!
  end

  def refresh_rating!
    stats = ratings.where.not(hidden: true).select(
      "AVG(rating) as avg, COUNT(*) as count"
    ).first

    update!(
      avg_rating: stats.avg || 0,
      rating_count: stats.count
    )

    update_reputation!
  end

  def update_reputation!
    # Calculate reputation based on multiple factors
    success_rate = task_count.positive? ? (success_count.to_f / task_count * 100) : 0
    rating_factor = (avg_rating / 5.0) * 100
    volume_factor = [Math.log10(task_count + 1) * 10, 30].min
    verified_bonus = verified? ? 10 : 0

    score = (success_rate * 0.4 + rating_factor * 0.3 + volume_factor * 0.2 + verified_bonus * 0.1)
    update_column(:reputation_score, score.round(2))
  end

  # Community summary
  def community_summary
    {
      id: id,
      slug: slug,
      name: name,
      description: description,
      category: category,
      tags: tags,
      visibility: visibility,
      verified: verified,
      reputation_score: reputation_score,
      avg_rating: avg_rating,
      rating_count: rating_count,
      task_count: task_count,
      success_rate: success_rate,
      protocol_version: protocol_version,
      federated: federated,
      owner_account: owner_account.name,
      published_at: published_at
    }
  end

  def community_details
    community_summary.merge(
      long_description: long_description,
      capabilities: capabilities,
      authentication: authentication,
      endpoint_url: endpoint_url,
      version: version,
      changelog: changelog,
      last_updated_at: last_updated_at,
      subscriber_count: subscriber_count,
      avg_response_time_ms: avg_response_time_ms,
      verified_at: verified_at,
      agent_card_id: agent_card_id
    )
  end

  # Public summary - excludes sensitive endpoint URL
  def public_summary
    community_summary.except(:endpoint_url)
  end

  # Public details - excludes sensitive authentication and endpoint info
  def public_details
    community_details.except(:authentication, :endpoint_url)
  end

  # Owner details - full details including private fields for the owner
  def owner_details
    community_details.merge(
      registered_by_id: registered_by_id,
      registered_at: created_at,
      can_edit: true
    )
  end

  def success_rate
    return 0 if task_count.zero?

    (success_count.to_f / task_count * 100).round(2)
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = name.parameterize
    self.slug = base_slug

    counter = 1
    while CommunityAgent.exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def unique_agent_registration
    existing = CommunityAgent.where(agent_id: agent_id)
                             .where.not(id: id)
                             .where(status: %w[pending active])
                             .exists?

    if existing
      errors.add(:agent, "is already registered in the community")
    end
  end

  def link_agent_card
    return if agent_card.present?
    return unless agent.agent_card.present?

    update!(agent_card: agent.agent_card)
  end
end
