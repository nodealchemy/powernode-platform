# frozen_string_literal: true

require 'rails_helper'

# GET and PUT /api/v1/settings are the read and write halves of ONE resource:
# Api::V1::SettingsController#show builds the response from its own private
# serializers, and #update renders SettingsUpdateService's `result[:data]`
# straight through, which the service builds from ITS own copies of the same
# four serializers.
#
# Parity between the two sets was held by "kept in parity with ..." comments,
# and the existing settings_spec.rb only ever exercises GET — so nothing covered
# the write half. They had already drifted on the security section:
#
#   GET  security_settings -> 9 fields, two_factor_enabled from the live
#                             User#two_factor_enabled? predicate
#   PUT  security_settings -> 5 fields, two_factor_enabled hardcoded `false`
#
# meaning a user with 2FA genuinely enabled who saved an unrelated setting got a
# response telling them 2FA was off, and lost two_factor_enabled_at,
# backup_codes_generated_at, login_history and authorized_keys on the way.
#
# Unlike the two approval serializers (IMP-550e44e24220), these two are NOT
# allowed to differ — they describe the same resource to the same client, so
# the divergence is the defect rather than a contract to preserve. These specs
# therefore assert full equality of shape, not a shared subset.
RSpec.describe 'Settings read/write parity', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let(:headers) { auth_headers_for(user) }

  SECTIONS = %w[user_preferences account_settings notification_preferences security_settings].freeze

  def get_settings
    get '/api/v1/settings', headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data']
  end

  # Deliberately an UNRELATED write: nothing here touches the security section,
  # so anything the response says about 2FA is pure serialization.
  def put_settings
    # settings_params is params.require(:settings), so the body must nest.
    put '/api/v1/settings',
        params: { settings: { user_preferences: { timezone: 'Europe/Berlin' } } },
        headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data']
  end

  describe 'the security section' do
    before { user.enable_two_factor! }

    it 'reports 2FA as enabled on the READ half' do
      expect(get_settings.dig('security_settings', 'two_factor_enabled')).to be true
    end

    # The defect, stated directly: this is the one a user actually hits.
    it 'reports 2FA as enabled on the WRITE half too' do
      expect(put_settings.dig('security_settings', 'two_factor_enabled')).to be true
    end

    it 'does not drop security fields on the write half' do
      expect(put_settings['security_settings'].keys.sort)
        .to eq(get_settings['security_settings'].keys.sort)
    end
  end

  describe 'every section' do
    it 'has the same key set on both halves' do
      read = get_settings
      written = put_settings

      SECTIONS.each do |section|
        expect(written[section]).to be_present, "PUT response is missing #{section}"
        expect(read[section]).to be_present, "GET response is missing #{section}"
        expect(written[section].keys.sort).to eq(read[section].keys.sort),
                                              "#{section} has drifted between the read and write halves"
      end
    end

    # Values, not just shape. The write half must not invent or stale-cache a
    # value the read half computes live — a hardcoded literal passes a key-set
    # check and fails this one.
    it 'agrees on values for fields the write did not touch' do
      read = get_settings
      written = put_settings

      # user_preferences is excluded: the PUT deliberately changed timezone, so
      # the two are expected to differ there and only there.
      (SECTIONS - [ 'user_preferences' ]).each do |section|
        expect(written[section]).to eq(read[section]),
                                    "#{section} values diverge between the read and write halves"
      end
    end

    it 'applies the write it was asked to make' do
      expect(put_settings.dig('user_preferences', 'timezone')).to eq('Europe/Berlin')
    end
  end
end
