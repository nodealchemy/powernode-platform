# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookHealthService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  # make_test_request issues the outbound HTTP POST to the user-settable
  # endpoint.url. It must reject private/loopback/link-local/metadata targets
  # BEFORE opening a socket — otherwise the webhook health test (reachable with
  # webhook.read) is a blind internal port-scan / reachability oracle.
  #
  # Exercised at the service level: test_endpoint's delivery recording references
  # non-existent WebhookDelivery columns and 500s independently (tracked as a
  # separate follow-up), so we drive the guard in make_test_request directly.
  describe '#make_test_request SSRF guard' do
    let(:endpoint) { create(:webhook_endpoint, account: account) }
    let(:payload) { { test: true } }

    it 'rejects a link-local/metadata URL without opening a socket' do
      endpoint.update_column(:url, 'http://169.254.169.254/latest/meta-data/')
      # Would succeed if the request were actually sent — proves the guard
      # blocked it rather than the request merely failing to connect.
      stub_request(:post, 'http://169.254.169.254/latest/meta-data/').to_return(status: 200, body: 'ok')

      expect do
        service.send(:make_test_request, endpoint, payload)
      end.to raise_error(Ai::DataSources::HttpConnectionFactory::SsrfError)

      expect(WebMock).not_to have_requested(:post, 'http://169.254.169.254/latest/meta-data/')
    end

    it 'rejects a private (RFC1918) URL without opening a socket' do
      endpoint.update_column(:url, 'http://10.0.0.5:8080/')
      stub_request(:post, 'http://10.0.0.5:8080/').to_return(status: 200, body: 'ok')

      expect do
        service.send(:make_test_request, endpoint, payload)
      end.to raise_error(Ai::DataSources::HttpConnectionFactory::SsrfError)

      expect(WebMock).not_to have_requested(:post, 'http://10.0.0.5:8080/')
    end

    it 'allows a public URL (the request proceeds normally)' do
      endpoint.update_column(:url, 'http://93.184.216.34/webhook')
      stub_request(:post, 'http://93.184.216.34/webhook').to_return(status: 200, body: 'ok')

      service.send(:make_test_request, endpoint, payload)

      expect(WebMock).to have_requested(:post, 'http://93.184.216.34/webhook')
    end

    # DNS-rebinding TOCTOU: validating the host then connecting by hostname
    # re-resolves at connect, so a sub-TTL rebind could reach an internal IP.
    # make_test_request must resolve+validate ONCE and PIN the socket to that IP
    # (Net::HTTP#ipaddr=), keeping the hostname for Host header / SNI / cert.
    it 'pins the socket to the resolved+validated IP (closes the rebind TOCTOU)' do
      endpoint.update_column(:url, 'http://hook.example.test/webhook')
      stub_request(:post, 'http://hook.example.test/webhook').to_return(status: 200, body: 'ok')
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:resolve_host)
        .with('hook.example.test').and_return([ IPAddr.new('93.184.216.34') ])

      expect_any_instance_of(Net::HTTP).to receive(:ipaddr=).with('93.184.216.34')

      service.send(:make_test_request, endpoint, payload)
    end
  end
end
