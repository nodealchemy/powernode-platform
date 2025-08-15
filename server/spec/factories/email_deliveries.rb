FactoryBot.define do
  factory :email_delivery do
    recipient_email { "MyString" }
    subject { "MyString" }
    email_type { "MyString" }
    account { nil }
    user { nil }
    template { "MyString" }
    template_data { "MyText" }
    status { "MyString" }
    message_id { "MyString" }
    sent_at { "2025-08-11 12:02:21" }
    failed_at { "2025-08-11 12:02:21" }
    error_message { "MyText" }
  end
end
