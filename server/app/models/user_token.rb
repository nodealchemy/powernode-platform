# frozen_string_literal: true

class UserToken < ApplicationRecord
  belongs_to :user

  # Token types
  TOKEN_TYPES = %w[access refresh api_key 2fa impersonation].freeze

  # Default expiration times
  EXPIRATION_TIMES = {
    access: 24.hours,
    refresh: 30.days,
    api_key: 1.year,
    "2fa" => 10.minutes,
    impersonation: 8.hours
  }.freeze

  # Validations
  validates :token_digest, presence: true, uniqueness: true
  validates :token_type, presence: true, inclusion: { in: TOKEN_TYPES }
  validates :expires_at, presence: true
  validates :name, length: { maximum: 100 }
  validates :scopes, length: { maximum: 500 }

  # Serialization. `permissions` is NOT an authorization input — see
  # #has_permission?. Nothing writes it and nothing in production reads it any
  # more; the coder is retained only so the surviving rows still present as the
  # Array they were written as, for anyone inspecting the table or writing a
  # migration to drop it. Do not read it as a grant.
  serialize :permissions, coder: JSON

  # Scopes
  scope :active, -> { where(revoked: false).where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :revoked, -> { where(revoked: true) }
  scope :by_type, ->(type) { where(token_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_default_expiration, if: :new_record?
  after_create :cleanup_expired_tokens

  # Class methods
  def self.generate_token
    SecureRandom.urlsafe_base64(48)
  end

  # NO `permissions:` kwarg. It used to exist and defaulted to
  # `user.permission_names`, so every token was stamped with the user's FULL
  # permission set as of its mint, and #has_permission? then answered from that
  # stamp instead of the database. Removed rather than left ignored: a kwarg that
  # silently discards its argument invites a caller to believe it narrows a token.
  # It never did — nobody ever passed a narrowed set (the sole production mint
  # omitted it, and #refresh! only copied the stamp forward), so no scoping
  # behaviour is lost here. Reintroducing a genuinely scoped token means a
  # deliberate design, not restoring this parameter; see #has_permission?.
  def self.create_token_for_user(user, type: "access", name: nil, scopes: nil, expires_in: nil)
    token = generate_token
    token_digest = Digest::SHA256.hexdigest(token)

    expires_at = expires_in ? expires_in.from_now : EXPIRATION_TIMES[type.to_sym].from_now

    user_token = create!(
      user: user,
      token_digest: token_digest,
      token_type: type,
      name: name,
      scopes: scopes,
      expires_at: expires_at
    )

    # Return both the token and the record
    { token: token, user_token: user_token }
  end

  def self.find_by_token(token)
    return nil if token.blank?

    token_digest = Digest::SHA256.hexdigest(token)
    active.find_by(token_digest: token_digest)
  end

  def self.authenticate(token)
    user_token = find_by_token(token)
    return nil unless user_token

    # Update last used information
    user_token.touch_last_used!

    user_token
  end

  def self.cleanup_expired
    expired.delete_all
    revoked.where("revoked_at < ?", 7.days.ago).delete_all
  end

  # Instance methods
  def active?
    !revoked? && !expired?
  end

  def expired?
    expires_at <= Time.current
  end

  def revoke!(reason: "manual")
    update!(
      revoked: true,
      revoked_at: Time.current,
      revoked_reason: reason
    )
  end

  def touch_last_used!(ip: nil, user_agent: nil)
    update_columns(
      last_used_at: Time.current,
      last_used_ip: ip,
      user_agent: user_agent&.truncate(500)
    )
  end

  def refresh!
    return nil unless token_type == "refresh" && active?

    # The successor deliberately carries NO permission snapshot. This call used to
    # pass `permissions: permissions`, copying the stamp into every successor, so
    # a stamp outlived the token it was taken for and nothing bounded how long a
    # revocation could go unseen. Latent rather than observed — this method has no
    # caller outside its spec — but it is what made the staleness unbounded.
    UserToken.create_token_for_user(user, type: "access")
  end

  def scope_list
    return [] if scopes.blank?
    scopes.split(",").map(&:strip)
  end

  def has_scope?(scope)
    scope_list.include?(scope.to_s)
  end

  # Resolved LIVE from the user on every call, so a revocation takes effect
  # immediately for an already-issued token.
  #
  # There is NO token-borne short-circuit. Two used to read the `permissions`
  # column — a stamp of the user's full permission set taken at mint time:
  #
  #   return true if permissions&.include?("system.admin")
  #   return permissions&.include?(permission_name) if permissions.present?
  #
  # The first answered true for ANY permission off a stale admin stamp. The second
  # answered the stamp VERBATIM, so it had a false-NEGATIVE direction too: a
  # permission granted after the mint was invisible to the token. Because the
  # column was persisted, reloading did not clear it, and #refresh! copied it into
  # each successor, so neither error would have been bounded by a token lifetime.
  #
  # LATENT, not exploited: no caller of this method is findable in server/,
  # extensions/ (including extensions/private) or worker/ — the receiver of every
  # .has_permission? call in the tree is a user, role, delegation or worker, never
  # a token — and the one call site was deleted in IMP-a18f5a8ed393. In particular
  # an impersonation UserToken is NOT an authorization principal: the arm that
  # authenticates one sets current_user to the impersonated User and every gate
  # resolves through that, while the token itself is assigned and never read. A
  # literal-name grep cannot see symbol or composed dispatch, so treat that as
  # strong evidence of no caller, not proof.
  #
  # Deleted rather than intersected (`stamp & live`). Intersection would NOT have
  # been a no-op today: the stamp is the full set as of the MINT, not as of now,
  # so it would have preserved the false-negative half — a permission granted
  # after the mint stays denied for the token's life. It is also an affordance
  # nothing uses; no caller ever passed a narrowed set, so there is no scoped
  # token for a deletion to break. With no reader left, a future writer of the
  # column cannot reopen or close anything by accident.
  #
  # Do not reintroduce a stamp as an optimisation. A real scoped token needs a
  # mint-time surface for narrowing AND an invalidation story that answers what a
  # token minted BEFORE a narrowing may do — neither exists. Same shape as the JWT
  # `permissions` claim deleted in IMP-4b5fffbf5421. Pinned by
  # spec/models/user_token_permission_snapshot_spec.rb.
  def has_permission?(permission_name)
    user.has_permission?(permission_name)
  end

  def display_name
    name.present? ? name : "#{token_type.humanize} Token"
  end

  def masked_token
    return nil unless token_digest.present?

    # Show first 8 and last 4 characters of digest
    digest_preview = token_digest[0..7] + "..." + token_digest[-4..-1]
    "tok_#{digest_preview}"
  end

  private

  def set_default_expiration
    return if expires_at.present?

    self.expires_at = EXPIRATION_TIMES[token_type.to_sym]&.from_now || 24.hours.from_now
  end

  def cleanup_expired_tokens
    # Clean up expired tokens for this user periodically
    return unless rand < 0.1 # 10% chance to run cleanup

    self.class.where(user: user).expired.limit(100).delete_all
  end
end
