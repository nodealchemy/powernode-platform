# frozen_string_literal: true

module System
  class RegionVolumeType < BaseRecord
    include System::Base

    # === Associations ===
    belongs_to :provider_region, class_name: 'System::ProviderRegion'
    belongs_to :volume_type, class_name: 'System::ProviderVolumeType'

    # Delegate account access through region
    delegate :account, to: :provider_region
    delegate :account_id, to: :provider_region
    delegate :provider, to: :provider_region

    # === Validations ===
    validates :provider_region_id, uniqueness: { scope: :volume_type_id, message: 'already has this volume type' }

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }

    # === Methods ===
    def region_name
      provider_region&.name
    end

    def volume_type_name
      volume_type&.name
    end
  end
end
