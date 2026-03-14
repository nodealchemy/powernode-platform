# frozen_string_literal: true

FactoryBot.define do
  # Alias - specs reference :supply_chain_execution_log but the actual
  # model/factory is :supply_chain_scan_execution
  factory :supply_chain_execution_log, parent: :supply_chain_scan_execution
end
