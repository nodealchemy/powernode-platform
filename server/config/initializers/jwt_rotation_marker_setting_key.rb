# frozen_string_literal: true

# Security::JwtKeyStore::ROTATION_MARKER is a PROTECTED SiteSetting key.
#
# Once set, an empty HS256 secret store refuses to fall back to the retired
# JWT_SECRET_KEY. Deleting it would quietly re-arm that fallback, and writing
# it would refuse the bootstrap secret, so neither is an ordinary admin edit:
# the REST site_settings doors and the policy-gated site_setting_set verb refuse
# it, and the only writer in code is JwtKeyStore.rotate_hmac!. (The human-only
# site_setting_set_protected verb can still change it, parked for a person.)
#
# `to_prepare`, as for the other protected keys: the registry is a class-level
# ivar on an autoloadable class. Registration is idempotent.
Rails.application.config.to_prepare do
  Ai::Tools::SiteSettingTool.register_key(
    Security::JwtKeyStore::ROTATION_MARKER,
    setting_type: "string",
    description: "When the HS256 user-token secret was last rotated (ISO 8601). Written by " \
                 "JwtKeyStore.rotate_hmac!. While set, an empty secret store fails closed instead " \
                 "of falling back to JWT_SECRET_KEY; reverting to the env secret means deleting " \
                 "both the stored secret and this marker, then restarting.",
    protected: true
  )
end
