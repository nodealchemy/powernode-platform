# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SystemSettings do
  describe ".general_settings" do
    it "reads the flat general keys admin_settings_controller writes, nil when unset" do
      AdminSetting.find_or_create_by(key: "system_name") { |s| s.value = "Powernode" }

      settings = described_class.general_settings

      expect(settings["system_name"]).to eq("Powernode")
      expect(settings["registration_enabled"]).to be_nil
    end
  end

  describe ".update_general_settings!" do
    it "writes flat keys as their string value" do
      updated = described_class.update_general_settings!("registration_enabled" => false)

      expect(updated).to eq("registration_enabled" => false)
      expect(AdminSetting.find_by(key: "registration_enabled").value).to eq("false")
    end

    it "fans a Hash value out into dotted sub-keys, mirroring the pre-move controller writer" do
      updated = described_class.update_general_settings!(
        "system_notifications" => { "email_enabled" => true, "sms_enabled" => false }
      )

      expect(updated).to eq(
        "system_notifications.email_enabled" => true,
        "system_notifications.sms_enabled" => false
      )
      expect(AdminSetting.find_by(key: "system_notifications.email_enabled").value).to eq("true")
      expect(AdminSetting.find_by(key: "system_notifications.sms_enabled").value).to eq("false")
    end
  end

  describe ".registration_enabled? / .email_verification_required?" do
    # Pins the exact string->bool mapping config_controller.rb used before
    # this method moved here, so an operator's existing stored value keeps
    # meaning the same thing.
    {
      "true" => true, "1" => true, "yes" => true, "on" => true, "enabled" => true,
      "false" => false, "0" => false, "no" => false, "off" => false, "disabled" => false,
      "TRUE" => true, "  true  " => true,
      "garbage" => true, "" => true
    }.each do |stored, expected|
      it "reads #{stored.inspect} as #{expected}" do
        AdminSetting.find_or_create_by(key: "registration_enabled") { |s| s.value = stored }

        expect(described_class.registration_enabled?).to eq(expected)
      end
    end

    it "defaults to true (registration) / true (email verification) when the row does not exist" do
      expect(described_class.registration_enabled?).to be(true)
      expect(described_class.email_verification_required?).to be(true)
    end

    it "defaults to true when the lookup raises" do
      allow(AdminSetting).to receive(:find_by).and_raise(StandardError, "db down")

      expect(described_class.registration_enabled?).to be(true)
    end
  end

  describe ".email_settings / .update_email_settings!" do
    it "round-trips a plain (non-secret) field" do
      described_class.update_email_settings!("smtp_host" => "smtp.example.com")

      expect(described_class.email_settings[:smtp_host]).to eq("smtp.example.com")
    end

    it "normalizes the 'provider' param key to email_provider, like the pre-move controller" do
      described_class.update_email_settings!("provider" => "sendgrid")

      expect(AdminSetting.find_by(key: "email_provider").value).to eq("sendgrid")
      expect(described_class.email_settings[:provider]).to eq("sendgrid")
    end

    it "encrypts a _password/_api_key/_secret_key suffixed value via CredentialEncryptionService and decrypts it back on read" do
      described_class.update_email_settings!("smtp_password" => "hunter2")

      raw = AdminSetting.find_by(key: "smtp_password_encrypted").value
      expect(raw).not_to include("hunter2")
      expect(described_class.email_settings[:smtp_password]).to eq("hunter2")
    end

    it "returns empty string for an unset secret rather than nil" do
      expect(described_class.email_settings[:sendgrid_api_key]).to eq("")
    end

    it "treats a pre-encryption plaintext value as its literal (backward compatibility), same as the pre-move controller" do
      AdminSetting.set("smtp_password_encrypted", "plaintext-legacy-value")

      expect(described_class.email_settings[:smtp_password]).to eq("plaintext-legacy-value")
    end
  end

  describe ".redis_config / .update_redis_config! (fc-38 decision #3 — password is encrypted, never in the blob)" do
    # fc-38 review item #4: unlike email's decrypt_secret (which falls back
    # to treating undecryptable ciphertext as the LITERAL credential, for
    # pre-encryption legacy rows only email ever had), redis/vault have no
    # such legacy plaintext-in-an-_encrypted-key case — a decrypt failure
    # here can only mean real corruption or a key-rotation gap, and the
    # ciphertext itself must never be handed anywhere as if it were the
    # actual password.
    # round 3 review item #2 (LOW): a decrypt failure used to merge
    # "password" => nil straight over ENV["REDIS_PASSWORD"]'s default,
    # sending the actual Redis connection out UNAUTHENTICATED instead of
    # with whatever credential was configured before the corruption. A
    # decrypt failure must fall back to the blob's own password (ENV or the
    # default), never nil — never the ciphertext either.
    it "falls back to the blob's own password (e.g. the ENV default), never nil, when the stored value fails to decrypt" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("env-fallback-password")
      AdminSetting.create!(key: "redis_config_password_encrypted", value: "not-valid-ciphertext")
      expect(Rails.logger).to receive(:error) do |message|
        expect(message).to include("redis_config_password")
        expect(message).to include("DecryptionError")
        expect(message).not_to include("not-valid-ciphertext")
      end

      expect(described_class.redis_config["password"]).to eq("env-fallback-password")
    end

    it "falls back to the non-secret blob's own password (e.g. the ENV default) when no encrypted row exists yet" do
      config = described_class.redis_config

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).to be_nil
      expect(config["password"]).to eq(AdminSetting.redis_config["password"])
    end

    it "update_redis_config! with no password key present leaves the encrypted row untouched (masked-resubmission skip)" do
      password = "redis-unit-#{SecureRandom.hex(4)}"
      described_class.update_redis_config!({ "password" => password, "host" => "127.0.0.1" })
      before_value = AdminSetting.find_by(key: "redis_config_password_encrypted").value

      described_class.update_redis_config!({ "host" => "192.168.1.1" })

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted").value).to eq(before_value)
      expect(described_class.redis_config["password"]).to eq(password)
      expect(AdminSetting.redis_config["host"]).to eq("192.168.1.1")
    end

    it "update_redis_config! never writes 'password' into the non-secret AdminSetting.redis_config blob" do
      described_class.update_redis_config!({ "password" => "redis-unit-blob-check", "host" => "127.0.0.1" })

      expect(AdminSetting.find_by(key: "redis_config").value).not_to include("redis-unit-blob-check")
    end

    # round 4 review (root cause): AdminSetting.update_redis_config used to
    # deep-merge `current_config = redis_config` — which ITSELF deep-merges
    # default_redis_config (ENV["REDIS_PASSWORD"]/ENV["REDIS_URL"]) — into
    # whatever got saved, and wrote THAT merged result back into the blob.
    # A save that never even mentions "password" (e.g. changing only "host")
    # silently baked the current ENV redis password into the blob. The old
    # fix (round 3 item #3(b)) only stripped that baked-in value back out of
    # the blob via strip_secret_keys_from_blob! — but that helper's OWN
    # backfill (round 3 item #1) saw a "password" present with no encrypted
    # row yet and ENCRYPTED IT, creating a redis_config_password_encrypted
    # row that then PERMANENTLY SHADOWS ENV: rotating REDIS_PASSWORD and
    # restarting would keep sending the old (captured) password — a live
    # auth outage — and a later clear_password: true would have nothing to
    # revert to but that same stale captured value on the next save.
    #
    # The actual fix is at the source: AdminSetting.update_redis_config now
    # merges the submitted config into the RAW STORED blob only (never into
    # the ENV-merged read-time result), so a host-only save never introduces
    # a "password" key into the blob in the first place — nothing for the
    # backfill to (wrongly) encrypt.
    it "a host-only save with REDIS_PASSWORD set creates no encrypted row and writes no password into the blob" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("env-redis-password-should-never-be-captured")

      described_class.update_redis_config!({ "host" => "127.0.0.1" })

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).to be_nil
      blob = AdminSetting.find_by(key: "redis_config").value
      expect(JSON.parse(blob)).not_to have_key("password")
    end

    it "reflects a REDIS_PASSWORD rotation immediately after a host-only save (no stale value captured into a row)" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("first-env-password")
      described_class.update_redis_config!({ "host" => "127.0.0.1" })
      expect(described_class.redis_config["password"]).to eq("first-env-password")

      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("rotated-env-password")

      expect(described_class.redis_config["password"]).to eq("rotated-env-password")
    end

    # The regression this specifically guards: the OLD destroy-last ordering
    # was a workaround for the backfill re-encrypting an ENV-derived value
    # the instant the row was cleared — fixing the root cause (above) means
    # a later, unrelated save can no longer resurrect a cleared password via
    # that path either.
    it "a cleared password stays cleared after a later unrelated save, even with REDIS_PASSWORD set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("env-password-after-clear")
      described_class.update_redis_config!({ "password" => "to-be-cleared", "host" => "127.0.0.1" })
      described_class.update_redis_config!({}, clear_password: true)

      described_class.update_redis_config!({ "host" => "192.168.1.1" })

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).to be_nil
      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob).not_to have_key("password")
      expect(described_class.redis_config["password"]).to eq("env-password-after-clear")
    end

    # round 3 review item #3(b): a blank "password" means "unchanged" (see
    # the masked-resubmission-skip test above), so there was no way to
    # actually CLEAR a saved password short of manually deleting the
    # encrypted row out-of-band. clear_password: true is the explicit signal
    # a blank value can't be: it destroys the encrypted row so .redis_config
    # falls back to the blob's own default (ENV or none) instead.
    it "clear_password: true removes the encrypted row so redis_config falls back to the ENV/blob default" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("env-fallback-after-clear")
      described_class.update_redis_config!({ "password" => "to-be-cleared", "host" => "127.0.0.1" })
      expect(described_class.redis_config["password"]).to eq("to-be-cleared")

      described_class.update_redis_config!({}, clear_password: true)

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).to be_nil
      expect(described_class.redis_config["password"]).to eq("env-fallback-after-clear")
    end
  end

  describe "redis url credential handling (round 4 review — root cause)" do
    # round 3 item #4 introduced sanitize_url_in_blob!, which stripped
    # credentials from a URL the ENV-merge bug (see the .redis_config /
    # .update_redis_config! describe block above) had baked into the blob —
    # but a SANITIZED credentialed ENV URL still persisted (now with its
    # userinfo silently removed), and that stripped blob value then beat ENV
    # at read time: redis_url_from_config uses config["url"] directly when
    # present, so the resolved URL lost its password entirely — a live
    # NOAUTH regression for any deployment using REDIS_URL=redis://:pw@host.
    # The actual fix is the same one as "password": a host-only (or any
    # unrelated-field) save must never introduce a "url" key at all when the
    # blob didn't already have one — nothing for the sanitizer to (wrongly)
    # persist a stripped copy of.
    it "a host-only save with a credentialed ENV REDIS_URL writes no url into the blob, and the resolved config keeps the credential" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_URL", nil).and_return("redis://:env-secret-password@redis.internal:6379/0")

      described_class.update_redis_config!({ "host" => "127.0.0.1" })

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob).not_to have_key("url")
      expect(described_class.redis_config["url"]).to eq("redis://:env-secret-password@redis.internal:6379/0")
    end

    it "a credentialed ENV REDIS_URL survives an unrelated save (connect_timeout) — the resolved config still carries the credential" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_URL", nil).and_return("redis://:env-url-password@redis.internal:6379/0")

      described_class.update_redis_config!({ "connect_timeout" => 10 })

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob).not_to have_key("url")
      expect(described_class.redis_config["url"]).to eq("redis://:env-url-password@redis.internal:6379/0")
      expect(AdminSetting.redis_config["connect_timeout"]).to eq(10)
    end

    it "leaves a URL with no credentials untouched" do
      described_class.update_redis_config!({ "url" => "redis://redis.internal:6379/0" })

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob["url"]).to eq("redis://redis.internal:6379/0")
    end

    # An admin-SUBMITTED credentialed URL (not ENV-derived) still gets
    # sanitized in the blob by sanitize_url_in_blob! — this is the
    # defense-in-depth case that method still exists for (the controller
    # also rejects this at the request boundary with a 422; this pins the
    # service layer independently).
    it "still sanitizes an admin-submitted credentialed URL in the blob" do
      described_class.update_redis_config!({ "url" => "redis://:admin-typed-password@redis.internal:6379/0" })

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob["url"]).to eq("redis://redis.internal:6379/0")
      expect(blob["url"]).not_to include("admin-typed-password")
    end
  end

  describe ".url_contains_credentials? / .strip_url_credentials (round 4 review — tightened to URI parsing)" do
    # The old hand-rolled regex (`[^/@]*@` for the userinfo segment) could
    # not reach an "@" past an unencoded "/" in what was meant as a
    # password: `[^/@]*` stops the instant it hits "/", so the pattern never
    # finds the "@" that follows and the whole match silently fails —
    # url_contains_credentials? returned false for a URL that DOES carry a
    # credential. URI.parse is authoritative instead of a hand-maintained
    # pattern, and — cheaply, as a side effect of using a real parser —
    # fails CLOSED (treats as credentialed) on anything it can't parse at
    # all, rather than defaulting an unparseable string to "safe".
    it "detects a credential even when the password contains an unencoded '/'" do
      expect(described_class.url_contains_credentials?("redis://:my/pass@host:6379/0")).to be(true)
    end

    it "still detects the ordinary password-only and user:password forms" do
      expect(described_class.url_contains_credentials?("redis://:plainpass@host:6379/0")).to be(true)
      expect(described_class.url_contains_credentials?("rediss://user:pass@host:6379/0")).to be(true)
    end

    it "returns false for a URL with no credentials" do
      expect(described_class.url_contains_credentials?("redis://host:6379/0")).to be(false)
    end

    it "returns false for a blank/nil URL" do
      expect(described_class.url_contains_credentials?(nil)).to be(false)
      expect(described_class.url_contains_credentials?("")).to be(false)
    end

    it "fails closed (treats as credentialed) for a string URI can't parse at all" do
      expect(described_class.url_contains_credentials?("not a url at all")).to be(true)
    end

    # fc-38 round 4 RE-review (security, MEDIUM): strip_url_credentials used
    # to return an unparseable URL UNCHANGED — failing OPEN. Every shape
    # below is a REAL password Ruby's URI.parse can't handle (unencoded "/",
    # "@", "#", "?", or a literal space in the userinfo), and this method is
    # called UNCONDITIONALLY on every infrastructure_config GET/PUT response
    # (never gated by url_contains_credentials? first) — returning it
    # unchanged leaked the plaintext credential straight into the response
    # body, and left it un-sanitized in the blob via sanitize_url_in_blob!.
    # It must redact on a parse failure, not pass the value through.
    it "redacts credentials from an unparseable URL rather than passing it through" do
      [
        "redis://:my/pass@host:6379/0",
        "redis://:p@ss@host:6379/0",
        "redis://:p#w@host:6379/0",
        "redis://:p?w@host:6379/0",
        "redis://:p w@host:6379/0"
      ].each do |url|
        result = described_class.strip_url_credentials(url)
        expect(result).not_to match(/my\/pass|p@ss|p#w|p\?w|p w/), "expected #{url.inspect} to be redacted, got #{result.inspect}"
        expect(result).to eq("redis://host:6379/0")
      end
    end

    # fc-38 final review: the regex fallback itself still failed OPEN on two
    # shapes — a newline inside the userinfo ("." doesn't cross "\n" without
    # /m) and anything before the scheme (the old "\A" anchor) — both came
    # back byte-for-byte unchanged, credential included.
    it "redacts a credential whose userinfo contains a newline" do
      result = described_class.strip_url_credentials("redis://:p\nw@host:6379/0")
      expect(result).not_to include("p\nw")
      expect(result).to eq("redis://host:6379/0")
    end

    it "redacts a credential when characters precede the scheme" do
      result = described_class.strip_url_credentials(" redis://:p w@host:6379/0")
      expect(result).not_to include("p w")
      expect(result).to eq("redis://host:6379/0")
    end

    it "returns a fixed placeholder, never the input, when an '@' survives the fallback" do
      result = described_class.strip_url_credentials("user:dummy secret@host:6379/0")
      expect(result).not_to include("dummy secret")
      expect(result).to eq("[redacted: unparseable URL with credentials]")
    end

    it "never raises on strip_url_credentials for an unparseable string — returns it unchanged when there's no credential to redact" do
      expect(described_class.strip_url_credentials("not a url at all")).to eq("not a url at all")
    end

    it "leaves a credential-free URL byte-for-byte unchanged" do
      expect(described_class.strip_url_credentials("redis://host:6379/0")).to eq("redis://host:6379/0")
    end
  end

  describe ".vault_config / .update_vault_config! (fc-38 decision #3 — role_id/secret_id are encrypted, never in the blob)" do
    it "returns empty-string role_id/secret_id and nil vault_addr when nothing is configured" do
      config = described_class.vault_config

      expect(config).to eq("vault_addr" => nil, "vault_role_id" => "", "vault_secret_id" => "")
    end

    # fc-38 review item #2: before the data migration runs (or for any row
    # written before this hardening shipped), the blob may still hold a
    # plaintext vault_role_id/vault_secret_id with no _encrypted row yet.
    # .redis_config already falls back to the blob's own value in that case;
    # .vault_config must do the same, or Vault authentication (and the admin
    # UI) would silently see blank credentials until the migration runs.
    it "falls back to the blob's plaintext vault_role_id/vault_secret_id when no encrypted row exists yet" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "pre-migration-role", "vault_secret_id" => "pre-migration-secret" }.to_json
      )

      config = described_class.vault_config

      expect(AdminSetting.exists?(key: "vault_role_id_encrypted")).to be(false)
      expect(config["vault_role_id"]).to eq("pre-migration-role")
      expect(config["vault_secret_id"]).to eq("pre-migration-secret")
    end

    it "prefers the encrypted row over the blob's plaintext once one exists" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "stale-plaintext-role" }.to_json
      )
      described_class.update_vault_config!({ "vault_role_id" => "fresh-encrypted-role" })

      expect(described_class.vault_config["vault_role_id"]).to eq("fresh-encrypted-role")
    end

    it "update_vault_config! writes only the keys present, leaving the others untouched" do
      described_class.update_vault_config!({ "vault_addr" => "http://vault.example.internal:8200", "vault_role_id" => "role-a" })
      described_class.update_vault_config!({ "vault_secret_id" => "secret-b" })

      config = described_class.vault_config
      expect(config["vault_addr"]).to eq("http://vault.example.internal:8200")
      expect(config["vault_role_id"]).to eq("role-a")
      expect(config["vault_secret_id"]).to eq("secret-b")
    end

    it "never writes vault_role_id/vault_secret_id into the vault_config blob" do
      described_class.update_vault_config!({ "vault_role_id" => "role-blob-check", "vault_secret_id" => "secret-blob-check" })

      expect(AdminSetting.find_by(key: "vault_config")&.value.to_s).not_to include("role-blob-check")
      expect(AdminSetting.find_by(key: "vault_config")&.value.to_s).not_to include("secret-blob-check")
    end

    # fc-38 review item #3(b): update_vault_config! reads raw_vault_blob and
    # merges "vault_addr" into it — if the blob already carries a stale
    # vault_role_id/vault_secret_id (a leftover from before this hardening,
    # or a row the migration hasn't reached yet), a vault_addr-only save
    # would round-trip that stale value straight back into the blob via the
    # merge, keeping the plaintext alive indefinitely.
    it "strips a pre-existing plaintext vault_role_id/vault_secret_id from the blob on a vault_addr-only save" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "stale-plaintext-role", "vault_secret_id" => "stale-plaintext-secret" }.to_json
      )

      described_class.update_vault_config!({ "vault_addr" => "http://vault.updated.internal:8200" })

      blob = JSON.parse(AdminSetting.find_by(key: "vault_config").value)
      expect(blob).to eq("vault_addr" => "http://vault.updated.internal:8200")
    end

    # round 3 review item #1 (MEDIUM): the strip-on-write helper used to just
    # delete a plaintext field from the blob once it was present — it never
    # checked whether an _encrypted row existed FIRST. A host-only (or
    # addr-only) save on a row from before the encryption migration ran
    # stripped the plaintext straight into the void: no encrypted row ever
    # got created, so the credential was gone, not migrated.
    it "encrypts a pre-migration plaintext redis password into its own row before stripping it, on a host-only save" do
      AdminSetting.create!(
        key: "redis_config",
        value: { "host" => "127.0.0.1", "port" => 6379, "password" => "pre-migration-redis-password" }.to_json
      )

      described_class.update_redis_config!({ "host" => "192.168.1.1" })

      encrypted = AdminSetting.find_by(key: "redis_config_password_encrypted")
      expect(encrypted).not_to be_nil
      expect(encrypted.value).not_to include("pre-migration-redis-password")
      expect(described_class.redis_config["password"]).to eq("pre-migration-redis-password")
      expect(AdminSetting.find_by(key: "redis_config").value).not_to include("pre-migration-redis-password")
    end

    it "encrypts pre-migration plaintext vault_role_id/vault_secret_id into their own rows before stripping them, on a vault_addr-only save" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "pre-migration-role", "vault_secret_id" => "pre-migration-secret" }.to_json
      )

      described_class.update_vault_config!({ "vault_addr" => "http://vault.updated.internal:8200" })

      expect(AdminSetting.find_by(key: "vault_role_id_encrypted")).not_to be_nil
      expect(AdminSetting.find_by(key: "vault_secret_id_encrypted")).not_to be_nil
      config = described_class.vault_config
      expect(config["vault_role_id"]).to eq("pre-migration-role")
      expect(config["vault_secret_id"]).to eq("pre-migration-secret")
    end

    # round 3 review item #3(b): same "blank means unchanged, so there's no
    # way to clear it" gap as redis's password — clear_vault_role_id/
    # clear_vault_secret_id are the explicit signal.
    it "clear_vault_role_id: true removes the encrypted role_id row, leaving secret_id untouched" do
      described_class.update_vault_config!({ "vault_role_id" => "role-to-clear", "vault_secret_id" => "secret-to-keep" })

      described_class.update_vault_config!({}, clear_vault_role_id: true)

      expect(AdminSetting.find_by(key: "vault_role_id_encrypted")).to be_nil
      config = described_class.vault_config
      expect(config["vault_role_id"]).to eq("")
      expect(config["vault_secret_id"]).to eq("secret-to-keep")
    end

    it "clear_vault_secret_id: true removes the encrypted secret_id row, leaving role_id untouched" do
      described_class.update_vault_config!({ "vault_role_id" => "role-to-keep", "vault_secret_id" => "secret-to-clear" })

      described_class.update_vault_config!({}, clear_vault_secret_id: true)

      expect(AdminSetting.find_by(key: "vault_secret_id_encrypted")).to be_nil
      config = described_class.vault_config
      expect(config["vault_role_id"]).to eq("role-to-keep")
      expect(config["vault_secret_id"]).to eq("")
    end
  end

  describe "proxy delegation (thin passthrough to the ServiceConfiguration concern already on AdminSetting)" do
    it "delegates .proxy_url_config" do
      expect(AdminSetting).to receive(:reverse_proxy_url_config).and_return(enabled: true)

      expect(described_class.proxy_url_config).to eq(enabled: true)
    end

    it "delegates .update_proxy_url_config!" do
      expect(AdminSetting).to receive(:update_reverse_proxy_url_config).with({ enabled: true }).and_return(enabled: true)

      expect(described_class.update_proxy_url_config!({ enabled: true })).to eq(enabled: true)
    end

    it "delegates .validate_proxy_host" do
      expect(AdminSetting).to receive(:validate_proxy_host).with("example.com").and_return(valid: true)

      expect(described_class.validate_proxy_host("example.com")).to eq(valid: true)
    end

    it "delegates .generate_api_url" do
      expect(AdminSetting).to receive(:generate_api_url).with({ forwarded_host: "example.com" }).and_return(base_url: "https://example.com")

      expect(described_class.generate_api_url({ forwarded_host: "example.com" })).to eq(base_url: "https://example.com")
    end

    it "delegates .add_trusted_host" do
      expect(AdminSetting).to receive(:add_trusted_host).with("*.example.com").and_return(true)

      expect(described_class.add_trusted_host("*.example.com")).to be(true)
    end

    it "delegates .remove_trusted_host" do
      expect(AdminSetting).to receive(:remove_trusted_host).with("*.example.com").and_return(true)

      expect(described_class.remove_trusted_host("*.example.com")).to be(true)
    end

    it "delegates .test_proxy_headers" do
      headers = { "X-Forwarded-Host" => "example.com" }
      expect(AdminSetting).to receive(:test_proxy_headers).with(headers).and_return(proxy_context: {})

      expect(described_class.test_proxy_headers(headers)).to eq(proxy_context: {})
    end
  end
end
