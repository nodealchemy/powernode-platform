# frozen_string_literal: true

FactoryBot.define do
  # Alias - specs reference :supply_chain_component but the actual
  # model/factory is :supply_chain_sbom_component
  factory :supply_chain_component, parent: :supply_chain_sbom_component
end
