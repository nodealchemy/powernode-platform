# frozen_string_literal: true

require 'rails_helper'

# Focused on #cancel's paused-instance handling (fc-32 review: paused was
# treated as terminal, so cancelling a paused sandbox silently no-opped).
# Not a full spec of ContainerOrchestrationService — that has no existing
# coverage and backfilling it is out of scope for this fix.
RSpec.describe Devops::ContainerOrchestrationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:devops_container_template, account: account) }

  before do
    # #initialize unconditionally builds a Gitea client; #cancel only reaches
    # it when the instance carries a gitea_workflow_run_id, which none of
    # these fixtures do. Stub construction rather than provisioning a real
    # GitProvider + credentials this spec has no other need for.
    allow_any_instance_of(described_class).to receive(:build_gitea_client).and_return(nil)
  end

  subject(:service) { described_class.new(account: account, user: user) }

  describe '#cancel' do
    it 'cancels a paused instance (paused is not terminal)' do
      instance = create(:devops_container_instance, :paused, account: account, template: template)

      result = service.cancel(instance.execution_id)

      expect(result).to be true
      expect(instance.reload.status).to eq("cancelled")
    end

    it 'refuses a genuinely terminal instance (completed)' do
      instance = create(:devops_container_instance, :completed, account: account, template: template)

      result = service.cancel(instance.execution_id)

      expect(result).to be false
      expect(instance.reload.status).to eq("completed")
    end
  end
end
