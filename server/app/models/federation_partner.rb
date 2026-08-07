# frozen_string_literal: true

require "resolv"
require "ipaddr"

class FederationPartner < ApplicationRecord
  # Concerns
  include Auditable

  # SSRF guard: an outbound cross-plane call must never reach an internal address,
  # even if an operator/tenant set endpoint_url to one. Checked against the
  # RESOLVED host so a public hostname pointing at a private IP is caught too.
  BLOCKED_OUTBOUND_RANGES = [
    IPAddr.new("0.0.0.0/8"), IPAddr.new("127.0.0.0/8"), IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"), IPAddr.new("192.168.0.0/16"), IPAddr.new("169.254.0.0/16"),
    IPAddr.new("::1/128"), IPAddr.new("fc00::/7"), IPAddr.new("fe80::/10")
  ].freeze

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
  validate :allowed_capabilities_not_overbroad

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :trusted, -> { where("trust_level >= ?", 3) }
  scope :recently_active, -> { where("last_request_at > ?", 24.hours.ago) }
  scope :verified, -> { where(status: "active").where.not(approved_at: nil) }

  # Resolve an INBOUND cross-plane MCP caller: an active partner whose bcrypt
  # federation token matches, that is not over its rate limit. Pure lookup +
  # verify (no side effects); the auth arm records the request. Fail-closed:
  # nil on any missing/blank/invalid/suspended/rate-limited case.
  def self.for_inbound(organization_id:, token:)
    return nil if organization_id.blank? || token.blank?

    partner = active.find_by(organization_id: organization_id)
    return nil unless partner&.valid_token?(token)
    return nil if partner.rate_limited?

    partner
  end

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

  # OUTBOUND credential: the plaintext shared secret THIS plane presents when it
  # calls the partner. `federation_token_hash` is one-way (inbound verify only),
  # so the outbound secret is stored separately, encrypted at rest. Mirrors
  # McpServer's OAuth-token handling.
  def outbound_token
    return nil if outbound_token_encrypted.blank?

    Security::CredentialEncryptionService.decrypt_value(outbound_token_encrypted, namespace: "federation")
  rescue Security::CredentialEncryptionService::DecryptionError => e
    Rails.logger.error("Failed to decrypt outbound federation token for partner #{id}: #{e.message}")
    nil
  end

  def outbound_token=(value)
    self.outbound_token_encrypted =
      value.blank? ? nil : Security::CredentialEncryptionService.encrypt_value(value, namespace: "federation")
  end

  # The organization id THIS plane is known by on the partner — presented in the
  # X-Federation-Organization header so the partner finds its reciprocal row.
  # Non-secret; lives in tls_config alongside the other connection config.
  def presented_organization_id
    tls_config&.dig("presented_organization_id")
  end

  # OUTBOUND cross-plane MCP call: proxy a single tool invocation to the partner's
  # MCP endpoint over JSON-RPC. Mirrors #fetch_agent_catalog's HTTP/TLS shape.
  # Returns { success:, result: } or { success: false, error:, code? }.
  def invoke_remote_tool(tool:, arguments: {})
    return { success: false, error: "Partner not active" } unless active?
    return { success: false, error: "Rate limited" } if rate_limited?

    token = outbound_token
    return { success: false, error: "No outbound federation token configured" } if token.blank?

    presented = presented_organization_id
    return { success: false, error: "No presented_organization_id configured" } if presented.blank?

    uri = URI.parse("#{endpoint_url}/api/v1/mcp/message")
    return { success: false, error: "Refusing outbound call to a non-public endpoint host" } unless self.class.public_outbound_host?(uri.host)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30
    if tls_config["ca_cert"].present?
      http.ca_file = tls_config["ca_cert"]
    end
    if tls_config["verify_mode"].present?
      http.verify_mode = tls_config["verify_mode"] == "none" ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
    end

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{token}"
    request["X-Federation-Organization"] = presented
    request.body = JSON.generate(
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      method: "tools/call",
      params: { name: tool.to_s, arguments: arguments || {} }
    )

    response = http.request(request)
    increment_request_count!

    if response.code.to_i == 200
      data = JSON.parse(response.body)
      if data["error"]
        { success: false, error: data.dig("error", "message") || "Remote error", code: data.dig("error", "code") }
      else
        { success: true, result: data["result"] }
      end
    else
      { success: false, error: "HTTP #{response.code}: #{response.message}" }
    end
  rescue JSON::ParserError => e
    { success: false, error: "Invalid JSON response: #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Request failed: #{e.message}" }
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

  # True only when EVERY resolved address for host is a routable public address.
  # Fail-closed: unresolvable or partially-private hosts are refused. (SSRF guard
  # for the new outbound MCP sink; the pre-existing discovery GETs should adopt
  # this too — tracked separately.)
  def self.public_outbound_host?(host)
    return false if host.blank?

    begin
      addresses = Resolv.getaddresses(host.to_s)
    rescue StandardError
      return false
    end
    return false if addresses.empty?

    addresses.all? do |addr|
      ip = begin
        IPAddr.new(addr)
      rescue StandardError
        nil
      end
      ip && BLOCKED_OUTBOUND_RANGES.none? { |range| range.include?(ip) }
    end
  end

  private

  # Reject allowed_capabilities patterns that would grant a remote peer nearly the
  # whole tool surface — a wildcard-only entry ("*", "**") or the platform-wide
  # glob ("platform.*"). Specific prefixes like "platform.system_list_*" are fine.
  def allowed_capabilities_not_overbroad
    Array(allowed_capabilities).each do |cap|
      normalized = cap.to_s.strip.downcase
      next if normalized.blank?

      stripped = normalized.delete("*").delete(".")
      overbroad = stripped.blank? || (stripped == "platform" && normalized.include?("*"))
      if overbroad
        errors.add(:allowed_capabilities, "is over-broad and would grant a peer nearly all tools: #{cap}")
      end
    end
  end

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

    # IMP-e0cb1dbbff7e — LOCAL ATTESTATIONS DO NOT SURVIVE AN IDENTITY SWAP.
    #
    # The row is keyed on federation_key, so a re-sync lands on the SAME record
    # and rewrites its behavioral identity from the remote payload — where it
    # is reached (endpoint_url) and what it claims to do (capabilities). The
    # local attestations (verified/verified_at/verified_by, reputation_score)
    # describe the thing that WAS there, and community_skills serves
    # verified-only results ordered by reputation, so a re-pointed row would be
    # preferentially selected on trust it never earned.
    #
    # Cleared only when the identity actually changes: a partner re-syncing
    # unchanged (or editing only its description) must not cost an operator
    # their verification, or routine syncs would silently erode the catalog.
    identity_swapped = community_agent.persisted? && federated_identity_changed?(
      community_agent, agent_data
    )

    # Update agent data
    community_agent.assign_attributes(
      name: agent_data["name"],
      slug: "#{organization_id.parameterize}-#{agent_data['name'].parameterize}",
      description: agent_data["description"],
      long_description: agent_data["long_description"],
      endpoint_url: build_agent_endpoint(agent_data),
      category: federated_category(agent_data["category"]),
      tags: agent_data["tags"] || [],
      visibility: determine_visibility(agent_data),
      status: "active",
      protocol_version: agent_data["protocol_version"] || "0.3",
      capabilities: agent_data["capabilities"] || {},
      federated: true,
      federation_partner_id: id,
      # A federated row carries no local Ai::Agent (see CommunityAgent
      # :local_row_requires_agent) but is still owned by THIS account, which is
      # what scopes it and what audit_account_via reads.
      owner_account_id: account_id,
      federation_metadata: {
        source_agent_id: agent_data["id"],
        synced_at: Time.current.iso8601,
        original_endpoint: agent_data["endpoint_url"]
      }
    )

    if identity_swapped
      community_agent.assign_attributes(
        verified: false, verified_at: nil, verified_by_id: nil,
        reputation_score: 0.0
      )
    end

    if community_agent.save
      { success: true, community_agent_id: community_agent.id,
        attestations_reset: identity_swapped }
    else
      { success: false, error: community_agent.errors.full_messages.join(", ") }
    end
  end

  # A partner's category vocabulary is its own; only CommunityAgent::CATEGORIES
  # are valid locally. This defaulted to "general", which is NOT in that list —
  # so every sync failed validation with "Category is not included in the list"
  # even once the columns existed. Unrecognized (and absent) categories land on
  # "custom", the catch-all, rather than inventing a mapping. (IMP-e0cb1dbbff7e)
  def federated_category(remote_category)
    return "custom" if remote_category.blank?

    CommunityAgent::CATEGORIES.include?(remote_category) ? remote_category : "custom"
  end

  # True when a re-sync would change WHERE the agent is reached or WHAT it
  # claims to do — the two facts a local verification was about. Description
  # and display churn deliberately do not count. (IMP-e0cb1dbbff7e)
  def federated_identity_changed?(community_agent, agent_data)
    endpoint_changed = community_agent.endpoint_url != build_agent_endpoint(agent_data)
    capabilities_changed =
      (community_agent.capabilities || {}).as_json != (agent_data["capabilities"] || {}).as_json

    endpoint_changed || capabilities_changed
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
