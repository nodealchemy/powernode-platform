# frozen_string_literal: true

# IMP-d0403597f455 — register the site-wide human-session category list as a
# PROTECTED operator-configurable key.
#
# Ai::Approvals::HumanSessionPolicy reads this key to decide which parked
# requests only a person may decide in their own session. Unregistered, it was
# an ordinary row: Api::V1::SiteSettingsController#refuse_protected_key_write
# only refuses REGISTERED protected keys, so any settings.manage admin session —
# an impersonation or account-switch session included — could write it to [] and
# drop the own-session requirement for every category not separately marked.
#
# Registering it PROTECTED narrows every door at once: the REST twin refuses it,
# the policy-gated site_setting_set verb refuses it (SiteSettingTool
# #write_key_error), and the only write path left is the human-only
# site_setting_set_protected, which parks for a person to confirm in their own
# session and runs as that person. Disarming the control that decides what needs
# a person is itself a person's decision.
#
# `to_prepare`, not `after_initialize`: the registry is a class-level ivar on an
# autoloadable class, so a reload would wipe it and leave the key silently
# absent — the very state this closes. Registration is idempotent; re-registering
# the same shape is a no-op and a conflicting shape raises.
Rails.application.config.to_prepare do
  Ai::Tools::SiteSettingTool.register_key(
    Ai::Approvals::HumanSessionPolicy::SETTING_KEY,
    setting_type: "json",
    description: "Array of File.fnmatch patterns naming the approval categories only a person " \
                 "may decide, in their own session. Unset (or not a list of strings) means " \
                 "HumanSessionPolicy::DEFAULT_CATEGORY_PATTERNS applies. Shrinking it removes " \
                 "that requirement, so it is written only through the human-only verb.",
    protected: true
  )
end
