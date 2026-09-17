# frozen_string_literal: true

require 'rails_helper'

# IMP-dd0305de2799, D5. Auditable#webhook_payload_data must default to "ids
# only" for any model that has not explicitly reviewed and declared its own
# safe-to-ship attributes — audit-row parity (redact_audit_values alone) is
# the WRONG bar for a payload leaving the process to a customer-supplied URL.
RSpec.describe 'Auditable#webhook_payload_data' do
  it 'defaults to empty ("ids only") when the model declares no webhook_payload_attributes' do
    expect(User.webhook_payload_attribute_names).to eq([])

    user = build_stubbed(:user)
    expect(user.send(:webhook_payload_data)).to eq({})
  end

  it 'ships only the explicitly declared attributes when a model opts in' do
    # :status — plain string column, not `encrypts`-backed and not a
    # substring match of any entry User's own filter_attributes carries
    # (email/name/two_factor_secret/backup_codes/last_login_ip/reset_token_digest)
    # — chosen so this proves the allowlist mechanism itself, undisturbed by
    # User's own (correct, separate) redaction of its PII columns.
    klass = Class.new(User) do
      def self.name
        'FakeModelWithAllowlist'
      end
      webhook_payload_attributes :status
    end

    expect(klass.webhook_payload_attribute_names).to eq([ 'status' ])

    instance = klass.new(status: 'active')
    expect(instance.send(:webhook_payload_data)).to eq('status' => 'active')
  end

  it 'still redacts an allowlisted attribute that is separately encrypted/filtered (redact_audit_values runs as a SECOND pass, not instead of the allowlist)' do
    klass = Class.new(User) do
      def self.name
        'FakeModelWithAllowlistOfAnEncryptedColumn'
      end
      webhook_payload_attributes :email # User `encrypts :email` — still redacted even though allowlisted
    end

    instance = klass.new(email: 'person@example.com')
    expect(instance.send(:webhook_payload_data)).to eq('email' => '[FILTERED]')
  end

  it 'declaring an allowlist on a subclass does not widen the parent model' do
    Class.new(User) do
      def self.name
        'AnotherFakeModelWithAllowlist'
      end
      webhook_payload_attributes :email
    end

    expect(User.webhook_payload_attribute_names).to eq([])
  end

  it 'neither User nor Account has opted into an allowlist yet (both currently ship ids-only payloads)' do
    expect(User.webhook_payload_attribute_names).to eq([])
    expect(Account.webhook_payload_attribute_names).to eq([])
  end

  it "does not leak Account's un-redacted, un-allowlisted attributes (tax_id, billing_email, settings, ...) by default" do
    account = create(:account)

    expect(account.send(:webhook_payload_data)).to eq({})
  end
end
