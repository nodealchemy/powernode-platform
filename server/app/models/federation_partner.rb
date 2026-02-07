# frozen_string_literal: true

class FederationPartner < ApplicationRecord
  # Concerns
  include Auditable

  # Constants
  STATUSES = %w[pending active suspended revoked].freeze
  MIN_TRUST_LEVEL = 1
  MAX_TRUST_LEVEL = 5

  # Aliases for API compatibility
  alias_attribute :organization_name, :name
  alias_attribute :allowed_skills, :allowed_capabilities

  # Associations
  belongs_to :account
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  has_many :a2a_tasks, class_name: "Ai::A2aTask", foreign_key: "federation_partner_id"

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :organization_id, presence: true, uniqueness: true
  validates :endpoint_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :trust_level, numericality: { in: MIN_TRUST_LEVEL..MAX_TRUST_LEVEL }
  validates :max_requests_per_hour, numericality: { greater_than: 0 }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :trusted, -> { where("trust_level >= ?", 3) }
  scope :recently_active, -> { where("last_request_at > ?", 24.hours.ago) }
  scope :verified, -> { where(status: "active").where.not(approved_at: nil) }

  # Alias for controller compatibility (initiated_by -> created_by)
  # For attributes, use alias_attribute; for associations, define wrapper methods
  def initiated_by
    created_by
  end

  def initiated_by=(value)
    self.created_by = value
  end

  def verified_at
    approved_at
  end

  def verified_at=(value)
    self.approved_at = value
  end

  # Callbacks
  before_create :generate_federation_token

  # Status checks
  def active?
    status == "active"
  end

  def pending?
    status == "pending"
  end

  def suspended?
    status == "suspended"
  end

  # Lifecycle
  def approve!(user)
    update!(
      status: "active",
      approved_by: user,
      approved_at: Time.current
    )
  end

  def suspend!(reason: nil)
    update!(
      status: "suspended",
      tls_config: tls_config.merge("suspension_reason" => reason)
    )
  end

  def revoke!
    update!(status: "revoked")
  end

  def reactivate!
    update!(status: "active") if suspended?
  end

  # Check if partner is verified and active
  def verified?
    active? && approved_at.present?
  end

  # Verify connectivity to partner's A2A endpoint
  def verify_connection!
    uri = URI.parse("#{endpoint_url}/.well-known/a2a")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"

    response = http.request(request)

    if response.code.to_i == 200
      update!(approved_at: Time.current)
      { success: true }
    else
      { success: false, error: "HTTP #{response.code}: #{response.message}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # Fetch agents from partner with optional filtering
  def fetch_agents(category: nil, query: nil)
    return { success: false, error: "Partner not verified" } unless verified?

    result = fetch_agent_catalog
    return result unless result[:success]

    agents = result[:agents] || []

    if category.present?
      agents = agents.select { |a| a["category"] == category }
    end

    if query.present?
      query_downcase = query.downcase
      agents = agents.select do |a|
        a["name"]&.downcase&.include?(query_downcase) ||
          a["description"]&.downcase&.include?(query_downcase)
      end
    end

    { success: true, agents: agents }
  end

  # Extended partner information for API responses
  def partner_details
    partner_summary.merge(
      contact_email: tls_config&.dig("contact_email"),
      tls_config: (tls_config || {}).except("ca_cert", "contact_email", "mtls_certificate"),
      auto_approve_agents: auto_approve_agents,
      allowed_skills: allowed_skills,
      request_count: request_count,
      last_request_at: last_request_at,
      verified_at: approved_at,
      created_by_id: created_by_id
    )
  end

  # Trust management
  def increase_trust!
    new_level = [ trust_level + 1, MAX_TRUST_LEVEL ].min
    update!(trust_level: new_level)
  end

  def decrease_trust!
    new_level = [ trust_level - 1, MIN_TRUST_LEVEL ].max
    update!(trust_level: new_level)

    suspend!(reason: "Trust level too low") if new_level == MIN_TRUST_LEVEL
  end

  # Rate limiting
  def rate_limit_key
    "federation:#{id}:rate"
  end

  def rate_limited?
    count = Rails.cache.read(rate_limit_key).to_i
    count >= max_requests_per_hour
  end

  def increment_request_count!
    key = rate_limit_key
    count = Rails.cache.read(key).to_i
    Rails.cache.write(key, count + 1, expires_in: 1.hour)
    increment!(:request_count)
    touch(:last_request_at)
  end

  # Token validation
  def valid_token?(token)
    return false if federation_token_hash.blank? || token.blank?

    BCrypt::Password.new(federation_token_hash) == token
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def regenerate_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(federation_token_hash: BCrypt::Password.create(token))
    token
  end

  # Summary for list views
  def partner_summary
    {
      id: id,
      name: name,
      organization_id: organization_id,
      endpoint_url: endpoint_url,
      status: status,
      trust_level: trust_level,
      agent_count: agent_count,
      last_sync_at: last_sync_at,
      approved_at: approved_at
    }
  end

  # Sync agents from federation partner
  # Fetches agent catalog from partner's A2A discovery endpoint
  # and creates/updates CommunityAgent records
  def sync_agents!
    return { success: false, error: "Partner not active" } unless active?
    return { success: false, error: "Rate limited" } if rate_limited?

    Rails.logger.info("FederationPartner: Starting sync for #{name} (#{organization_id})")

    begin
      # Fetch agent catalog from partner
      response = fetch_agent_catalog

      unless response[:success]
        decrease_trust!
        return { success: false, error: response[:error] }
      end

      agents_data = response[:agents] || []
      synced_count = 0
      error_count = 0

      agents_data.each do |agent_data|
        result = sync_agent(agent_data)
        if result[:success]
          synced_count += 1
        else
          error_count += 1
          Rails.logger.warn("Failed to sync agent: #{agent_data['name']}: #{result[:error]}")
        end
      end

      # Update sync metadata
      update!(
        agent_count: synced_count,
        last_sync_at: Time.current
      )

      increment_request_count!

      Rails.logger.info(
        "FederationPartner: Sync completed for #{name} - " \
        "synced: #{synced_count}, errors: #{error_count}"
      )

      { success: true, synced: synced_count, errors: error_count }
    rescue StandardError => e
      Rails.logger.error("FederationPartner: Sync failed for #{name}: #{e.message}")
      decrease_trust!
      { success: false, error: e.message }
    end
  end

  private

  # Fetch agent catalog from partner's discovery endpoint
  def fetch_agent_catalog
    uri = URI.parse("#{endpoint_url}/.well-known/a2a/agents")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    # Apply TLS configuration if provided
    if tls_config["ca_cert"].present?
      http.ca_file = tls_config["ca_cert"]
    end
    if tls_config["verify_mode"].present?
      http.verify_mode = tls_config["verify_mode"] == "none" ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
    end

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["X-Federation-Organization"] = organization_id
    request["Authorization"] = "Bearer #{generate_federation_jwt}" if federation_token_hash.present?

    response = http.request(request)

    if response.code.to_i == 200
      data = JSON.parse(response.body)
      { success: true, agents: data["agents"] || data }
    else
      { success: false, error: "HTTP #{response.code}: #{response.message}" }
    end
  rescue JSON::ParserError => e
    { success: false, error: "Invalid JSON response: #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Request failed: #{e.message}" }
  end

  # Sync a single agent from partner data
  def sync_agent(agent_data)
    # Validate required fields
    return { success: false, error: "Missing agent name" } if agent_data["name"].blank?

    # Build unique federation key for this agent
    federation_key = "#{organization_id}:#{agent_data['id'] || agent_data['name'].parameterize}"

    # Find or initialize community agent
    community_agent = CommunityAgent.find_or_initialize_by(federation_key: federation_key)

    # Update agent data
    community_agent.assign_attributes(
      name: agent_data["name"],
      slug: "#{organization_id.parameterize}-#{agent_data['name'].parameterize}",
      description: agent_data["description"],
      long_description: agent_data["long_description"],
      endpoint_url: build_agent_endpoint(agent_data),
      category: agent_data["category"] || "general",
      tags: agent_data["tags"] || [],
      visibility: determine_visibility(agent_data),
      status: "active",
      protocol_version: agent_data["protocol_version"] || "0.3",
      capabilities: agent_data["capabilities"] || {},
      federated: true,
      federation_partner_id: id,
      federation_metadata: {
        source_agent_id: agent_data["id"],
        synced_at: Time.current.iso8601,
        original_endpoint: agent_data["endpoint_url"]
      }
    )

    if community_agent.save
      { success: true, community_agent_id: community_agent.id }
    else
      { success: false, error: community_agent.errors.full_messages.join(", ") }
    end
  end

  # Build agent endpoint URL
  def build_agent_endpoint(agent_data)
    if agent_data["endpoint_url"].present?
      agent_data["endpoint_url"]
    elsif agent_data["id"].present?
      "#{endpoint_url}/a2a/agents/#{agent_data['id']}"
    else
      "#{endpoint_url}/a2a/agents/#{agent_data['name'].parameterize}"
    end
  end

  # Determine visibility based on trust level and agent data
  def determine_visibility(agent_data)
    # Auto-approve based on trust level and configuration
    if trust_level >= 3 || auto_approve_agents
      agent_data["visibility"] || "public"
    else
      "unlisted"
    end
  end

  # Generate a short-lived JWT for federation authentication
  def generate_federation_jwt
    payload = {
      iss: "powernode",
      sub: organization_id,
      aud: endpoint_url,
      iat: Time.current.to_i,
      exp: 5.minutes.from_now.to_i
    }

    # Use account's JWT secret or global federation secret
    secret = account.jwt_secret || Rails.application.credentials.federation_secret
    JWT.encode(payload, secret, "HS256")
  rescue StandardError
    nil
  end

  private

  def generate_federation_token
    return if federation_token_hash.present?

    # Generate initial token - must be saved by admin
    token = SecureRandom.urlsafe_base64(32)
    self.federation_token_hash = BCrypt::Password.create(token)
    # Note: Token should be displayed once and saved securely
  end
end
