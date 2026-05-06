# frozen_string_literal: true

require "rails_helper"

# Regression test for the May-2026 bug where Marketing::* models
# inherited from ApplicationRecord without setting self.table_name,
# causing Rails to default to namespace-stripped names (e.g. "campaigns")
# that didn't match the marketing_-prefixed migration tables.
#
# Hardcoded list intentionally — Rails.application.eager_load! triggers
# unrelated autoload issues in the broader codebase, so we verify each
# Marketing model individually. New models added under Marketing::
# should be appended here when introduced.
RSpec.describe "Marketing namespace table_name discipline" do
  EXPECTED_TABLES = {
    Marketing::Campaign           => "marketing_campaigns",
    Marketing::CampaignContent    => "marketing_campaign_contents",
    Marketing::CampaignEmailList  => "marketing_campaign_email_lists",
    Marketing::CampaignMetric     => "marketing_campaign_metrics",
    Marketing::ContentCalendar    => "marketing_content_calendars",
    Marketing::EmailList          => "marketing_email_lists",
    Marketing::EmailSubscriber    => "marketing_email_subscribers",
    Marketing::SocialMediaAccount => "marketing_social_media_accounts",
    Marketing::WaitlistSignup     => "marketing_waitlist_signups"
  }.freeze

  EXPECTED_TABLES.each do |klass, expected_table|
    it "#{klass} maps to #{expected_table}" do
      expect(klass.table_name).to eq(expected_table),
        "#{klass}.table_name was #{klass.table_name.inspect}; expected #{expected_table.inspect}. " \
        "Fix: add `self.table_name = #{expected_table.inspect}` immediately after the class declaration."
    end
  end
end
