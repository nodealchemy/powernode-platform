# frozen_string_literal: true

# Register the operator's list of categories a promotion grant may name
# (Ai::PromotionGrants::Grantable::SETTING_KEY) as a PROTECTED key, exactly as
# the human-session category list is (human_session_setting_keys.rb): widening
# it lets a person's grant stand in for an approval on a new kind of action, so
# it is written only through the human-only site_setting_set_protected verb,
# and the REST twin refuses it. Grantable's hard exclusions hold whatever the
# list says. `to_prepare` for the same reload reason as that initializer.
Rails.application.config.to_prepare do
  Ai::Tools::SiteSettingTool.register_key(
    Ai::PromotionGrants::Grantable::SETTING_KEY,
    setting_type: "json",
    description: "Array of the gated action categories a time-boxed promotion grant may name. Unset (or not a " \
                 "list of strings) means [\"release.promote\"]. Destructive, human-only, key, kill-switch and " \
                 "site-setting categories are excluded whatever it says, and each category also needs an " \
                 "installed extension's grant catalog.",
    protected: true
  )
end
