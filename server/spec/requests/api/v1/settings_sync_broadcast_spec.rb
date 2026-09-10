# frozen_string_literal: true

require 'rails_helper'

# IMP-01a04dac-1083 — the settings half. SettingsController ships the saving
# user's OWN preferences to "all user's sessions" (its comment), but it
# published to the ACCOUNT stream, so every coworker's open ProfilePage merged
# the payload into its own form state and, for a theme change, called setTheme —
# switching another person's theme and preloading their form with foreign
# settings a subsequent save would persist.
#
# Each isolation example also asserts the save SUCCEEDED: a failed update
# broadcasts nothing, which would satisfy `not_to have_broadcasted_to` for the
# wrong reason.
RSpec.describe 'Api::V1::Settings sync broadcast', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let!(:coworker) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:account_stream) { "account_#{account.id}" }

  def user_stream(u) = "notifications:user:#{u.id}"

  {
    'preferences' => [ '/api/v1/settings/preferences', { preferences: { theme: 'dark' } }, 'preferences_updated' ],
    'notification preferences' => [ '/api/v1/settings/notifications',
                                    { notifications: { marketing_emails: true } }, 'notifications_updated' ]
  }.each do |label, (path, params, event)|
    describe "saving #{label}" do
      it "syncs the save to the saver's own sessions" do
        expect {
          put path, params: params, headers: headers, as: :json
        }.to have_broadcasted_to(user_stream(user)).with(hash_including(type: event))
        expect(response).to have_http_status(:ok)
      end

      it 'does not reach the account stream every coworker listens on' do
        expect {
          put path, params: params, headers: headers, as: :json
        }.not_to have_broadcasted_to(account_stream)
        expect(response).to have_http_status(:ok)
      end

      it 'does not reach a same-account coworker' do
        expect {
          put path, params: params, headers: headers, as: :json
        }.not_to have_broadcasted_to(user_stream(coworker))
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
