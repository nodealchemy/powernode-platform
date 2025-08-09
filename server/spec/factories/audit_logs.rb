FactoryBot.define do
  factory :audit_log do
    user { create(:user) }
    account
    action { "create" }
    resource_type { "User" }
    sequence(:resource_id) { |n| "resource_#{n}" }
    old_values { {} }
    new_values { {} }
    metadata { {} }
    ip_address { "192.168.1.1" }
    user_agent { "Mozilla/5.0 (Test Browser)" }
    source { "web" }
  end
end
