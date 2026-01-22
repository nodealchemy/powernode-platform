# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_questionnaire_response, class: "SupplyChain::QuestionnaireResponse" do
    association :vendor, factory: :supply_chain_vendor
    association :template, factory: :supply_chain_questionnaire_template
    association :account
    requested_by { nil }
    status { "pending" }
    access_token { SecureRandom.urlsafe_base64(32) }
    sent_at { Time.current }
    expires_at { 30.days.from_now }
    responses { {} }
    section_scores { {} }
    metadata { {} }

    trait :pending do
      status { "pending" }
      started_at { nil }
      submitted_at { nil }
      reviewed_at { nil }
    end

    trait :in_progress do
      status { "in_progress" }
      started_at { 2.days.ago }
      responses do
        {
          "q1" => { answer: "yes", answered_at: 2.days.ago.iso8601 }
        }
      end
    end

    trait :submitted do
      status { "submitted" }
      started_at { 5.days.ago }
      submitted_at { Time.current }
      responses do
        {
          "q1" => { answer: "yes", answered_at: 3.days.ago.iso8601 },
          "q2" => { answer: "We follow best practices", answered_at: 2.days.ago.iso8601 },
          "q3" => { answer: "yes", answered_at: 1.day.ago.iso8601 }
        }
      end
      overall_score { rand(60..100) }
      section_scores do
        {
          "section1" => rand(60..100),
          "section2" => rand(60..100)
        }
      end
    end

    trait :reviewed do
      status { "reviewed" }
      started_at { 2.weeks.ago }
      submitted_at { 1.week.ago }
      reviewed_at { Time.current }
      association :reviewed_by, factory: :user
      review_notes { "Assessment completed successfully. Vendor meets requirements." }
      responses do
        {
          "q1" => { answer: "yes", answered_at: 10.days.ago.iso8601 },
          "q2" => { answer: "Comprehensive security program in place", answered_at: 9.days.ago.iso8601 },
          "q3" => { answer: "yes", answered_at: 8.days.ago.iso8601 }
        }
      end
      overall_score { rand(75..100) }
      section_scores do
        {
          "section1" => rand(75..100),
          "section2" => rand(75..100)
        }
      end
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.day.ago }
      responses { {} }
    end

    trait :expiring_soon do
      status { "pending" }
      expires_at { 3.days.from_now }
    end

    trait :with_risk_assessment do
      association :risk_assessment, factory: :supply_chain_risk_assessment
    end

    trait :high_score do
      overall_score { rand(85..100) }
      section_scores do
        {
          "section1" => rand(85..100),
          "section2" => rand(85..100)
        }
      end
    end

    trait :low_score do
      overall_score { rand(20..50) }
      section_scores do
        {
          "section1" => rand(20..50),
          "section2" => rand(20..50)
        }
      end
    end

    trait :partial_completion do
      status { "in_progress" }
      started_at { 3.days.ago }
      responses do
        {
          "q1" => { answer: "yes", answered_at: 2.days.ago.iso8601 }
        }
      end
    end

    trait :complete_responses do
      responses do
        {
          "q1" => { answer: "yes", answered_at: 5.days.ago.iso8601 },
          "q2" => { answer: "We have comprehensive security policies and procedures", answered_at: 4.days.ago.iso8601 },
          "q3" => { answer: "yes", answered_at: 3.days.ago.iso8601 }
        }
      end
    end

    trait :with_requested_by do
      association :requested_by, factory: :user
    end
  end
end
