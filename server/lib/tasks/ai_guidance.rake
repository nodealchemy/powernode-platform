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
end
