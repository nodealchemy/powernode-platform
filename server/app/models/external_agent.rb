# frozen_string_literal: true

# ExternalAgent - Represents an external A2A-compliant agent
# Used for discovering and communicating with agents from other platforms
class ExternalAgent < ApplicationRecord
  # === Constants ===
  STATUSES = %w[active inactive error unreachable].freeze
  HEALTH_STATUSES = %w[healthy degraded unhealthy unknown].freeze

  # === Associations ===
  belongs_to :account
  belongs_to :created_by, class_name: "User", optional: true
  has_many :a2a_tasks, class_name: "Ai::A2aTask", foreign_key: :to_agent_id, dependent: :nullify

  # === Validations ===
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :agent_card_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, inclusion: { in: STATUSES }
  validates :slug, uniqueness: true, allow_nil: true

  # === Callbacks ===
  before_validation :generate_slug, on: :create
  after_create :fetch_agent_card_async

  # === Scopes ===
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :healthy, -> { where(health_status: "healthy") }
  scope :needs_health_check, -> { where("last_health_check < ? OR last_health_check IS NULL", 5.minutes.ago) }
  scope :with_skill, ->(skill) { where("skills @> ?", [ skill ].to_json) }
  scope :with_capability, ->(cap) { where("capabilities ? ?", cap) }
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }

  # === Encryption ===
  encrypts :auth_token_encrypted

  # === Instance Methods ===

  # Fetch and cache the agent card from the remote URL
  def fetch_agent_card!
    response = A2a::Client::AgentDiscovery.fetch_card(agent_card_url)

    if response[:success]
      update!(
        cached_card: response[:card],
        card_cached_at: Time.current,
        card_version: response[:card]["version"],
        skills: extract_skills(response[:card]),
        capabilities: extract_capabilities(response[:card]),
        health_status: "healthy",
        last_health_check: Time.current
      )
      true
    else
      update!(
        health_status: "unhealthy",
        health_details: { error: response[:error] },
        last_health_check: Time.current
      )
      false
    end
  rescue StandardError => e
    update!(
      status: "error",
      health_status: "unhealthy",
      health_details: { error: e.message, backtrace: e.backtrace&.first(3) },
      last_health_check: Time.current
    )
    false
  end

  # Check health of the external agent
  def health_check!
    result = A2a::Client::AgentDiscovery.health_check(agent_card_url)

    update!(
      last_health_check: Time.current,
      health_status: result[:healthy] ? "healthy" : "unhealthy",
      health_details: result
    )

    result[:healthy]
  end

  # Get the A2A-compliant agent card
  def to_a2a_json
    return cached_card if cached_card.present? && card_fresh?

    fetch_agent_card!
    cached_card
  end

  # Check if cached card is still fresh
  def card_fresh?
    card_cached_at.present? && card_cached_at > 1.hour.ago
  end

  # Get skills list
  def skills_list
    (skills || []).map { |s| s.is_a?(Hash) ? s["id"] || s["name"] : s }
  end

  # Check if agent has a specific skill
  def has_skill?(skill_id)
    skills_list.include?(skill_id)
  end

  # Summary for listings
  def summary
    {
      id: id,
      name: name,
      description: description,
      agent_card_url: agent_card_url,
      status: status,
      health_status: health_status,
      skills: skills_list,
      task_count: task_count,
      success_rate: success_rate,
      avg_response_time_ms: avg_response_time_ms
    }
  end

  # Calculate success rate
  def success_rate
    return 0 if task_count.zero?
    (success_count.to_f / task_count * 100).round(2)
  end

  # Record task result for metrics
  def record_task_result!(success:, response_time_ms: nil)
    increment!(:task_count)

    if success
      increment!(:success_count)
    else
      increment!(:failure_count)
    end

    if response_time_ms.present?
      # Update rolling average
      new_avg = if avg_response_time_ms.nil?
                  response_time_ms
      else
                  (avg_response_time_ms * (task_count - 1) + response_time_ms) / task_count
      end
      update_column(:avg_response_time_ms, new_avg.round(2))
    end
  end

  private

  def generate_slug
    return if slug.present?
    base_slug = name&.parameterize
    return unless base_slug

    self.slug = base_slug
    counter = 1
    while ExternalAgent.exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def fetch_agent_card_async
    ExternalAgentCardFetchJob.perform_later(id)
  end

  def extract_skills(card)
    (card["skills"] || []).map do |skill|
      {
        "id" => skill["id"],
        "name" => skill["name"],
        "description" => skill["description"],
        "tags" => skill["tags"] || []
      }
    end
  end

  def extract_capabilities(card)
    card["capabilities"] || {}
  end
end
