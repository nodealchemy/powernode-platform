# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecurityHeaders do
  let(:app) { ->(env) { [ 200, { 'Content-Type' => 'text/html' }, [ 'OK' ] ] } }
  let(:middleware) { described_class.new(app) }
  let(:env) { Rack::MockRequest.env_for('/test') }

  describe '#call' do
    subject(:response) { middleware.call(env) }
    let(:status) { response[0] }
    let(:headers) { response[1] }
    let(:body) { response[2] }

    it 'passes through the original status' do
      expect(status).to eq(200)
    end

    it 'passes through the original body' do
      expect(body).to eq([ 'OK' ])
    end

    describe 'X-Frame-Options header' do
      it 'sets X-Frame-Options to DENY' do
        expect(headers['X-Frame-Options']).to eq('DENY')
      end

      context 'when header is already set' do
        let(:app) { ->(env) { [ 200, { 'X-Frame-Options' => 'SAMEORIGIN' }, [ 'OK' ] ] } }

        it 'does not override existing header' do
          expect(headers['X-Frame-Options']).to eq('SAMEORIGIN')
        end
      end
    end

    describe 'X-Content-Type-Options header' do
      it 'sets X-Content-Type-Options to nosniff' do
        expect(headers['X-Content-Type-Options']).to eq('nosniff')
      end
    end

    describe 'X-XSS-Protection header' do
      it 'sets X-XSS-Protection to block mode' do
        expect(headers['X-XSS-Protection']).to eq('1; mode=block')
      end
    end

    describe 'Referrer-Policy header' do
      it 'sets strict referrer policy' do
        expect(headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
      end
    end

    describe 'Permissions-Policy header' do
      it 'restricts browser features' do
        expect(headers['Permissions-Policy']).to eq('microphone=(), camera=(), geolocation=()')
      end
    end

    describe 'X-Permitted-Cross-Domain-Policies header' do
      it 'prevents cross-domain policy file loading' do
        expect(headers['X-Permitted-Cross-Domain-Policies']).to eq('none')
      end
    end

    describe 'Content-Security-Policy header' do
      context 'for HTML responses' do
        let(:app) { ->(env) { [ 200, { 'Content-Type' => 'text/html' }, [ 'OK' ] ] } }

        it 'sets Content-Security-Policy' do
          expect(headers['Content-Security-Policy']).to be_present
        end

        it 'restricts default-src to self' do
          expect(headers['Content-Security-Policy']).to include("default-src 'self'")
        end

        it 'restricts script-src to self' do
          expect(headers['Content-Security-Policy']).to include("script-src 'self'")
        end

        it 'prevents framing via frame-ancestors' do
          expect(headers['Content-Security-Policy']).to include("frame-ancestors 'none'")
        end

        it 'restricts base-uri' do
          expect(headers['Content-Security-Policy']).to include("base-uri 'self'")
        end

        it 'restricts form-action' do
          expect(headers['Content-Security-Policy']).to include("form-action 'self'")
        end
      end

      context 'for JSON API responses' do
        let(:app) { ->(env) { [ 200, { 'Content-Type' => 'application/json' }, [ '{"status":"ok"}' ] ] } }

        it 'does not set Content-Security-Policy for API responses' do
          expect(headers['Content-Security-Policy']).to be_nil
        end
      end
    end
  end

  describe 'integration with Rails' do
    it 'works as Rack middleware' do
      expect { middleware.call(env) }.not_to raise_error
    end

    it 'handles errors gracefully' do
      error_app = ->(_env) { raise StandardError, 'Test error' }
      error_middleware = described_class.new(error_app)

      expect { error_middleware.call(env) }.to raise_error(StandardError, 'Test error')
    end
  end

  describe 'security header completeness' do
    subject(:response) { middleware.call(env) }
    let(:headers) { response[1] }

    it 'includes all essential security headers' do
      essential_headers = [
        'X-Frame-Options',
        'X-Content-Type-Options',
        'X-XSS-Protection',
        'Referrer-Policy',
        'Permissions-Policy',
        'X-Permitted-Cross-Domain-Policies'
      ]

      essential_headers.each do |header|
        expect(headers[header]).to be_present, "Expected #{header} to be present"
      end
    end
  end
end
