# frozen_string_literal: true

module System
  class ProviderVolumeSnapshot < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[pending creating completed error deleting deleted].freeze

    # === Associations ===
    belongs_to :account
    belongs_to :volume, class_name: 'System::ProviderVolume', optional: true

    has_many :operations, class_name: 'System::Operation', as: :operable, dependent: :destroy

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :size_gb, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :progress, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # === Scopes ===
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { by_status('pending') }
    scope :creating, -> { by_status('creating') }
    scope :completed, -> { by_status('completed') }
    scope :errored, -> { by_status('error') }
    scope :deleting, -> { by_status('deleting') }
    scope :deleted, -> { by_status('deleted') }

    scope :encrypted_snapshots, -> { where(encrypted: true) }
    scope :unencrypted_snapshots, -> { where(encrypted: false) }
    scope :by_name, -> { order(name: :asc) }
    scope :by_size, -> { order(size_gb: :desc) }
    scope :recent, -> { order(created_at: :desc) }

    # === Status Predicates ===
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # === Methods ===
    def can_restore?
      completed?
    end

    def can_delete?
      completed? || error?
    end

    def in_progress?
      pending? || creating?
    end

    def finished?
      completed? || error? || deleted?
    end

    def update_progress!(new_progress)
      update!(progress: new_progress.clamp(0, 100))
    end

    def provider
      volume&.provider
    end

    def provider_region
      volume&.provider_region
    end
  end
end
