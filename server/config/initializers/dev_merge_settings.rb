# frozen_string_literal: true

# IMP-e82f619dde7a — the operator's declaration of the private extensions that
# exist in this deployment's ecosystem but are not installed on this host.
# Ai::DevMerge::ForbiddenNames unions it with what the host can see for itself;
# without it, a deployed control plane that composes no private extension
# cannot know their names and dev_merge_increment refuses to publish.
#
# PROTECTED, like the human-session category list: removing a name disarms the
# refusal that keeps it out of published history, so the only write door is
# the human-only site_setting_set_protected. The value check refuses anything
# but a list of slugs. `to_prepare`, so a reload re-registers both.
Rails.application.config.to_prepare do
  Ai::Tools::SiteSettingTool.register_key(
    Ai::DevMerge::ForbiddenNames::SETTING_KEY,
    setting_type: "json",
    description: "JSON list of the private extension slugs that exist in this deployment but are not " \
                 "installed here; dev_merge_increment refuses to publish a commit naming one. [] declares " \
                 "that none exist. Unset on a host that cannot see them makes the merge refuse.",
    protected: true,
    # An instance (the dev loop) may ASK for a change; only a person decides it.
    machine_parkable: true
  )
  SiteSetting.register_value_check(Ai::DevMerge::ForbiddenNames::SETTING_KEY) do |value|
    Ai::DevMerge::ForbiddenNames.declaration_problem(value)
  end
end
