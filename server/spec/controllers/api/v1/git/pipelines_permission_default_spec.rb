# frozen_string_literal: true

require 'rails_helper'

# PipelinesController#validate_permissions maps each action to a permission.
# An action the map does not name must be REFUSED, not waved through: a new
# action (or a deleted one's route left behind) would otherwise run with no
# permission check at all.
RSpec.describe Api::V1::Git::PipelinesController, type: :controller do
  controller(described_class) do
    def unmapped
      render_success({ reached: true })
    end
  end

  let(:account) { create(:account) }
  let(:user_with_every_pipeline_permission) do
    create(:user, account: account, permissions: %w[
      git.pipelines.read git.pipelines.trigger git.pipelines.cancel git.pipelines.logs
    ])
  end

  before do
    routes.draw { get "unmapped" => "api/v1/git/pipelines#unmapped" }
    @request.headers['Accept'] = 'application/json'
    sign_in user_with_every_pipeline_permission
  end

  it 'refuses an action the permission map does not name' do
    get :unmapped

    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('reached')
  end
end
