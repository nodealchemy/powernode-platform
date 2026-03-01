# frozen_string_literal: true

# Marketing associations for Account model
# Loaded by the PowernodeMarketing engine via config.to_prepare decorator loading.
Account.class_eval do
  has_many :marketing_campaigns, class_name: "Marketing::Campaign", dependent: :destroy
  has_many :marketing_content_calendars, class_name: "Marketing::ContentCalendar", dependent: :destroy
  has_many :marketing_email_lists, class_name: "Marketing::EmailList", dependent: :destroy
  has_many :marketing_social_media_accounts, class_name: "Marketing::SocialMediaAccount", dependent: :destroy
end
