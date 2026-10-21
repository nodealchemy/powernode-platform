# frozen_string_literal: true

FactoryBot.define do
  # A grant issued from a person's own session (the only door that may issue
  # one). `environment` defaults to the account's protected `ops` plane.
  factory :ai_promotion_grant, class: "Ai::PromotionGrant" do
    account
    granted_by { association :user, account: account }
    agent { association :ai_agent, account: account }
    environment { account.environments.find_by!(slug: "ops") }
    action_category { "release.promote" }
    module_ids { [] }
    max_uses { nil }
    expires_at { 4.hours.from_now }
    reason { "Ship the release train into ops while I am in the meeting" }
    issuing_origin { Ai::ApprovalDecision::REST_SESSION }
  end
end
