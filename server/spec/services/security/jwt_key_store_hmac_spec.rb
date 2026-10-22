# frozen_string_literal: true

require "rails_helper"

# HS256 secrets live in Security::JwtKeyStore beside the RSA keypair: the
# active secret and a keyring of retired secrets still inside their grace
# window, both durable in SecretStore (account: nil) and cached only in
# process memory. Nothing HS256 goes to Rails.cache, which is a shared
# Postgres table wherever it is solid_cache.
RSpec.describe Security::JwtKeyStore, "HMAC keyring" do
  let(:env_secret) { Rails.application.config.jwt_secret_key }

  before do
    described_class.clear_cache!
    allow(Rails.application.config).to receive(:jwt_algorithm).and_return("HS256")
  end

  after { described_class.clear_cache! }

  def token_signed_with(secret, sub: "user-1")
    payload = {
      sub: sub, jti: SecureRandom.uuid, iat: Time.current.to_i, exp: 15.minutes.from_now.to_i,
      iss: Rails.application.config.jwt_issuer, aud: Rails.application.config.jwt_audience
    }
    JWT.encode(payload, secret, "HS256")
  end

  # Expire every cached entry: the cache TTL runs on the monotonic clock, which
  # `travel` does not move.
  def expire_cache!
    cache = described_class.instance_variable_get(:@cache)
    cache.each_key { |key| cache[key] = cache[key].merge(expires_at: 0) }
  end

  def stored_ring
    Security::SecretStore.read(account: nil, scope: described_class::SCOPE, key: described_class::HMAC_KEYRING)
  end

  # Simulate another process: rotate there, then put this process's cache back
  # to what it held before, so it still believes the pre-rotation secret.
  def rotate_in_another_process(grace_hours: 24)
    described_class.active_hmac_secret # warm this process's cache
    stale = described_class.instance_variable_get(:@cache).deep_dup
    described_class.rotate_hmac!(grace_hours: grace_hours)
    described_class.instance_variable_set(:@cache, stale)
    described_class.instance_variable_set(:@last_forced_refresh, nil)
  end

  def stored_active_secret
    Security::SecretStore.read(account: nil, scope: described_class::SCOPE, key: described_class::ACTIVE_HMAC_SECRET)
  end

  it "bootstraps from JWT_SECRET_KEY while the store holds no secret" do
    expect(described_class.active_hmac_secret).to eq(env_secret)
    expect(described_class.hmac_grace_secrets).to be_empty
  end

  describe ".rotate_hmac!" do
    it "makes a new active secret durable and keeps the retired one in the ring" do
      result = described_class.rotate_hmac!(grace_hours: 24)

      expect(stored_active_secret).to be_present
      expect(stored_active_secret).not_to eq(env_secret)
      expect(described_class.active_hmac_secret).to eq(stored_active_secret)
      expect(described_class.hmac_grace_secrets).to eq([ env_secret ])
      expect(result.keys).to contain_exactly(:rotated_at, :grace_ends_at)
    end

    it "prunes expired ring entries on the next rotation" do
      described_class.rotate_hmac!(grace_hours: 1)
      first_active = stored_active_secret

      travel(2.hours) { described_class.rotate_hmac!(grace_hours: 1) }

      travel(2.hours + 1.minute) do
        described_class.clear_cache!
        expect(described_class.hmac_grace_secrets).to eq([ first_active ])
      end
    end

    it "writes no HS256 material to Rails.cache" do
      writes = []
      allow(Rails.cache).to receive(:write).and_wrap_original do |original, *args, **kwargs|
        writes << args
        original.call(*args, **kwargs)
      end

      described_class.rotate_hmac!(grace_hours: 24)
      token = Security::JwtService.encode({ sub: "user-1" })
      Security::JwtService.decode(token)

      secrets = [ env_secret, stored_active_secret ]
      leaked = writes.select { |args| secrets.any? { |s| args.inspect.include?(s) } }
      expect(leaked).to be_empty
    end
  end

  describe "verification through JwtService (HS256)" do
    it "a process holding the pre-rotation secret verifies a token signed after the rotation" do
      rotate_in_another_process
      new_token = token_signed_with(stored_active_secret)

      expect(Security::JwtService.decode(new_token)[:sub]).to eq("user-1")
    end

    it "keeps verifying a token signed with the retired secret inside the grace window" do
      old_token = token_signed_with(env_secret)
      described_class.rotate_hmac!(grace_hours: 24)

      expect(Security::JwtService.decode(old_token)[:sub]).to eq("user-1")
    end

    it "refuses the retired secret once its grace window has passed" do
      described_class.rotate_hmac!(grace_hours: 1)

      travel(61.minutes) do
        described_class.clear_cache!
        old_token = token_signed_with(env_secret)
        expect { Security::JwtService.decode(old_token) }.to raise_error(StandardError, /Invalid token/)
      end
    end

    it "signs new tokens with the stored active secret" do
      described_class.rotate_hmac!(grace_hours: 24)

      token = Security::JwtService.encode({ sub: "user-1" })
      expect { JWT.decode(token, stored_active_secret, true, algorithm: "HS256") }.not_to raise_error
    end
  end

  describe "an unavailable store fails closed" do
    before do
      allow(Security::SecretStore).to receive(:read)
        .and_raise(Security::SecretStore::BackendUnavailable, "vault down")
    end

    it "refuses to sign rather than falling back to JWT_SECRET_KEY" do
      expect { Security::JwtService.encode({ sub: "user-1" }) }
        .to raise_error(described_class::StoreUnavailable)
    end

    it "refuses to verify, even a token signed with JWT_SECRET_KEY" do
      token = token_signed_with(env_secret)

      expect { Security::JwtService.decode(token) }.to raise_error(described_class::StoreUnavailable)
    end

    it "refuses to rotate" do
      expect { described_class.rotate_hmac!(grace_hours: 24) }.to raise_error(described_class::StoreUnavailable)
    end
  end

  # A Vault secret backend: VaultClient#read_secret raises SecretNotFoundError
  # for a path that does not exist yet, which is the normal state of every
  # install before its first HS256 rotation. The fake records each read's
  # `cache:` so the specs can see whether a forced refresh really re-reads.
  describe "on a Vault secret backend" do
    let(:vault) do
      Class.new do
        attr_reader :reads

        def initialize
          @data = {}
          @reads = []
        end

        def read_secret(path, key: nil, cache: true)
          @reads << { path: path, cache: cache }
          raise Security::VaultClient::SecretNotFoundError, "Secret not found: #{path}" unless @data.key?(path)

          key ? @data[path][key] : @data[path]
        end

        def write_secret(path, data)
          @data[path] = data.transform_keys(&:to_s)
        end

        def healthy? = true
      end.new
    end

    before do
      allow(Security::SecretStore).to receive(:backend).and_return(:vault)
      allow(Security::VaultClient).to receive(:instance).and_return(vault)
    end

    it "treats a not-yet-written secret as empty and bootstraps from JWT_SECRET_KEY" do
      expect(described_class.active_hmac_secret).to eq(env_secret)
      expect(described_class.hmac_grace_secrets).to be_empty
      expect { Security::JwtService.decode(Security::JwtService.encode({ sub: "user-1" })) }.not_to raise_error
    end

    it "can rotate out of the empty state" do
      described_class.rotate_hmac!(grace_hours: 24)

      expect(described_class.active_hmac_secret).not_to eq(env_secret)
      expect(described_class.hmac_grace_secrets).to eq([ env_secret ])
    end

    it "reads past VaultClient's own cache, so a forced refresh really re-reads Vault" do
      described_class.active_hmac_secret
      described_class.hmac_verification_secrets(refresh: true)

      expect(vault.reads).not_to be_empty
      expect(vault.reads.map { |r| r[:cache] }.uniq).to eq([ false ])
    end
  end

  # A store blip after the 60s cache has expired must not log everyone out:
  # the last secret this process loaded keeps serving until the store answers.
  describe "a store outage after secrets were loaded" do
    it "serves the last-known active and ring secrets" do
      described_class.rotate_hmac!(grace_hours: 24)
      active = described_class.active_hmac_secret
      ring = described_class.hmac_grace_secrets

      allow(Security::SecretStore).to receive(:read)
        .and_raise(Security::SecretStore::BackendUnavailable, "vault down")

      expire_cache!
      expect(described_class.active_hmac_secret).to eq(active)
      expect(described_class.hmac_grace_secrets).to eq(ring)
      expect(described_class.hmac_verification_secrets(refresh: true)).to eq([ active, *ring ])
    end

    # Transient database errors (solid_cache's own transient list) are an
    # outage too, not a bad token: last-known secret, or 503, never 401.
    it "treats a cancelled query as an outage and serves the last-known secret" do
      described_class.rotate_hmac!(grace_hours: 24)
      active = described_class.active_hmac_secret
      allow(Security::SecretStore).to receive(:read).and_raise(ActiveRecord::QueryCanceled, "canceling statement")

      expire_cache!
      expect(described_class.active_hmac_secret).to eq(active)
    end

    it "raises StoreUnavailable (503) for a cancelled query when nothing was loaded" do
      allow(Security::SecretStore).to receive(:read).and_raise(ActiveRecord::QueryCanceled, "canceling statement")

      expect { described_class.active_hmac_secret }.to raise_error(described_class::StoreUnavailable)
    end

    it "stops serving a last-known active secret once it is older than the rotation grace period" do
      described_class.rotate_hmac!(grace_hours: 24)
      described_class.active_hmac_secret
      allow(Security::SecretStore).to receive(:read)
        .and_raise(Security::SecretStore::BackendUnavailable, "vault down")

      travel(described_class::STALE_SERVE_LIMIT + 1.minute) do
        expire_cache!
        expect { described_class.active_hmac_secret }.to raise_error(described_class::StoreUnavailable)
      end
    end

    it "logs the stale-serve warning once per key per CACHE_TTL, not per request" do
      described_class.rotate_hmac!(grace_hours: 24)
      described_class.active_hmac_secret
      allow(Security::SecretStore).to receive(:read)
        .and_raise(Security::SecretStore::BackendUnavailable, "vault down")
      allow(Rails.logger).to receive(:warn)

      5.times do
        expire_cache!
        described_class.active_hmac_secret
      end

      expect(Rails.logger).to have_received(:warn).with(/last-known #{described_class::ACTIVE_HMAC_SECRET}/).once
    end

    it "still fails closed when nothing was ever loaded" do
      allow(Security::SecretStore).to receive(:read)
        .and_raise(Security::VaultClient::ConnectionError, "connection refused")

      expect { described_class.active_hmac_secret }.to raise_error(described_class::StoreUnavailable)
    end
  end

  # After a rotation, JWT_SECRET_KEY is a RETIRED secret. A store that answers
  # "empty" afterwards (wrong Vault mount or namespace, a reconfigured Vault, a
  # database restored from before the rotation) must not quietly bring it back.
  describe "after a rotation has been recorded" do
    before { described_class.rotate_hmac!(grace_hours: 24) }

    it "records the rotation outside the secret path" do
      expect(SiteSetting.get(described_class::ROTATION_MARKER)).to be_present
    end

    it "refuses to fall back to JWT_SECRET_KEY when the store answers empty" do
      described_class.clear_cache!
      allow(Security::SecretStore).to receive(:read).and_return(nil)

      expect { described_class.active_hmac_secret }.to raise_error(described_class::StoreUnavailable, /rotation/)
    end

    it "never replaces a last-known real secret with an empty read" do
      active = described_class.active_hmac_secret
      allow(Security::SecretStore).to receive(:read).and_return(nil)

      expire_cache!
      expect(described_class.active_hmac_secret).to eq(active)
    end
  end

  it "spaces forced refreshes at least 5s apart on a Vault backend" do
    allow(Security::SecretStore).to receive(:backend).and_return(:vault)
    clock = 1_000.0
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock }
    refreshed_at = -> { described_class.instance_variable_get(:@last_forced_refresh) }

    described_class.send(:force_refresh!)
    expect(refreshed_at.call).to eq(1_000.0)
    clock += 2
    described_class.send(:force_refresh!)
    expect(refreshed_at.call).to eq(1_000.0)
    clock += 4
    described_class.send(:force_refresh!)
    expect(refreshed_at.call).to eq(1_006.0)
  end

  # Before the first rotation the marker read is on the hot path too. During
  # an outage it serves its last-known value, like the secrets do, rather than
  # turning a bootstrap install's every request into a 503.
  it "serves the last-known rotation marker while the database is unreachable" do
    expect(described_class.active_hmac_secret).to eq(env_secret)
    allow(SiteSetting).to receive(:get).and_raise(ActiveRecord::QueryCanceled, "canceling statement")

    expire_cache!
    expect(described_class.active_hmac_secret).to eq(env_secret)
  end

  # The secrets are written first and are what matter; the marker is a guard.
  # A failure to write it must not fail a rotation whose secrets landed.
  it "completes a rotation, and drops its cache, when the marker write fails" do
    described_class.active_hmac_secret # warm the cache with the bootstrap secret
    allow(SiteSetting).to receive(:set).and_raise(ActiveRecord::StatementInvalid, "boom")
    allow(Rails.logger).to receive(:error)

    expect { described_class.rotate_hmac!(grace_hours: 24) }.not_to raise_error

    expect(described_class.active_hmac_secret).to eq(stored_active_secret)
    expect(Rails.logger).to have_received(:error).with(/#{described_class::ROTATION_MARKER}/)
  end

  # The documented revert clears the marker to an empty value through the
  # human-only site_setting_set_protected verb; SiteSetting must accept a
  # blank value for it, and blank must read as "not rotated".
  it "accepts a blank rotation marker, which reads back as not rotated" do
    described_class.rotate_hmac!(grace_hours: 24)

    expect(SiteSetting.set(described_class::ROTATION_MARKER, "", setting_type: "string")).to be_persisted
    described_class.clear_cache!

    expect(described_class.send(:rotation_recorded?)).to be(false)
  end

  it "still bootstraps from JWT_SECRET_KEY when no rotation was ever recorded" do
    allow(Security::SecretStore).to receive(:read).and_return(nil)

    expect(described_class.active_hmac_secret).to eq(env_secret)
  end
end
