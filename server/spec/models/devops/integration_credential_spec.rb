# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::IntegrationCredential, type: :model do
  # IMP-01a04d08-ea13: `has_many :instances, dependent: :nullify` let any
  # destroy that bypassed RegistryService#delete_credential's in-use guard
  # orphan an instance whose template requires a credential. The rule that guard
  # states is now the model's own (restrict_with_error), so no path can do that.
  describe "an in-use credential (IMP-01a04d08-ea13)" do
    let(:account)    { create(:account) }
    let(:template)   { create(:devops_integration_template, credential_requirements: { "type" => "api_key" }) }
    let(:credential) { create(:devops_integration_credential, account: account) }
    let!(:instance)  { create(:devops_integration_instance, account: account, template: template, credential: credential) }

    it "refuses to be destroyed while an instance uses it, and the instance keeps it" do
      expect(credential.destroy).to be(false)
      expect(credential.errors.full_messages.join).to match(/instances/i)
      expect(described_class.exists?(credential.id)).to be(true)
      expect(instance.reload.integration_credential_id).to eq(credential.id)
    end

    it "is destroyed normally once no instance uses it" do
      instance.destroy!

      expect(credential.destroy).to be_truthy
      expect(described_class.exists?(credential.id)).to be(false)
    end

    # restrict_with_error does not block deleting an ACCOUNT because the account
    # destroys its instances before its credentials, and dependent: callbacks
    # run in declaration order. That order is what makes the restriction safe,
    # so it is pinned here.
    it "is destroyed after the account's instances, so account deletion is not blocked" do
      names = Account.reflect_on_all_associations(:has_many).map(&:name)

      expect(names.index(:devops_integration_instances)).to be < names.index(:devops_integration_credentials)
    end
  end
end
