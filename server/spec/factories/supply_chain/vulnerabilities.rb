# frozen_string_literal: true

FactoryBot.define do
  # Alias - specs reference :supply_chain_vulnerability but the actual
  # model/factory is :supply_chain_vulnerability_scan
  factory :supply_chain_vulnerability, parent: :supply_chain_vulnerability_scan
end
