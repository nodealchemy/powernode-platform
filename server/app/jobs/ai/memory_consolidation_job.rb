# frozen_string_literal: true

module Ai
  class MemoryConsolidationJob < ApplicationJob
    queue_as :default

    def perform(account_id = nil)
      if account_id
        account = Account.find(account_id)
        consolidate_for_account(account)
      else
        Account.find_each { |account| consolidate_for_account(account) }
      end
    end

    private

    def consolidate_for_account(account)
      service = Ai::Learning::MemoryConsolidationService.new(account: account)
      service.consolidate
    rescue => e
      Rails.logger.error "[MemoryConsolidation] Failed for account #{account.id}: #{e.message}"
    end
  end
end
