# frozen_string_literal: true

namespace :ai do
  desc "Soft-retire compound learnings tagged/domained under DOMAIN (excludes them from injection/retrieval/ranking; never hard-deletes)"
  task :retire_learning_domain, [:domain] => :environment do |_t, args|
    domain = args[:domain].presence
    abort("Usage: rails ai:retire_learning_domain[<domain>]") unless domain

    Account.find_each do |account|
      service = Ai::Learning::CompoundLearningService.new(account: account)
      result = service.retire_domain!(domain)

      next if result[:retired_count].to_i.zero? && result[:success] != false

      Rails.logger.info("[ai:retire_learning_domain] account=#{account.id} domain=#{domain} #{result}")
      puts "[ai:retire_learning_domain] account=#{account.id} domain=#{domain} #{result}"
    end
  end
end
