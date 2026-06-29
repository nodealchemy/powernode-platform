# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::WebhookUrlGuard do
  describe '.safe? / .validate!' do
    context 'rejects internal / disallowed destinations' do
      it 'rejects IPv4 loopback (127.0.0.1)' do
        expect(described_class.safe?('http://127.0.0.1/hook')).to be(false)
      end

      it 'rejects the cloud metadata link-local IP (169.254.169.254)' do
        expect(described_class.safe?('http://169.254.169.254/latest/meta-data/')).to be(false)
      end

      it 'rejects RFC1918 10.0.0.0/8' do
        expect(described_class.safe?('http://10.1.2.3/hook')).to be(false)
      end

      it 'rejects RFC1918 192.168.0.0/16' do
        expect(described_class.safe?('https://192.168.1.10/hook')).to be(false)
      end

      it 'rejects RFC1918 172.16.0.0/12' do
        expect(described_class.safe?('http://172.16.5.5/hook')).to be(false)
      end

      it 'rejects IPv6 loopback (::1)' do
        expect(described_class.safe?('http://[::1]/hook')).to be(false)
      end

      it 'rejects IPv4-mapped IPv6 loopback (::ffff:127.0.0.1)' do
        expect(described_class.safe?('http://[::ffff:127.0.0.1]/hook')).to be(false)
      end

      it 'rejects the unspecified address (0.0.0.0)' do
        expect(described_class.safe?('http://0.0.0.0/hook')).to be(false)
      end

      it 'rejects localhost' do
        expect(described_class.safe?('http://localhost:8080/hook')).to be(false)
      end

      it 'rejects *.localhost' do
        expect(described_class.safe?('http://api.localhost/hook')).to be(false)
      end

      it 'rejects metadata.google.internal' do
        expect(described_class.safe?('http://metadata.google.internal/computeMetadata/v1/')).to be(false)
      end

      it 'rejects non-http(s) schemes (ftp://)' do
        expect(described_class.safe?('ftp://example.com/hook')).to be(false)
      end

      it 'rejects file:// scheme' do
        expect(described_class.safe?('file:///etc/passwd')).to be(false)
      end

      it 'rejects a URL with no host' do
        expect(described_class.safe?('http:///hook')).to be(false)
      end

      it 'rejects a DNS name that resolves to a private IP (DNS-rebinding defense)' do
        allow(Resolv).to receive(:getaddresses).with('rebind.example.test').and_return(['10.0.0.5'])
        expect(described_class.safe?('https://rebind.example.test/hook')).to be(false)
      end

      it 'raises UnsafeUrlError from validate! with a descriptive message' do
        expect { described_class.validate!('http://169.254.169.254/') }
          .to raise_error(Security::WebhookUrlGuard::UnsafeUrlError, /internal address/)
      end
    end

    context 'allows public / opted-in destinations' do
      it 'allows a public IP literal' do
        expect(described_class.safe?('https://93.184.216.34/hook')).to be(true)
      end

      it 'allows a DNS name that resolves to a public IP' do
        allow(Resolv).to receive(:getaddresses).with('hooks.example.com').and_return(['93.184.216.34'])
        expect(described_class.safe?('https://hooks.example.com/endpoint')).to be(true)
      end

      it 'returns the parsed URI from validate! for a safe URL' do
        uri = described_class.validate!('https://93.184.216.34/hook')
        expect(uri).to be_a(URI::HTTPS)
        expect(uri.host).to eq('93.184.216.34')
      end
    end

    context 'with WEBHOOK_ALLOWED_INTERNAL_HOSTS opt-in allowlist' do
      around do |example|
        original = ENV['WEBHOOK_ALLOWED_INTERNAL_HOSTS']
        ENV['WEBHOOK_ALLOWED_INTERNAL_HOSTS'] = 'internal-hooks.example.test, other.internal'
        example.run
      ensure
        ENV['WEBHOOK_ALLOWED_INTERNAL_HOSTS'] = original
      end

      it 'allows an allowlisted internal host even though it resolves private' do
        allow(Resolv).to receive(:getaddresses).with('internal-hooks.example.test').and_return(['10.0.0.9'])
        expect(described_class.safe?('http://internal-hooks.example.test/hook')).to be(true)
      end

      it 'still rejects a non-allowlisted internal host' do
        allow(Resolv).to receive(:getaddresses).with('not-allowed.example.test').and_return(['10.0.0.9'])
        expect(described_class.safe?('http://not-allowed.example.test/hook')).to be(false)
      end
    end
  end
end
