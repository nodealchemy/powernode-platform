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

  describe '#trusted_proxies_configured? (via .status[:bypass_ips_supported])' do
    it 'is false when TRUSTED_PROXY_CIDRS is unset' do
      expect(described_class.status[:bypass_ips_supported]).to be false
    end

    it 'is true when TRUSTED_PROXY_CIDRS parses to at least one valid entry' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        expect(described_class.status[:bypass_ips_supported]).to be true
      end
    end

    # N3: an env var that IS set but entirely unparseable must not report
    # supported — the predicate has to check the PARSED result, not the raw
    # env var's mere presence, or bypass_ip?/validate_bypass_ips! would trust
    # request.remote_ip when application.rb actually left NOTHING pinned
    # (Rails' own default trusted-proxy list applies instead — see
    # Powernode::TrustedProxyCidrs's N3 correction).
    it 'is false when TRUSTED_PROXY_CIDRS is set but entirely garbage' do
      with_trusted_proxy_cidrs('garbage, also-not-an-ip') do
        expect(described_class.status[:bypass_ips_supported]).to be false
      end
    end

    it 'raises InvalidBypassIp for a bypass-IP write when TRUSTED_PROXY_CIDRS is all-garbage' do
      with_trusted_proxy_cidrs('garbage, also-not-an-ip') do
        expect {
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
        }.to raise_error(described_class::InvalidBypassIp, /TRUSTED_PROXY_CIDRS/)
      end
    end
  end

  describe '.enable!' do
    it 'persists a typed boolean row under the fresh key, not the legacy one' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.enable!(message: 'Upgrading', estimated_completion: '2026-01-01T00:00:00Z', bypass_ips: [ '10.0.0.1' ])
      end

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
      # Seed the cache with an explicit read (enable! itself no longer does
      # this — see run_after_commit — so simulate a request that read the
      # status right after the write).
      expect(described_class.enabled?).to be true

      # Overwrite the DB row directly, bypassing the service, to prove the
      # NEXT .status call is serving the cache rather than re-querying.
      AdminSetting.find_by(key: described_class::ENABLED_KEY).update!(value: 'false')

      expect(described_class.enabled?).to be true # still cached

      described_class.invalidate_cache!

      expect(described_class.enabled?).to be false # now re-read from the DB
    end

    it 'invalidates the cache immediately when called outside a transaction (no deferral to commit)' do
      described_class.enable!(message: 'Upgrading')
      expect(described_class.enabled?).to be true # seeds the cache

      described_class.disable!
      # No explicit invalidate_cache! call here: disable! ran with no open
      # transaction, so run_after_commit's NullTransaction fires immediately.
      expect(described_class.enabled?).to be false
    end

    it 'defers cache invalidation until the surrounding transaction commits' do
      described_class.enable!(message: 'Upgrading')
      expect(described_class.enabled?).to be true # seeds the cache

      ActiveRecord::Base.transaction do
        described_class.disable!
        # Still inside the transaction: the cache has NOT been invalidated
        # yet, so a concurrent reader would still see the old (cached) value.
        expect(described_class.enabled?).to be true
      end

      # Transaction committed: the deferred invalidation has now run.
      expect(described_class.enabled?).to be false
    end

    it 'raises InvalidBypassIp explaining TRUSTED_PROXY_CIDRS when unset, for a well-formed public IP' do
      expect {
        described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
      }.to raise_error(described_class::InvalidBypassIp, /TRUSTED_PROXY_CIDRS/)

      expect(described_class.enabled?).to be false
    end

    it 'raises InvalidBypassIp for an unparseable entry once TRUSTED_PROXY_CIDRS is configured' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        expect {
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5', 'not-an-ip' ])
        }.to raise_error(described_class::InvalidBypassIp, /not-an-ip/)
      end

      expect(described_class.enabled?).to be false
    end

    it 'accepts a CIDR bypass entry once TRUSTED_PROXY_CIDRS is configured' do
      status = with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.enable!(message: 'Upgrading', bypass_ips: [ '198.51.100.0/24' ])
      end

      expect(status[:bypass_ips]).to eq([ '198.51.100.0/24' ])
    end

    it 'does not raise when bypass_ips is empty, TRUSTED_PROXY_CIDRS unset or not' do
      expect { described_class.enable!(message: 'Upgrading', bypass_ips: []) }.not_to raise_error
      expect { described_class.enable!(message: 'Upgrading') }.not_to raise_error
    end
  end

  describe '.disable!' do
    it 'clears every field back to defaults' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.enable!(message: 'Upgrading', estimated_completion: '2026-01-01T00:00:00Z', bypass_ips: [ '10.0.0.1' ])
      end

      status = described_class.disable!

      expect(status[:enabled]).to be false
      expect(status[:message]).to eq(described_class::DEFAULT_MESSAGE)
      expect(status[:enabled_at]).to be_nil
      expect(status[:estimated_completion]).to be_nil
      expect(status[:bypass_ips]).to eq([])
    end
  end

  describe '.update_fields!' do
    it 'updates message/estimated_completion/bypass_ips without touching enabled' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        status = described_class.update_fields!(message: 'Staged message', estimated_completion: '30 minutes', bypass_ips: [ '203.0.113.5' ])

        expect(status[:enabled]).to be false
        expect(status[:message]).to eq('Staged message')
        expect(status[:estimated_completion]).to eq('30 minutes')
        expect(status[:bypass_ips]).to eq([ '203.0.113.5' ])
      end
    end

    it 'does NOT wipe fields when maintenance is already OFF (the Save-while-OFF regression)' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.update_fields!(message: 'Staged message', bypass_ips: [ '203.0.113.5' ])
        described_class.invalidate_cache!

        expect(described_class.status[:message]).to eq('Staged message')
        expect(described_class.status[:bypass_ips]).to eq([ '203.0.113.5' ])
        expect(described_class.enabled?).to be false
      end
    end

    it 'does NOT reset enabled_at when maintenance is already ON (the Save-while-ON regression)' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.enable!(message: 'Upgrading')
        original_enabled_at = described_class.status[:enabled_at]

        travel_to(1.hour.from_now) do
          described_class.update_fields!(message: 'Almost done')
          described_class.invalidate_cache!

          expect(described_class.status[:message]).to eq('Almost done')
          expect(described_class.status[:enabled_at]).to eq(original_enabled_at)
          expect(described_class.enabled?).to be true
        end
      end
    end

    it 'still validates bypass IPs the same way enable! does' do
      expect {
        described_class.update_fields!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
      }.to raise_error(described_class::InvalidBypassIp, /TRUSTED_PROXY_CIDRS/)
    end

    # Item 7a: a caller that omits a keyword entirely (not "passes it as
    # blank") must leave that field completely untouched.
    it 'leaves bypass_ips and estimated_completion untouched when only message is given' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.update_fields!(message: 'first', estimated_completion: '10 minutes', bypass_ips: [ '203.0.113.5' ])

        status = described_class.update_fields!(message: 'second')

        expect(status[:message]).to eq('second')
        expect(status[:estimated_completion]).to eq('10 minutes')
        expect(status[:bypass_ips]).to eq([ '203.0.113.5' ])
      end
    end

    it 'leaves message and estimated_completion untouched when only bypass_ips is given' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.update_fields!(message: 'Keep me', estimated_completion: '10 minutes')

        status = described_class.update_fields!(bypass_ips: [ '198.51.100.9' ])

        expect(status[:message]).to eq('Keep me')
        expect(status[:estimated_completion]).to eq('10 minutes')
        expect(status[:bypass_ips]).to eq([ '198.51.100.9' ])
      end
    end
  end

  describe '.bypass_ip?' do
    it 'is false with no bypass list' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        expect(described_class.bypass_ip?('203.0.113.5')).to be false
      end
    end

    it 'is false for a blank IP' do
      expect(described_class.bypass_ip?(nil)).to be false
      expect(described_class.bypass_ip?('')).to be false
    end

    context 'without TRUSTED_PROXY_CIDRS configured' do
      it 'refuses to match ANY bypass entry — public or private — even one already configured' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
        end

        # TRUSTED_PROXY_CIDRS is unset again here (with_trusted_proxy_cidrs restores it).
        expect(described_class.bypass_ip?('203.0.113.5')).to be false
      end
    end

    context 'with TRUSTED_PROXY_CIDRS configured' do
      it 'matches a public IP on the configured bypass list' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

          expect(described_class.bypass_ip?('203.0.113.5')).to be true
          expect(described_class.bypass_ip?('203.0.113.6')).to be false
        end
      end

      it 'matches a private-range bypass entry too — the public/private split was dropped' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '10.0.0.5' ])

          expect(described_class.bypass_ip?('10.0.0.5')).to be true
        end
      end

      it 'matches a CIDR bypass entry' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '198.51.100.0/24' ])

          expect(described_class.bypass_ip?('198.51.100.42')).to be true
          expect(described_class.bypass_ip?('198.51.101.1')).to be false
        end
      end

      it 'matches an IPv4-mapped IPv6 peer against a bare IPv4 bypass entry' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

          expect(described_class.bypass_ip?('::ffff:203.0.113.5')).to be true
        end
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

    it 'is false for a bypass-listed remote IP even with no exempt permission, once TRUSTED_PROXY_CIDRS is configured' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        described_class.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])

        expect(described_class.blocked?('203.0.113.5') { false }).to be false
        expect(described_class.blocked?('198.51.100.1') { false }).to be true
      end
    end
  end
end
