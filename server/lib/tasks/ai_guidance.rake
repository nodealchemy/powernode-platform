# frozen_string_literal: true

namespace :ai do
  desc "Seed development-guidance conventions into platform knowledge (idempotent)"
  task seed_guidance: :environment do
    repository = ENV["REPOSITORY"].presence || "powernode-platform"
    Account.find_each do |account|
      result = Ai::Guidance::GuidanceKnowledgeSeeder.new(account: account, repository: repository).call
      Rails.logger.info("[ai:seed_guidance] account=#{account.id} #{result.summary}")
      puts "[ai:seed_guidance] account=#{account.id} #{result.summary}"
    end
  end

  desc "Seed THIS deployment's local operator docs (gitignored docs/operations/local/*.md) into platform knowledge as deployment-<slug> (idempotent)"
  task seed_deployment_knowledge: :environment do
    repository = ENV["REPOSITORY"].presence || "powernode-platform"
    dir = Rails.root.parent.join(*Ai::Guidance::GuidanceKnowledgeSeeder::DEPLOYMENT_DIR)
    unless dir.exist?
      puts "[ai:seed_deployment_knowledge] #{dir} does not exist — nothing to seed (see docs/contributing/conventions/deployment-knowledge.md)"
      next
    end
    Account.find_each do |account|
      result = Ai::Guidance::GuidanceKnowledgeSeeder.for_deployment(account: account, repository: repository).call
      Rails.logger.info("[ai:seed_deployment_knowledge] account=#{account.id} #{result.summary}")
      puts "[ai:seed_deployment_knowledge] account=#{account.id} #{result.summary}"
    end
  end
end
