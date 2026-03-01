# frozen_string_literal: true

FactoryBot.define do
  factory :ai_mission, class: "Ai::Mission" do
    account
    association :created_by, factory: :user
    sequence(:name) { |n| "Mission #{n}" }
    mission_type { "development" }
    status { "draft" }
    objective { "Implement a new feature" }

    # Assign a template matching the mission type (required for phase resolution)
    after(:build) do |mission|
      if mission.mission_template.nil? && mission.custom_phases.blank?
        trait = case mission.mission_type
                when "research" then :research
                when "operations" then :operations
                else nil
                end
        mission.mission_template = if trait
          create(:ai_mission_template, trait)
        else
          create(:ai_mission_template)
        end
      end

      # Development missions need a repository
      if mission.mission_type == "development" && mission.repository.nil?
        mission.repository = create(:git_repository, account: mission.account)
      end
    end

    trait :development do
      mission_type { "development" }
    end

    trait :research do
      mission_type { "research" }
      repository { nil }
    end

    trait :operations do
      mission_type { "operations" }
      repository { nil }
    end

    trait :active do
      status { "active" }
      started_at { Time.current }
      current_phase { "analyzing" }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      current_phase { "completed" }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.hour.ago }
      error_message { "Something went wrong" }
    end

    trait :with_deployment do
      deployed_port { 6000 }
      deployed_url { "http://localhost:6000" }
      deployed_container_id { "abc123" }
      current_phase { "previewing" }
      status { "active" }
      started_at { Time.current }
    end
  end

  factory :ai_mission_approval, class: "Ai::MissionApproval" do
    association :mission, factory: :ai_mission
    account { mission.account }
    association :user
    gate { "feature_selection" }
    decision { "approved" }

    trait :rejected do
      decision { "rejected" }
      comment { "Needs revision" }
    end

    trait :feature_selection do
      gate { "feature_selection" }
    end

    trait :prd_review do
      gate { "prd_review" }
    end

    trait :code_review do
      gate { "code_review" }
    end

    trait :merge_approval do
      gate { "merge_approval" }
    end
  end
end
