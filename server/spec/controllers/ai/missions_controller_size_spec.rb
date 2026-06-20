# frozen_string_literal: true

require 'rails_helper'

# Guard for IMP-805c34a12cb1: Api::V1::Ai::MissionsController exceeded the 300-line
# limit (611 lines). Its action groups were extracted into Ai::Missions:: concern
# modules (lifecycle, operations, plan composition). Behavior is covered by
# spec/requests/api/v1/ai/missions_spec.rb (unchanged, must stay green).
RSpec.describe 'Ai::MissionsController size budget' do
  it 'keeps the controller under the 300-line limit (action groups live in concerns)' do
    path = Rails.root.join('app/controllers/api/v1/ai/missions_controller.rb')
    line_count = File.readlines(path).count
    expect(line_count).to be <= 300
  end
end
