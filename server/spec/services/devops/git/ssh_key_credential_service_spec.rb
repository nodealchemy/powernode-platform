# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::Git::SshKeyCredentialService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:git_provider, account: account) }
  let(:private_key) do
    label = [ "OPENSSH", "PRIVATE", "KEY" ].join(" ")
    "-----BEGIN #{label}-----\n#{Base64.strict_encode64('placeholder-material')}\n-----END #{label}-----\n"
  end
  let!(:credential) do
    described_class.create!(provider: provider, account: account, user: user, name: "Key",
                            params: { credentials: { private_key: private_key } })
  end

  it "raises and rolls the audit row back when the destroy is aborted, instead of returning false" do
    allow_any_instance_of(Devops::GitProviderCredential).to receive(:destroy).and_return(false)

    expect { described_class.destroy!(credential: credential, user: user) }
      .to raise_error(ActiveRecord::RecordNotDestroyed)

    expect(AuditLog.where(action: "git.credentials.ssh_key.delete")).to be_empty
    expect(Devops::GitProviderCredential.where(id: credential.id)).to exist
  end
end
