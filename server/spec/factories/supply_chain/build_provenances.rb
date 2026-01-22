# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_build_provenance, class: "SupplyChain::BuildProvenance" do
    association :attestation, factory: :supply_chain_attestation
    association :account

    builder_id { "https://github.com/actions/runner" }
    builder_version { "v#{rand(2..3)}.#{rand(100..400)}.#{rand(0..9)}" }
    source_repository { "https://github.com/#{Faker::Internet.slug}/#{Faker::App.name.downcase.gsub(/\s+/, '-')}" }
    source_commit { SecureRandom.hex(20) }
    source_branch { %w[main master develop].sample }
    reproducible { false }
    materials { [] }
    invocation { {} }
    build_config { {} }
    environment { {} }
    metadata { {} }

    # ============================================
    # Builder Traits
    # ============================================
    trait :github_actions do
      builder_id { "https://github.com/actions/runner" }
      builder_version { "v2.311.0" }
    end

    trait :gitlab_ci do
      builder_id { "https://gitlab.com/gitlab-runner" }
      builder_version { "v16.8.0" }
    end

    trait :jenkins do
      builder_id { "https://jenkins.io/pipeline" }
      builder_version { "v2.426.3" }
    end

    trait :circleci do
      builder_id { "https://circleci.com/executor" }
      builder_version { "v2.1" }
    end

    trait :tekton do
      builder_id { "https://tekton.dev/pipeline" }
      builder_version { "v0.54.0" }
    end

    # ============================================
    # Build Status Traits
    # ============================================
    trait :pending do
      build_started_at { nil }
      build_finished_at { nil }
      build_duration_ms { nil }
    end

    trait :in_progress do
      build_started_at { 5.minutes.ago }
      build_finished_at { nil }
      build_duration_ms { nil }
    end

    trait :completed do
      build_started_at { 10.minutes.ago }
      build_finished_at { Time.current }
      build_duration_ms { 600_000 } # 10 minutes in ms
    end

    trait :quick_build do
      build_started_at { 30.seconds.ago }
      build_finished_at { Time.current }
      build_duration_ms { 30_000 }
    end

    trait :long_build do
      build_started_at { 2.hours.ago }
      build_finished_at { Time.current }
      build_duration_ms { 7_200_000 } # 2 hours in ms
    end

    # ============================================
    # Reproducibility Traits
    # ============================================
    trait :reproducible do
      reproducible { true }
      reproducibility_hash { Digest::SHA256.hexdigest("#{source_commit}#{SecureRandom.hex(8)}") }
    end

    trait :not_reproducible do
      reproducible { false }
      reproducibility_hash { nil }
      reproducibility_verified_at { nil }
    end

    trait :verified_reproducible do
      reproducible { true }
      reproducibility_hash { Digest::SHA256.hexdigest("#{source_commit}#{SecureRandom.hex(8)}") }
      reproducibility_verified_at { Time.current }
    end

    # ============================================
    # Source Control Traits
    # ============================================
    trait :main_branch do
      source_branch { "main" }
    end

    trait :develop_branch do
      source_branch { "develop" }
    end

    trait :feature_branch do
      source_branch { "feature/#{Faker::Internet.slug}" }
    end

    trait :release_branch do
      source_branch { "release/#{Faker::App.semantic_version}" }
    end

    # ============================================
    # Materials Traits
    # ============================================
    trait :with_materials do
      materials do
        [
          {
            uri: source_repository,
            digest: { sha256: source_commit }
          },
          {
            uri: "pkg:npm/express@4.18.2",
            digest: { sha256: SecureRandom.hex(32) }
          },
          {
            uri: "pkg:npm/lodash@4.17.21",
            digest: { sha256: SecureRandom.hex(32) }
          }
        ]
      end
    end

    trait :with_docker_base_image do
      materials do
        [
          {
            uri: source_repository,
            digest: { sha256: source_commit }
          },
          {
            uri: "docker:node:20-alpine",
            digest: { sha256: SecureRandom.hex(32) }
          }
        ]
      end
    end

    trait :with_many_dependencies do
      materials do
        deps = [{ uri: source_repository, digest: { sha256: source_commit } }]
        10.times do
          deps << {
            uri: "pkg:npm/#{Faker::Internet.slug}@#{Faker::App.semantic_version}",
            digest: { sha256: SecureRandom.hex(32) }
          }
        end
        deps
      end
    end

    # ============================================
    # Invocation Traits
    # ============================================
    trait :with_invocation do
      invocation do
        {
          parameters: {
            ref: source_branch,
            inputs: { deploy: true, environment: "production" }
          },
          internal_parameters: {
            github_event_name: "push",
            github_actor: Faker::Internet.username
          },
          configSource: {
            uri: source_repository,
            digest: { sha256: source_commit },
            entryPoint: ".github/workflows/build.yml"
          }
        }
      end
    end

    # ============================================
    # Build Config Traits
    # ============================================
    trait :with_build_config do
      build_config do
        {
          dockerfile: "Dockerfile",
          build_args: { NODE_ENV: "production" },
          target: "production",
          platforms: ["linux/amd64", "linux/arm64"]
        }
      end
    end

    # ============================================
    # Environment Traits
    # ============================================
    trait :with_environment do
      environment do
        {
          os: "ubuntu-22.04",
          arch: "x86_64",
          runner: "github-hosted",
          node_version: "20.10.0",
          npm_version: "10.2.3"
        }
      end
    end

    # ============================================
    # SLSA Level Traits (based on provenance completeness)
    # ============================================
    trait :slsa_level_1 do
      github_actions
      completed
      with_materials
    end

    trait :slsa_level_2 do
      github_actions
      completed
      with_materials
      with_invocation
      with_environment
    end

    trait :slsa_level_3 do
      github_actions
      completed
      with_materials
      with_invocation
      with_environment
      with_build_config
      verified_reproducible
    end
  end
end
