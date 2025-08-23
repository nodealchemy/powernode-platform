class PasswordHistory < ApplicationRecord
  belongs_to :user

  # Validations
  validates :password_digest, presence: true
  validates :created_at, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  # Class methods
  def self.add_for_user(user, password_digest)
    create!(
      user: user,
      password_digest: password_digest,
      created_at: Time.current
    )
  end

  def self.cleanup_old_entries(user, keep_count = 12)
    old_entries = for_user(user)
                    .recent
                    .offset(keep_count)

    old_entries.destroy_all
  end

  def self.password_recently_used?(user, password)
    return false unless user.persisted?

    # Get the 12 most recent password history entries, ordered by created_at desc
    recent_histories = for_user(user)
                        .recent
                        .limit(12)
                        .to_a  # Load into array to ensure proper ordering

    # Check each history entry with early termination
    recent_histories.each do |history|
      return true if BCrypt::Password.new(history.password_digest) == password
    end

    false
  end
end
