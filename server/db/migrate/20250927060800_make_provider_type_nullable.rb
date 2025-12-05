# frozen_string_literal: true

class MakeProviderTypeNullable < ActiveRecord::Migration[8.0]
  def up
    change_column_null :ai_providers, :provider_type, true
  end

  def down
    # Update any NULL provider_types to 'custom' before adding NOT NULL constraint back
    AiProvider.where(provider_type: nil).update_all(provider_type: 'custom')
    change_column_null :ai_providers, :provider_type, false
  end
end