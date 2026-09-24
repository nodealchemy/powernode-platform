# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::MaintenanceMode do
  describe '.status / .enabled?' do
    it 'defaults to disabled with no AdminSetting rows at all' do
      status = described_class.status

      expect(status[:enabled]).to be false
      expect(status[:message]).to eq(described_class::DEFAULT_MESSAGE)
      expect(status[:enabled_at]).to be_nil
      expect(status[:estimated_completion]).to be_nil
      expect(status[:bypass_ips]).to eq([])
      expect(described_class.enabled?).to be false
    end

    it 'is blind to a legacy row under the OLD AdminSetting key name' do
      AdminSetting.create!(key: 'maintenance_mode', value: 'true')

      expect(described_class.enabled?).to be false
    end
  end

  describe '.enable!' do
    it 'persists a typed boolean row under the fresh key, not the legacy one' do
      described_class.enable!(message: 'Upgrading', estimated_completion: '2026-01-01T00:00:00Z', bypass_ips: [ '10.0.0.1' ])

      row = AdminSetting.find_by(key: described_class::ENABLED_KEY)
      expect(row.value).to eq('true') # AdminSetting.set JSON-serializes non-String values
      expect(AdminSetting.get(described_class::ENABLED_KEY)).to eq(true) # ...and .get parses it back to a real boolean
      expect(AdminSetting.find_by(key: 'maintenance_mode')).to be_nil
    end

    it 'is visible to a READ THAT NEVER WROTE IT — a fresh read after the cache is cleared, standing in for a second Puma worker' do
      described_class.enable!(message: 'Upgrading')

      # Simulate a different process / a later request: clear ONLY the cache,
      # never touching the DB row, and read again.
      described_class.invalidate_cache!

      expect(described_class.enabled?).to be true
      expect(described_class.status[:message]).to eq('Upgrading')
    end

    it 'defaults message when blank' do
      status = described_class.enable!(message: '')

      expect(status[:message]).to eq(described_class::DEFAULT_MESSAGE)
    end

    it 'stores message and estimated_completion as plain strings, never JSON-coerced' do
      # "123" and "true" are exactly the shapes AdminSetting.get's JSON.parse
      # fallback would silently turn into an Integer/boolean on the next read.
      status = described_class.enable!(message: '123', estimated_completion: 'true')

      expect(status[:message]).to eq('123')
      expect(status[:estimated_completion]).to eq('true')

      described_class.invalidate_cache!

      reread = described_class.status
      expect(reread[:message]).to eq('123')
      expect(reread[:estimated_completion]).to eq('true')
    end

    it 'caches the status for CACHE_TTL so a write is not immediately visible without invalidation' do
      described_class.enable!(message: 'Upgrading')
      # Overwrite the DB row directly, bypassing the service, to prove the
      # NEXT .status call is serving the cache rather than re-querying.
      AdminSetting.find_by(key: described_class::ENABLED_KEY).update!(value: 'false')

      expect(described_class.enabled?).to be true # still cached

      described_class.invalidate_cache!

      expect(described_class.enabled?).to be false # now re-read from the DB
    end

    it 'raises InvalidBypassIp and writes nothing for an unparseable entry' do
      expect {
        described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5', 'not-an-ip' ])
      }.to raise_error(described_class::InvalidBypassIp, /not-an-ip/)

      expect(described_class.enabled?).to be false
    end

    it 'accepts a CIDR bypass entry' do
      status = described_class.enable!(message: 'Upgrading', bypass_ips: [ '198.51.100.0/24' ])

      expect(status[:bypass_ips]).to eq([ '198.51.100.0/24' ])
    end
  end

  describe '.disable!' do
    it 'clears every field back to defaults' do
      described_class.enable!(message: 'Upgrading', estimated_completion: '2026-01-01T00:00:00Z', bypass_ips: [ '10.0.0.1' ])

      status = described_class.disable!

      expect(status[:enabled]).to be false
      expect(status[:message]).to eq(described_class::DEFAULT_MESSAGE)
      expect(status[:enabled_at]).to be_nil
      expect(status[:estimated_completion]).to be_nil
      expect(status[:bypass_ips]).to eq([])
    end
  end

  describe '.bypass_ip?' do
    it 'is false with no bypass list' do
      expect(described_class.bypass_ip?('203.0.113.5')).to be false
    end

    it 'matches a public IP on the configured bypass list' do
      described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

      expect(described_class.bypass_ip?('203.0.113.5')).to be true
      expect(described_class.bypass_ip?('203.0.113.6')).to be false
    end

    it 'matches a CIDR bypass entry' do
      described_class.enable!(message: 'Upgrading', bypass_ips: [ '198.51.100.0/24' ])

      expect(described_class.bypass_ip?('198.51.100.42')).to be true
      expect(described_class.bypass_ip?('198.51.101.1')).to be false
    end

    it 'matches an IPv4-mapped IPv6 peer against a bare IPv4 bypass entry' do
      described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

      expect(described_class.bypass_ip?('::ffff:203.0.113.5')).to be true
    end

    it 'is false for a blank IP' do
      expect(described_class.bypass_ip?(nil)).to be false
      expect(described_class.bypass_ip?('')).to be false
    end

    context 'when the configured bypass entry is itself a private/loopback range' do
      around do |example|
        original = ENV['TRUSTED_PROXY_CIDRS']
        example.run
        original.nil? ? ENV.delete('TRUSTED_PROXY_CIDRS') : (ENV['TRUSTED_PROXY_CIDRS'] = original)
      end

      it 'refuses the match without TRUSTED_PROXY_CIDRS configured (default: any private hop is a trusted proxy)' do
        ENV.delete('TRUSTED_PROXY_CIDRS')
        described_class.enable!(message: 'Upgrading', bypass_ips: [ '10.0.0.5' ])

        expect(described_class.bypass_ip?('10.0.0.5')).to be false
      end

      it 'honors the match once TRUSTED_PROXY_CIDRS is configured' do
        ENV['TRUSTED_PROXY_CIDRS'] = '10.10.10.10/32'
        described_class.enable!(message: 'Upgrading', bypass_ips: [ '10.0.0.5' ])

        expect(described_class.bypass_ip?('10.0.0.5')).to be true
      end
    end
  end

  describe '.blocked?' do
    it 'is false when maintenance mode is disabled, regardless of permission' do
      expect(described_class.blocked? { false }).to be false
    end

    it 'is true when enabled and the permission check never grants an exempt permission' do
      described_class.enable!(message: 'Upgrading')

      expect(described_class.blocked? { false }).to be true
    end

    it 'is false when the permission check grants any of EXEMPT_PERMISSIONS' do
      described_class.enable!(message: 'Upgrading')

      %w[system.admin admin.access admin.maintenance.mode].each do |exempt|
        expect(described_class.blocked? { |perm| perm == exempt }).to be false
      end
    end

    it 'is false for a bypass-listed remote IP even with no exempt permission' do
      described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

      expect(described_class.blocked?('203.0.113.5') { false }).to be false
    end

    it 'is true for a non-exempt, non-bypassed request' do
      described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

      expect(described_class.blocked?('198.51.100.1') { false }).to be true
    end
  end
end
