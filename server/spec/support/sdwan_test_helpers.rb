# frozen_string_literal: true

# Helpers for SDWAN spec setup. The model graph requires
# Account → NodeArchitecture → NodePlatform → NodeTemplate → Node →
# NodeInstance before any Sdwan::Peer can be created. We delegate to
# factory_bot for the upstream chain (5 belongs_to required) so the
# helper file isn't a duplicate of the factories. These wrappers exist
# only to guarantee a single account-scoped template is reused across a
# spec's let! block — saving a few hundred milliseconds vs. building
# the chain N times for N peers.
module SdwanTestHelpers
  include FactoryBot::Syntax::Methods

  # Returns a Node belonging to `account`. Caches the per-account
  # template so multiple peer setups in one spec share parents.
  def sdwan_test_node(account:, name: nil)
    template = sdwan_test_template(account: account)
    ::System::Node.create!(
      account: account,
      node_template: template,
      name: name || "sdwan-test-node-#{SecureRandom.hex(3)}"
    )
  end

  def sdwan_test_template(account:)
    existing = ::System::NodeTemplate.where(account_id: account.id, name: "sdwan-test-template").first
    return existing if existing

    arch = ::System::NodeArchitecture.where(account_id: account.id).first ||
           create(:system_node_architecture, account: account)
    platform = ::System::NodePlatform.where(account_id: account.id).first ||
               create(:system_node_platform, account: account, node_architecture: arch)
    ::System::NodeTemplate.create!(
      account: account,
      node_platform: platform,
      name: "sdwan-test-template",
      enabled: true,
      admin_user: "admin",
      config: {}
    )
  end

  # Builds a NodeInstance under the given Node — provider_region and
  # provider_instance_type are optional on the model so we skip them
  # for SDWAN specs.
  def sdwan_test_node_instance(node:, name: nil)
    ::System::NodeInstance.create!(
      node: node,
      name: name || "sdwan-test-inst-#{SecureRandom.hex(3)}",
      variety: "physical",
      status: "pending"
    )
  end
end

RSpec.configure do |config|
  config.include SdwanTestHelpers
end
