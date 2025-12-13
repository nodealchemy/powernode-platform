# frozen_string_literal: true

class BlacklistedToken < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :valid, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  def self.blacklisted?(token)
    valid.exists?(token: token)
  end

  def self.cleanup_expired
    expired.delete_all
  end

  def expired?
    expires_at <= Time.current
  end
end
