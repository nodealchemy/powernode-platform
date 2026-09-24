# frozen_string_literal: true

require "rails_helper"

# IMP-24df1ec74489 — rack_attack.rb's #extract_account_from_request (:67)
# and the "system_api_keys" safelist (:390) both query ApiKey by a
# `key_hash` column that does not exist (schema has `key_digest`), AND —
# even once the column name is fixed — with the WRONG digest scheme:
# `Digest::SHA256.hexdigest(api_key)` (bare) never equals what ApiKey
# actually stores, which is `ApiKey.hash_key(api_key)` =
# `Digest::SHA256.hexdigest("#{secret_key_base}:#{api_key}")` — confirmed
# by executing the real write path (ApiKey#generate_key) and comparing
# against both candidate digests before writing a line of fix (see the
# task's own trap warning: a column-name-only fix would convert today's
# loud PG::UndefinedColumn into a silent never-match, which is worse).
#
# CONSEQUENCE CLASSIFICATION, established by execution before any fix:
# - :390 (safelist) is RESCUED-AND-SILENT — its `rescue StandardError ->
#   false` catches the raise, so a system API key is simply never
#   safelisted, with no log at all today.
# - :67 (extract_account_from_request) is UNRESCUED at most of its call
#   sites, including the "extreme_abuse" blocklist (which runs
#   unconditionally for every request, gated only by
#   rate_limiting_enabled? — true by default outside test). Reproduced
#   directly: a real request carrying ANY X-API-Key header (valid or
#   garbage) through that blocklist raises straight through Rack::Attack's
#   middleware and 500s the request. See the request-spec example below.
# - The "poisons the DB transaction for later queries" claim is TRUE but
#   ENVIRONMENT-SPECIFIC, not a general production mechanism: reproduced
#   under RSpec's `use_transactional_fixtures` (the whole example shares
#   one open transaction, so Postgres aborts it until rollback at the
#   test's end) via `rails runner` OUTSIDE that wrapper, where the
#   identical rescued raise does NOT poison a later unrelated query —
#   confirmed empirically, not assumed. Rails does not wrap a live web
#   request in one ambient transaction by default, and Rack::Attack runs
#   as outer middleware before any controller-level transaction would
#   open, so this mechanism is not expected to reproduce against a live
#   production request either — recorded here rather than carried forward
#   as an established production hazard.
RSpec.describe "Rack::Attack API-key lookups" do
  def request_with_api_key(api_key)
    env = Rack::MockRequest.env_for("/api/v1/whatever", "HTTP_X_API_KEY" => api_key)
    Rack::Attack::Request.new(env)
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:api_key) { ApiKey.create!(name: "rack-attack-lookup-test", account: account, created_by: user) }
  let(:plaintext_key) { api_key.key_value }

  describe "Rack::Attack.extract_account_from_request" do
    it "resolves the correct account for a real, valid API key — verified against the real write path, not a guessed scheme" do
      request = request_with_api_key(plaintext_key)

      expect(Rack::Attack.extract_account_from_request(request)).to eq(account)
    end

    it "returns nil (fails open), never raises, for a garbage API key" do
      request = request_with_api_key("garbage-not-a-real-key")

      result = nil
      expect { result = Rack::Attack.extract_account_from_request(request) }.not_to raise_error
      expect(result).to be_nil
    end

    it "returns nil for a revoked (inactive) key even though it exists" do
      api_key.update!(is_active: false)
      request = request_with_api_key(plaintext_key)

      expect(Rack::Attack.extract_account_from_request(request)).to be_nil
    end

    # The dangerous-direction requirement: a rate limiter silently failing
    # open must not do so without a trace.
    it "fails open and logs at ERROR naming the reason when the lookup itself raises unexpectedly" do
      allow(ApiKey).to receive(:active).and_raise("simulated DB blip")
      allow(Rails.logger).to receive(:error)
      request = request_with_api_key(plaintext_key)

      result = nil
      expect { result = Rack::Attack.extract_account_from_request(request) }.not_to raise_error
      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error).with(a_string_including("simulated DB blip"))
    end
  end

  # Review follow-up — the original rescue wrapped only the ApiKey lookup,
  # leaving the user/JWT branch (extract_user_from_request + its .account
  # load), which most authenticated requests take, exposed to the same
  # unrescued-helper -> 500 path the API-key branch had.
  describe "the JWT/user branch of extract_account_from_request" do
    def request_with_bearer_token(token)
      env = Rack::MockRequest.env_for("/api/v1/whatever", "HTTP_AUTHORIZATION" => "Bearer #{token}")
      Rack::Attack::Request.new(env)
    end

    # IMP-99e8e4701150 review B1 — a real Security::JwtService.encode token,
    # not a hand-rolled JWT.encode with only `sub`: extract_user_from_request
    # now decodes via Security::JwtService (issuer/audience/rotation-aware,
    # not a hardcoded HS256 verify), which a minimal token missing iss/aud/iat
    # fails against.
    let(:valid_token) do
      Security::JwtService.encode({
        sub: user.id,
        account_id: user.account_id,
        email: user.email,
        type: "access",
        version: Security::JwtService::CURRENT_TOKEN_VERSION
      })
    end

    # Calls #extract_user_from_request DIRECTLY (as "impersonation_by_user"
    # does below, not only via #extract_account_from_request) so this pins
    # extract_user_from_request's OWN rescue, not the separate one that
    # wraps #extract_account_from_request's full resolution.
    it "extract_user_from_request itself fails open and logs at ERROR when the user lookup raises unexpectedly" do
      allow(User).to receive(:find_by).and_raise("simulated DB blip")
      allow(Rails.logger).to receive(:error)
      request = request_with_bearer_token(valid_token)

      result = nil
      expect { result = Rack::Attack.extract_user_from_request(request) }.not_to raise_error
      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error).with(a_string_including("simulated DB blip"))
    end

    it "extract_account_from_request also fails open when the user lookup raises unexpectedly" do
      allow(User).to receive(:find_by).and_raise("simulated DB blip")
      allow(Rails.logger).to receive(:error)
      request = request_with_bearer_token(valid_token)

      result = nil
      expect { result = Rack::Attack.extract_account_from_request(request) }.not_to raise_error
      expect(result).to be_nil
    end

    # IMP-99e8e4701150 re-review (post-approval) — extract_user_from_request
    # is called directly by several throttles/safelists
    # (impersonation_by_user, admin_users, two_factor_reauth_by_user) AND
    # indirectly via extract_account_from_request, so one authenticated
    # request can reach it up to ~4 times. Each call now does a REAL
    # Security::JwtService.decode — a blacklist lookup (DB or Redis), not
    # the free in-memory JWT.decode this replaced (B1/N1 above) — so
    # re-running it per call is real, repeated cost. Same env-keyed
    # memoization pattern as extract_account_from_request below, and the
    # same "cache the nil too" requirement.
    describe "memoization of extract_user_from_request" do
      it "decodes the token only once per request even when called multiple times" do
        request = request_with_bearer_token(valid_token)
        expect(Security::JwtService).to receive(:decode).once.and_call_original

        first = Rack::Attack.extract_user_from_request(request)
        second = Rack::Attack.extract_user_from_request(request)

        expect(first).to eq(user)
        expect(second).to eq(user)
      end

      it "caches a fail-open nil result too, rather than re-decoding on every call" do
        request = request_with_bearer_token("garbage-not-a-real-token")
        expect(Security::JwtService).to receive(:decode).once.and_call_original

        first = Rack::Attack.extract_user_from_request(request)
        second = Rack::Attack.extract_user_from_request(request)

        expect(first).to be_nil
        expect(second).to be_nil
      end

      it "does not leak the memoized result across two different requests" do
        request1 = request_with_bearer_token(valid_token)
        request2 = request_with_bearer_token(valid_token)

        Rack::Attack.extract_user_from_request(request1)

        expect(Security::JwtService).to receive(:decode).once.and_call_original
        Rack::Attack.extract_user_from_request(request2)
      end

      # The property the review asked for directly: a request that actually
      # hits several user-keyed call sites in the same pass still decodes
      # once. admin_users' safelist calls extract_user_from_request directly
      # (as impersonation_by_user and two_factor_reauth_by_user do too, not
      # exercised here since both are path-gated to routes this generic mock
      # request doesn't match); extract_account_from_request reaches it
      # indirectly via #resolve_account_from_request. All three against the
      # SAME request object, as Rack::Attack itself would run them for one
      # real request.
      it "a request hitting multiple user-keyed safelists/throttles still decodes only once" do
        request = request_with_bearer_token(valid_token)
        expect(Security::JwtService).to receive(:decode).once.and_call_original

        Rack::Attack.safelists.fetch("admin_users").matched_by?(request)
        Rack::Attack.extract_user_from_request(request)
        Rack::Attack.extract_account_from_request(request)
      end
    end
  end

  # Review follow-up — every account-keyed throttle calls
  # extract_account_from_request at least twice (discriminator + limit:
  # proc), and several throttles share it, so a single request would
  # otherwise repeat the same resolution many times.
  describe "memoization of extract_account_from_request" do
    it "resolves the account only once per request even when called multiple times" do
      request = request_with_api_key(plaintext_key)
      expect(ApiKey).to receive(:active).once.and_call_original

      first = Rack::Attack.extract_account_from_request(request)
      second = Rack::Attack.extract_account_from_request(request)

      expect(first).to eq(account)
      expect(second).to eq(account)
    end

    it "caches a fail-open nil result too, rather than re-querying on every call" do
      request = request_with_api_key("garbage-not-a-real-key")
      expect(ApiKey).to receive(:active).once.and_call_original

      first = Rack::Attack.extract_account_from_request(request)
      second = Rack::Attack.extract_account_from_request(request)

      expect(first).to be_nil
      expect(second).to be_nil
    end

    # Review follow-up (finding 8) — the case above is genuine anonymity
    # (no matching key); this one is a NIL CAUSED BY A FAILURE, which is
    # the behaviour we deliberately chose to accept: a transient DB error
    # on the first lookup is cached and NOT retried by later throttles in
    # the same request (was: every call retried, and re-logged,
    # independently). Pinned so a future `||=`-style refactor that
    # reintroduces per-call retry-and-log goes red here.
    it "caches a failure-derived nil too, rather than retrying (and re-logging) the failing lookup on every call" do
      allow(ApiKey).to receive(:active).and_raise("simulated DB blip")
      allow(Rails.logger).to receive(:error)
      request = request_with_api_key(plaintext_key)

      first = Rack::Attack.extract_account_from_request(request)
      second = Rack::Attack.extract_account_from_request(request)

      expect(first).to be_nil
      expect(second).to be_nil
      expect(ApiKey).to have_received(:active).once
      expect(Rails.logger).to have_received(:error).once
    end

    it "does not leak the memoized result across two different requests" do
      request1 = request_with_api_key(plaintext_key)
      request2 = request_with_api_key(plaintext_key)

      Rack::Attack.extract_account_from_request(request1)

      expect(ApiKey).to receive(:active).once.and_call_original
      Rack::Attack.extract_account_from_request(request2)
    end
  end

  describe "the system_api_keys safelist" do
    it "safelists a real system API key end to end" do
      api_key.update!(metadata: { "is_system_key" => true })
      request = request_with_api_key(plaintext_key)

      expect(Rack::Attack.safelists["system_api_keys"].matched_by?(request)).to be true
    end

    # Review follow-up — the cache key must use the same salted scheme as
    # the stored digest, not a bare unsalted hash of the live credential.
    it "keys its cache entry on the salted ApiKey.hash_key digest, not a bare unsalted hash" do
      api_key.update!(metadata: { "is_system_key" => true })
      request = request_with_api_key(plaintext_key)

      Rack::Attack.safelists["system_api_keys"].matched_by?(request)

      expect(Rails.cache.exist?("system_api_key:#{ApiKey.hash_key(plaintext_key)}")).to be true
      expect(Rails.cache.exist?("system_api_key:#{Digest::SHA256.hexdigest(plaintext_key)}")).to be false
    end

    # Review follow-up — reuses ApiKey.find_by_key (the model's own
    # digest-and-lookup pair) instead of a second hand-rolled copy of it.
    it "uses ApiKey.find_by_key for the lookup rather than a duplicated digest-and-find" do
      api_key.update!(metadata: { "is_system_key" => true })
      request = request_with_api_key(plaintext_key)
      expect(ApiKey).to receive(:find_by_key).with(plaintext_key).and_call_original

      Rack::Attack.safelists["system_api_keys"].matched_by?(request)
    end

    it "does not safelist a key without the is_system_key metadata flag" do
      request = request_with_api_key(plaintext_key)

      expect(Rack::Attack.safelists["system_api_keys"].matched_by?(request)).to be false
    end

    it "does not safelist, and does not raise for, a garbage key" do
      request = request_with_api_key("garbage-not-a-real-key")

      result = nil
      expect { result = Rack::Attack.safelists["system_api_keys"].matched_by?(request) }.not_to raise_error
      expect(result).to be false
    end

    it "fails open (not safelisted) and logs at ERROR naming the reason when the lookup itself raises unexpectedly" do
      allow(ApiKey).to receive(:find_by).and_raise("simulated DB blip")
      allow(Rails.logger).to receive(:error)
      request = request_with_api_key(plaintext_key)

      result = nil
      expect { result = Rack::Attack.safelists["system_api_keys"].matched_by?(request) }.not_to raise_error
      expect(result).to be false
      expect(Rails.logger).to have_received(:error).with(a_string_including("simulated DB blip"))
    end
  end

  # IMP-24df1ec74489 — the "extreme_abuse" blocklist (rack_attack.rb:326)
  # runs UNCONDITIONALLY for every request (gated only by
  # rate_limiting_enabled?, true by default outside test) and calls
  # extract_account_from_request with NO rescue of its own. Before this
  # fix, ANY request carrying an X-API-Key header — valid or garbage —
  # 500s here. Forcing rate_limiting_enabled? true simulates production's
  # default (it is false only in test).
  describe "the extreme_abuse blocklist path (unrescued today, every request)", type: :request do
    it "does not 500 a request carrying an X-API-Key header, with rate limiting forced on as in production" do
      original = Rails.application.config.rate_limiting_enabled
      Rails.application.config.rate_limiting_enabled = true
      begin
        get "/up", headers: { "X-API-Key" => "garbage-not-a-real-key" }
      ensure
        Rails.application.config.rate_limiting_enabled = original
      end

      # `/up` always returns 200 when healthy; asserting the exact status
      # (review follow-up) rather than `not_to eq(500)`, which would also
      # pass on a 404 or 503 for the wrong reason.
      expect(response).to have_http_status(:ok)
    end
  end
end
