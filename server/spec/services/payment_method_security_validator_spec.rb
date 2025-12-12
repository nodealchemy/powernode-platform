require 'rails_helper'

RSpec.describe PaymentMethodSecurityValidator do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:payment_method_data) do
    {
      'type' => 'card',
      'card' => {
        'brand' => 'visa',
        'country' => 'US',
        'funding' => 'credit',
        'checks' => {
          'cvc_check' => 'pass',
          'address_line1_check' => 'pass',
          'address_postal_code_check' => 'pass'
        }
      },
      'provider' => 'stripe'
    }
  end
  let(:request_metadata) { { ip_address: '192.168.1.1' } }

  let(:validator) do
    described_class.new(
      account: account,
      user: user,
      payment_method_data: payment_method_data,
      request_metadata: request_metadata
    )
  end

  describe '#validate' do
    context 'with low-risk payment method' do
      before do
        # Set account as older to avoid new account penalty
        account.update!(created_at: 1.month.ago)
        # Set user country in preferences to match IP geolocation
        user.update!(preferences: { 'country' => 'US' })
      end

      it 'recommends approval' do
        result = validator.validate

        expect(result[:recommendation]).to eq('approve')
        expect(result[:overall_risk_score]).to be < 30
        expect(result[:requires_additional_verification]).to be_falsy
      end
    end

    context 'with high-risk characteristics' do
      let(:payment_method_data) do
        {
          'type' => 'card',
          'card' => {
            'brand' => 'visa',
            'country' => 'AF', # High-risk country
            'funding' => 'prepaid', # High-risk funding
            'checks' => {
              'cvc_check' => 'fail',
              'address_line1_check' => 'fail',
              'address_postal_code_check' => 'fail'
            }
          },
          'provider' => 'stripe'
        }
      end

      it 'recommends rejection or additional verification' do
        result = validator.validate

        expect(result[:recommendation]).to be_in([ 'reject', 'additional_verification' ])
        expect(result[:overall_risk_score]).to be >= 60
        expect(result[:risk_factors]).to include('high_risk_country')
        expect(result[:risk_factors]).to include('high_risk_funding_source')
      end
    end

    context 'with new account and high velocity' do
      before do
        account.update!(created_at: 1.hour.ago)
        create_list(:payment_method, 4, account: account, created_at: 1.hour.ago)
      end

      it 'increases risk score' do
        result = validator.validate

        expect(result[:risk_factors]).to include('new_account')
        expect(result[:risk_factors]).to include('high_payment_method_velocity')
        expect(result[:overall_risk_score]).to be >= 40
      end
    end

    context 'with account payment failures' do
      before do
        subscription = create(:subscription, account: account)
        invoice = create(:invoice, subscription: subscription)
        create_list(:payment, 3, invoice: invoice, status: 'failed')
      end

      it 'considers payment history' do
        result = validator.validate

        expect(result[:validations][:account_history][:details][:failed_payments]).to eq(3)
      end
    end

    context 'with error during validation' do
      before do
        allow(validator).to receive(:validate_card_details).and_raise(StandardError, 'Test error')
      end

      it 'returns rejection with error' do
        result = validator.validate

        expect(result[:overall_risk_score]).to eq(100)
        expect(result[:recommendation]).to eq('reject')
        expect(result[:risk_factors]).to include('validation_error')
        expect(result[:error]).to eq('Test error')
      end
    end
  end

  describe 'validation components' do
    describe '#validate_card_details' do
      let(:card_validation) { validator.send(:validate_card_details) }

      context 'with valid card' do
        it 'returns low risk score' do
          expect(card_validation[:valid]).to be_truthy
          expect(card_validation[:risk_score]).to be < 25
        end
      end

      context 'with failed checks' do
        let(:payment_method_data) do
          {
            'type' => 'card',
            'card' => {
              'brand' => 'visa',
              'country' => 'US',
              'funding' => 'credit',
              'checks' => {
                'cvc_check' => 'fail',
                'address_line1_check' => 'fail'
              }
            }
          }
        end

        it 'increases risk score for failed checks' do
          expect(card_validation[:risk_score]).to be >= 30
          expect(card_validation[:risk_factors]).to include('cvc_check_failed')
          expect(card_validation[:risk_factors]).to include('address_verification_failed')
        end
      end
    end

    describe '#check_velocity_limits' do
      let(:velocity_check) { validator.send(:check_velocity_limits) }

      context 'with normal velocity' do
        it 'returns low risk score' do
          expect(velocity_check[:risk_score]).to be < 30
        end
      end

      context 'with high velocity' do
        before do
          create_list(:payment_method, 4, account: account, created_at: 1.hour.ago)
        end

        it 'flags high velocity' do
          expect(velocity_check[:risk_score]).to be >= 40
          expect(velocity_check[:risk_factors]).to include('high_payment_method_velocity')
        end
      end
    end

    describe '#validate_geolocation' do
      let(:geo_validation) { validator.send(:validate_geolocation) }

      context 'with matching geolocation' do
        before do
          user.update!(preferences: { 'country' => 'US' })
          allow(validator).to receive(:detect_country_from_ip).and_return('US')
        end

        it 'returns low risk score' do
          expect(geo_validation[:risk_score]).to eq(0)
          expect(geo_validation[:valid]).to be_truthy
        end
      end

      context 'with mismatched geolocation' do
        before do
          user.update!(preferences: { 'country' => 'US' })
          allow(validator).to receive(:detect_country_from_ip).and_return('RU')
        end

        it 'flags geolocation mismatch' do
          expect(geo_validation[:risk_score]).to eq(30)
          expect(geo_validation[:risk_factors]).to include('geolocation_mismatch')
        end
      end
    end

    describe '#check_account_history' do
      let(:account_history) { validator.send(:check_account_history) }

      context 'with new account' do
        before do
          account.update!(created_at: 1.hour.ago)
        end

        it 'flags new account' do
          expect(account_history[:risk_factors]).to include('new_account')
          expect(account_history[:risk_score]).to eq(25)
        end
      end

      context 'with previous chargebacks' do
        before do
          account.update!(settings: { 'chargeback_count' => 2 })
        end

        it 'flags previous chargebacks' do
          expect(account_history[:risk_factors]).to include('previous_chargebacks')
          expect(account_history[:risk_score]).to be >= 60
        end
      end
    end
  end

  describe 'helper methods' do
    describe '#high_risk_country?' do
      it 'identifies high-risk countries' do
        expect(validator.send(:high_risk_country?, 'AF')).to be_truthy
        expect(validator.send(:high_risk_country?, 'US')).to be_falsy
        expect(validator.send(:high_risk_country?, nil)).to be_falsy
      end
    end

    describe '#high_risk_issuer?' do
      it 'identifies high-risk funding types' do
        expect(validator.send(:high_risk_issuer?, 'prepaid')).to be_truthy
        expect(validator.send(:high_risk_issuer?, 'credit')).to be_falsy
        expect(validator.send(:high_risk_issuer?, nil)).to be_falsy
      end
    end
  end
end
