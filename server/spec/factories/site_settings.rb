FactoryBot.define do
  factory :site_setting do
    sequence(:key) { |n| "test_setting_#{n}" }
    value { "test_value" }
    description { "Test setting description" }
    setting_type { "string" }
    is_public { false }

    trait :string_setting do
      setting_type { "string" }
      value { "Sample string value" }
    end

    trait :text_setting do
      setting_type { "text" }
      value { "This is a longer text value that could contain multiple sentences." }
    end

    trait :boolean_setting do
      key { "enable_feature" }
      setting_type { "boolean" }
      value { "true" }
    end

    trait :integer_setting do
      key { "max_items" }
      setting_type { "integer" }
      value { "100" }
    end

    trait :json_setting do
      key { "config_options" }
      setting_type { "json" }
      value { '{"option1": true, "option2": "value"}' }
    end

    trait :public_setting do
      is_public { true }
    end

    trait :footer_setting do
      key { "site_name" }
      value { "Powernode Platform" }
      is_public { true }
      description { "The name of the site displayed in the footer" }
    end

    trait :social_setting do
      key { "social_twitter" }
      value { "https://twitter.com/powernode" }
      is_public { true }
      description { "Twitter social media URL" }
    end
  end
end
