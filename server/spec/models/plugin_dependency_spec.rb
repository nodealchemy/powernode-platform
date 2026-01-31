# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PluginDependency, type: :model do
  # NOTE: The plugin_dependencies table was dropped in migration
  # 20260111072313_drop_deprecated_app_and_plugin_tables.
  # The model file remains but the backing table no longer exists.
  # Only class-level checks that do not require database access are tested.

  it 'is defined as an ActiveRecord model' do
    expect(PluginDependency).to be < ApplicationRecord
  end
end
