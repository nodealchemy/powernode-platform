# frozen_string_literal: true

module System
  class NodeScript < BaseRecord
    include System::Base

    # Constants
    VARIETIES = %w[build init sync custom].freeze

    # Associations
    belongs_to :account

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :variety, presence: true, inclusion: { in: VARIETIES }

    # Scopes
    scope :build_scripts, -> { where(variety: 'build') }
    scope :init_scripts, -> { where(variety: 'init') }
    scope :sync_scripts, -> { where(variety: 'sync') }
    scope :custom_scripts, -> { where(variety: 'custom') }
  end
end
