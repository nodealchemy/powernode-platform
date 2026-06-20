# frozen_string_literal: true

require 'rails_helper'

# Guard for IMP-17a39c7f5266: AdminSettingsController exceeded the 300-line limit
# (644 lines). Its action groups were extracted into AdminSettings:: concern
# modules (security config, infrastructure/vault, extensions). This guards against
# the controller re-accumulating bloat. Behavior is covered by
# spec/requests/api/v1/admin_settings_spec.rb (unchanged, must stay green).
RSpec.describe 'AdminSettingsController size budget' do
  it 'keeps the controller under the 300-line limit (logic lives in concerns/services)' do
    path = Rails.root.join('app/controllers/api/v1/admin_settings_controller.rb')
    line_count = File.readlines(path).count
    expect(line_count).to be <= 300
  end
end
