# frozen_string_literal: true

class OauthApplication < ApplicationRecord
  include Doorkeeper::Orm::ActiveRecord::Mixins::Application

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================

  belongs_to :owner, polymorphic: true, optional: true

  has_many :access_tokens,
           class_name: 'Doorkeeper::AccessToken',
           foreign_key: :application_id,
           dependent: :delete_all

  has_many :access_grants,
           class_name: 'Doorkeeper::AccessGrant',
           foreign_key: :application_id,
           dependent: :delete_all

  # =========================================================================
  # VALIDATIONS
  # =========================================================================

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  validates :status, presence: true, inclusion: { in: %w[active suspended revoked] }
  validates :rate_limit_tier, inclusion: { in: %w[standard premium enterprise unlimited] }

  # =========================================================================
  # SCOPES
  # =========================================================================

  scope :active, -> { where(status: 'active') }
  scope :suspended, -> { where(status: 'suspended') }
  scope :trusted, -> { where(trusted: true) }
  scope :machine_clients, -> { where(machine_client: true) }
  scope :for_owner, ->(owner) { where(owner: owner) }
  scope :recently_used, -> {
    joins(:access_tokens)
      .where('oauth_access_tokens.created_at > ?', 30.days.ago)
      .distinct
  }

  # =========================================================================
  # CALLBACKS
  # =========================================================================

  before_validation :set_defaults, on: :create

  # =========================================================================
  # INSTANCE METHODS
  # =========================================================================

  def active?
    status == 'active'
  end

  def suspended?
    status == 'suspended'
  end

  def revoked?
    status == 'revoked'
  end

  def suspend!(reason: nil)
    update!(
      status: 'suspended',
      metadata: metadata.merge('suspension_reason' => reason, 'suspended_at' => Time.current.iso8601)
    )
    revoke_all_tokens!
  end

  def revoke!
    update!(
      status: 'revoked',
      metadata: metadata.merge('revoked_at' => Time.current.iso8601)
    )
    revoke_all_tokens!
  end

  def activate!
    update!(
      status: 'active',
      metadata: metadata.except('suspension_reason', 'suspended_at')
    )
  end

  def revoke_all_tokens!
    access_tokens.update_all(revoked_at: Time.current)
    access_grants.update_all(revoked_at: Time.current)
  end

  def regenerate_secret!
    self.secret = Doorkeeper.config.application_secret_generator.call
    save!
    secret
  end

  def active_tokens_count
    access_tokens.where(revoked_at: nil).where('expires_in IS NULL OR created_at + (expires_in * interval \'1 second\') > ?', Time.current).count
  end

  def last_used_at
    access_tokens.maximum(:created_at)
  end

  def total_requests_count
    metadata['total_requests'] || 0
  end

  def rate_limit
    case rate_limit_tier
    when 'unlimited' then nil
    when 'enterprise' then 10_000
    when 'premium' then 5_000
    else 1_000
    end
  end

  def scopes_list
    scopes.to_s.split(' ').map(&:strip).reject(&:blank?)
  end

  def has_scope?(scope)
    scopes_list.include?(scope.to_s)
  end

  def as_json(options = {})
    {
      id: id,
      name: name,
      description: description,
      uid: uid,
      redirect_uri: redirect_uri,
      scopes: scopes_list,
      confidential: confidential,
      trusted: trusted,
      machine_client: machine_client,
      status: status,
      rate_limit_tier: rate_limit_tier,
      rate_limit: rate_limit,
      active_tokens_count: active_tokens_count,
      last_used_at: last_used_at,
      created_at: created_at,
      updated_at: updated_at
    }.merge(options[:include_secret] ? { secret: secret } : {})
  end

  private

  def set_defaults
    self.status ||= 'active'
    self.rate_limit_tier ||= 'standard'
    self.metadata ||= {}
  end
end
