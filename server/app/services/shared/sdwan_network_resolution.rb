# frozen_string_literal: true

module Shared
  # The single copy of the SDWAN network-declaration semantics shared by the
  # platform's TWO network resolvers (IMP-8e1ac4a09e82).
  #
  # The bucketing landed with the composer's three-arm resolution
  # (IMP-94728a788498, extending 4db30efae) as private methods on
  # Ai::Provisioning::PlanComposerService. It is extracted here unchanged
  # because the direct/pool provisioning path needs the SAME decisions:
  #
  #   - Ai::Provisioning::PlanComposerService — AI-composed plans, resolves at
  #     compose time and stamps `network_id` into the plan step.
  #   - System::ProvisioningService#sdwan_network_for — instance-pool
  #     replenishment/acquisition, `system_provision_instance`, every direct
  #     caller; resolves at provision time.
  #
  # Two resolvers with two copies of "what does a blank value mean" is how one
  # bare template comes to produce two classes of node (composed → on fabric,
  # direct → networkless), so the vocabulary lives here once. What each
  # consumer DOES with a bucket still belongs to that consumer — the composer
  # turns :unusable into a compose-time clarification, the provisioner (which
  # has no clarification channel) logs it loudly — but the bucketing itself
  # has exactly one definition.
  #
  # Core purity: operates on a plain Hash and an Account. No `System::` /
  # `Sdwan::` constant is named here, and nothing in this module knows whether
  # the id it returns resolves — existence is the caller's question, because
  # only the extension can answer it.
  module SdwanNetworkResolution
    # The NodeTemplate config key / InstancePool metadata key declaring which
    # SDWAN network an instance joins (IMP-cdc1d0703e5a). A plain data key
    # travelling through the extension seam, not a reference to it.
    NETWORK_CONFIG_KEY = "sdwan_network_id"

    # Explicit fabric opt-out sentinel (IMP-94728a788498). With an account
    # default in play, "key absent / null / blank" must keep meaning "no
    # opinion" (builders emit those routinely — the swallowed-null class), so
    # a config surface that DELIBERATELY wants bare compute on an account with
    # a default needs a value that says so unmistakably. Compared
    # case-insensitively after strip. A network id is a UUID, so this string
    # could never collide with a real id.
    NETWORK_OPT_OUT_VALUE = "none"

    module_function

    # The value bucketing both resolvers share. Returns `[state, value]`.
    #
    # :absent   — null/blank/false, and numeric ZERO. "No opinion": inherit the
    #             next arm. Builders and forms that emit every key regardless
    #             produce `null` and `""` routinely, so neither may read as a
    #             loud failure (it would stop templates that work today) nor as
    #             an opt-out (it would silently detach them from a default).
    #             IMP-5a7aa42515d6: numeric 0 is that SAME phenomenon in a
    #             different type — a serializer that coerces an unset id field
    #             (`params[:sdwan_network_id].to_i`, a numeric column default, a
    #             form typing the field as a number) emits 0 out of exactly the
    #             "nobody chose anything" state that emits null and "". Nobody
    #             can write 0 meaning a network, so it can only be that.
    # :opt_out  — NETWORK_OPT_OUT_VALUE, case-insensitive. Deliberate bare
    #             compute; BEATS every later arm.
    # :unusable — non-blank and not a String, so structurally incapable of
    #             being a network id. The only bucket that is a
    #             misconfiguration rather than a choice. Deliberately NOT
    #             widened past zero to all numerics: network ids are UUIDs, so a
    #             NON-zero Integer is someone putting a number where a UUID
    #             belongs — a real decision, wrongly made, and the loud failure
    #             is the correct answer for it. Widening the whole type would
    #             trade one false alarm for the silent bare-compute defect this
    #             vocabulary exists to prevent.
    #             (A STRING "0" also stays out of :absent — it is a non-blank
    #             String, so it stamps and fails loud at RUN time via "sdwan
    #             network not found" rather than silently composing bare
    #             compute. Same reason existence is not decided here.)
    # :usable   — any other non-blank String, even if no such network exists.
    #             A dead id is already loud at run time ("sdwan network not
    #             found"); existence is not decided here.
    def classify_value(raw)
      return [ :absent, nil ] if raw.blank?
      return [ :absent, nil ] if raw.is_a?(Numeric) && raw.zero?
      return [ :unusable, raw ] unless raw.is_a?(String)

      value = raw.strip
      return [ :opt_out, value ] if value.casecmp?(NETWORK_OPT_OUT_VALUE)

      [ :usable, value ]
    end

    # What a config/metadata blob says, as the same `[state, value]` shape.
    # Tolerates string and symbol keys (jsonb round-trips strings, in-memory
    # writers may use symbols) and a non-Hash blob.
    def classify_config(config)
      return [ :absent, nil ] unless config.is_a?(Hash)
      return [ :absent, nil ] unless config.key?(NETWORK_CONFIG_KEY) || config.key?(NETWORK_CONFIG_KEY.to_sym)

      classify_value(config[NETWORK_CONFIG_KEY] || config[NETWORK_CONFIG_KEY.to_sym])
    end

    # What the ACCOUNT says about default fabric attachment. DB-driven config
    # (Account#settings jsonb) set through the existing account-settings
    # surface; no env var, seed, or hardcoded id.
    #
    # Identical bucketing to the config arm — :opt_out here simply means
    # "explicitly no default", which the resolvers treat like :absent since
    # there is no further arm for it to beat.
    def classify_account_default(account)
      classify_value(account&.default_sdwan_network_setting)
    end
  end
end
