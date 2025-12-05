# frozen_string_literal: true

class AddTestTrackingToAiProviderCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_provider_credentials, :last_test_at, :datetime
    add_column :ai_provider_credentials, :last_test_status, :string
    add_column :ai_provider_credentials, :success_count, :integer, default: 0, null: false
    add_column :ai_provider_credentials, :failure_count, :integer, default: 0, null: false

    # Add index for querying by test status
    add_index :ai_provider_credentials, :last_test_status
  end
end
