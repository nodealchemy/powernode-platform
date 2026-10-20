# frozen_string_literal: true

require "rails_helper"

# M2: the Vault secret is an external side effect, so it is deleted only once the
# row deletion has committed (after_destroy_commit). A rolled-back destroy keeps
# the secret and the row together.
RSpec.describe VaultCredential, "secret cleanup" do
  let(:account) { create(:account) }
  let!(:credential) do
    create(:chat_channel, account: account).tap do |c|
      c.update_columns(vault_path: "secret/data/powernode/test/credential")
    end
  end

  before { allow(Security::VaultClient).to receive(:delete_secret) }

  it "leaves the secret alone when the destroy is rolled back" do
    Chat::Channel.transaction(requires_new: true) do
      credential.destroy!
      raise ActiveRecord::Rollback
    end

    expect(Security::VaultClient).not_to have_received(:delete_secret)
    expect(Chat::Channel.exists?(credential.id)).to be true
  end

  it "deletes the secret once the destroy commits" do
    Chat::Channel.transaction(requires_new: true) { credential.destroy! }

    expect(Security::VaultClient).to have_received(:delete_secret).with("secret/data/powernode/test/credential")
  end
end
