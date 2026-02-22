# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Marketplace::InstallationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) do
    create(:ai_workflow_template, :published,
           account: account,
           created_by_user: user,
           version: "1.0.0",
           rating: 4.0,
           rating_count: 10)
  end
  let(:service) { described_class.new(account: account, user: user) }

  describe "#initialize" do
    it "sets account and user" do
      expect(service.account).to eq(account)
      expect(service.user).to eq(user)
    end
  end

  describe "#install" do
    context "with a valid installable template" do
      it "returns success" do
        result = service.install(template_id: template.id)
        expect(result[:success]).to be true
      end

      it "creates a marketplace subscription" do
        expect {
          service.install(template_id: template.id)
        }.to change { Marketplace::Subscription.count }.by(1)
      end

      it "creates a workflow from the template" do
        expect {
          service.install(template_id: template.id)
        }.to change { account.ai_workflows.count }.by(1)
      end

      it "returns the subscription and workflow" do
        result = service.install(template_id: template.id)
        expect(result[:subscription]).to be_a(Marketplace::Subscription)
        expect(result[:workflow]).to be_a(Ai::Workflow)
      end

      it "stores workflow_id in subscription metadata" do
        result = service.install(template_id: template.id)
        expect(result[:subscription].metadata["workflow_id"]).to eq(result[:workflow].id)
      end

      it "stores template_version in subscription metadata" do
        result = service.install(template_id: template.id)
        expect(result[:subscription].metadata["template_version"]).to eq("1.0.0")
      end

      it "stores installed_by_email in subscription metadata" do
        result = service.install(template_id: template.id)
        expect(result[:subscription].metadata["installed_by_email"]).to eq(user.email)
      end

      it "increments template usage_count" do
        expect {
          service.install(template_id: template.id)
        }.to change { template.reload.usage_count }.by(1)
      end

      it "stores custom_configuration in subscription" do
        config = { "max_retries" => 3 }
        result = service.install(template_id: template.id, custom_configuration: config)
        expect(result[:subscription].configuration).to eq(config)
      end

      it "returns a success message" do
        result = service.install(template_id: template.id)
        expect(result[:message]).to eq("Template installed successfully")
      end
    end

    context "when template is not installable" do
      let(:private_template) do
        other_account = create(:account)
        create(:ai_workflow_template, account: other_account, is_public: false)
      end

      it "returns error" do
        result = service.install(template_id: private_template.id)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not available for installation")
      end
    end

    context "when template is already installed" do
      before do
        service.install(template_id: template.id)
      end

      it "returns error about duplicate" do
        result = service.install(template_id: template.id)
        expect(result[:success]).to be false
        expect(result[:error]).to include("already installed")
      end
    end

    context "when template is not found" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          service.install(template_id: SecureRandom.uuid)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when workflow creation fails" do
      before do
        allow(account.ai_workflows).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(Ai::Workflow.new)
        )
      end

      it "returns error with validation messages" do
        result = service.install(template_id: template.id)
        expect(result[:success]).to be false
      end
    end

    context "with workflow nodes and edges from template" do
      let(:agent) { create(:ai_agent, account: account) }
      let(:complex_template) do
        create(:ai_workflow_template, :published,
               account: account,
               created_by_user: user,
               workflow_definition: {
                 "nodes" => [
                   { "node_id" => "start", "node_type" => "start", "name" => "Start",
                     "position" => { "x" => 0, "y" => 0 }, "configuration" => { "enabled" => true } },
                   { "node_id" => "agent", "node_type" => "ai_agent", "name" => "Agent",
                     "position" => { "x" => 200, "y" => 0 }, "configuration" => { "model" => "gpt-4", "agent_id" => agent.id } },
                   { "node_id" => "end", "node_type" => "end", "name" => "End",
                     "position" => { "x" => 400, "y" => 0 }, "configuration" => { "enabled" => true } }
                 ],
                 "edges" => [
                   { "source_node_id" => "start", "target_node_id" => "agent", "edge_type" => "default" },
                   { "source_node_id" => "agent", "target_node_id" => "end", "edge_type" => "default" }
                 ]
               })
      end

      it "creates workflow nodes from template definition" do
        result = service.install(template_id: complex_template.id)
        workflow = result[:workflow]
        expect(workflow.nodes.count).to eq(3)
        expect(workflow.nodes.pluck(:node_id)).to contain_exactly("start", "agent", "end")
      end

      it "creates workflow edges from template definition" do
        result = service.install(template_id: complex_template.id)
        workflow = result[:workflow]
        expect(workflow.edges.count).to eq(2)
      end
    end
  end

  describe "#uninstall" do
    let!(:install_result) { service.install(template_id: template.id) }
    let(:subscription) { install_result[:subscription] }

    context "with valid subscription" do
      it "returns success" do
        result = service.uninstall(subscription_id: subscription.id)
        expect(result[:success]).to be true
      end

      it "destroys the subscription" do
        expect {
          service.uninstall(subscription_id: subscription.id)
        }.to change { Marketplace::Subscription.count }.by(-1)
      end

      it "decrements template usage_count" do
        expect {
          service.uninstall(subscription_id: subscription.id)
        }.to change { template.reload.usage_count }.by(-1)
      end

      it "does not delete workflow by default" do
        workflow_id = subscription.metadata["workflow_id"]
        service.uninstall(subscription_id: subscription.id)
        expect(Ai::Workflow.find_by(id: workflow_id)).to be_present
      end
    end

    context "with delete_workflow: true" do
      it "deletes the associated workflow" do
        workflow_id = subscription.metadata["workflow_id"]
        service.uninstall(subscription_id: subscription.id, delete_workflow: true)
        expect(Ai::Workflow.find_by(id: workflow_id)).to be_nil
      end

      it "returns deleted_workflow: true" do
        result = service.uninstall(subscription_id: subscription.id, delete_workflow: true)
        expect(result[:deleted_workflow]).to be true
      end
    end

    context "when subscription is not found" do
      it "returns error" do
        result = service.uninstall(subscription_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("Installation not found")
      end
    end
  end

  describe "#list_installations" do
    before do
      3.times do
        t = create(:ai_workflow_template, :published, account: account, created_by_user: user)
        service.install(template_id: t.id)
      end
    end

    it "returns installations for the account" do
      result = service.list_installations
      expect(result[:installations].size).to eq(3)
    end

    it "includes pagination data" do
      result = service.list_installations
      expect(result[:pagination][:total_count]).to eq(3)
      expect(result[:pagination][:current_page]).to eq(1)
    end

    it "respects page parameter" do
      result = service.list_installations(per_page: 2, page: 2)
      expect(result[:installations].size).to eq(1)
      expect(result[:pagination][:current_page]).to eq(2)
    end

    it "caps per_page at 100" do
      result = service.list_installations(per_page: 200)
      expect(result[:pagination][:per_page]).to eq(100)
    end

    it "serializes installation data" do
      result = service.list_installations
      installation = result[:installations].first
      expect(installation).to have_key(:id)
      expect(installation).to have_key(:template_id)
      expect(installation).to have_key(:template_name)
      expect(installation).to have_key(:installed_version)
      expect(installation).to have_key(:workflow_id)
    end
  end

  describe "#get_installation" do
    let!(:install_result) { service.install(template_id: template.id) }
    let(:subscription) { install_result[:subscription] }

    it "returns installation details" do
      result = service.get_installation(subscription.id)
      expect(result[:success]).to be true
      expect(result[:installation]).to be_present
    end

    it "includes template details" do
      result = service.get_installation(subscription.id)
      expect(result[:installation][:template]).to be_present
      expect(result[:installation][:template][:name]).to eq(template.name)
    end

    it "includes workflow details" do
      result = service.get_installation(subscription.id)
      expect(result[:installation][:workflow]).to be_present
    end

    it "returns error for non-existent subscription" do
      result = service.get_installation(SecureRandom.uuid)
      expect(result[:success]).to be false
      expect(result[:error]).to include("Installation not found")
    end
  end

  describe "#check_for_updates" do
    context "when updates are available" do
      before do
        service.install(template_id: template.id)
        template.update!(version: "2.0.0")
      end

      it "returns available updates" do
        result = service.check_for_updates
        expect(result[:updates_available].size).to eq(1)
        expect(result[:total_count]).to eq(1)
      end

      it "includes version information" do
        result = service.check_for_updates
        update = result[:updates_available].first
        expect(update[:current_version]).to eq("1.0.0")
        expect(update[:latest_version]).to eq("2.0.0")
      end
    end

    context "when no updates are available" do
      before do
        service.install(template_id: template.id)
      end

      it "returns empty updates" do
        result = service.check_for_updates
        expect(result[:updates_available]).to be_empty
        expect(result[:total_count]).to eq(0)
      end
    end
  end

  describe "#apply_update" do
    let!(:install_result) { service.install(template_id: template.id) }
    let(:subscription) { install_result[:subscription] }

    context "when update is available" do
      before do
        template.update!(version: "2.0.0")
      end

      it "returns success" do
        result = service.apply_update(subscription_id: subscription.id)
        expect(result[:success]).to be true
      end

      it "updates subscription metadata with new version" do
        service.apply_update(subscription_id: subscription.id)
        subscription.reload
        expect(subscription.metadata["template_version"]).to eq("2.0.0")
      end

      it "records previous_version in metadata" do
        service.apply_update(subscription_id: subscription.id)
        subscription.reload
        expect(subscription.metadata["previous_version"]).to eq("1.0.0")
      end

      it "returns version info" do
        result = service.apply_update(subscription_id: subscription.id)
        expect(result[:previous_version]).to eq("1.0.0")
        expect(result[:new_version]).to eq("2.0.0")
      end
    end

    context "when already up to date" do
      it "returns error" do
        result = service.apply_update(subscription_id: subscription.id)
        expect(result[:success]).to be false
        expect(result[:error]).to include("already up to date")
      end
    end

    context "when subscription not found" do
      it "returns error" do
        result = service.apply_update(subscription_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("Installation not found")
      end
    end
  end

  describe "#apply_all_updates" do
    before do
      3.times do
        t = create(:ai_workflow_template, :published, account: account, created_by_user: user, version: "1.0.0")
        service.install(template_id: t.id)
        t.update!(version: "2.0.0")
      end
    end

    it "attempts to update all installations" do
      result = service.apply_all_updates
      expect(result[:total_attempted]).to eq(3)
    end

    it "reports successful updates" do
      result = service.apply_all_updates
      expect(result[:successful]).to eq(3)
    end

    it "includes details for each update" do
      result = service.apply_all_updates
      expect(result[:details].size).to eq(3)
      result[:details].each do |detail|
        expect(detail[:status]).to eq("updated")
      end
    end
  end

  describe "#rate_template" do
    before do
      service.install(template_id: template.id)
    end

    context "with valid rating" do
      it "returns success" do
        result = service.rate_template(template_id: template.id, rating: 5)
        expect(result[:success]).to be true
      end

      it "updates template average rating" do
        service.rate_template(template_id: template.id, rating: 5)
        template.reload
        # (4.0 * 10 + 5) / 11 = 4.09
        expect(template.rating).to be_within(0.1).of(4.09)
      end

      it "increments rating_count" do
        expect {
          service.rate_template(template_id: template.id, rating: 5)
        }.to change { template.reload.rating_count }.by(1)
      end

      it "stores rating in subscription metadata" do
        service.rate_template(template_id: template.id, rating: 4)
        subscription = account.workflow_template_subscriptions.find_by(subscribable: template)
        expect(subscription.metadata["rating"]).to eq(4)
      end

      it "returns new average and total ratings" do
        result = service.rate_template(template_id: template.id, rating: 5)
        expect(result[:new_average]).to be_present
        expect(result[:total_ratings]).to eq(11)
      end
    end

    context "with invalid rating" do
      it "rejects rating below 1" do
        result = service.rate_template(template_id: template.id, rating: 0)
        expect(result[:success]).to be false
        expect(result[:error]).to include("between 1 and 5")
      end

      it "rejects rating above 5" do
        result = service.rate_template(template_id: template.id, rating: 6)
        expect(result[:success]).to be false
        expect(result[:error]).to include("between 1 and 5")
      end
    end

    context "when template is not installed" do
      let(:other_template) { create(:ai_workflow_template, :published, account: account, created_by_user: user) }

      it "returns error" do
        result = service.rate_template(template_id: other_template.id, rating: 5)
        expect(result[:success]).to be false
        expect(result[:error]).to include("must install")
      end
    end

    context "when already rated" do
      before do
        service.rate_template(template_id: template.id, rating: 3)
      end

      it "prevents duplicate rating by default" do
        result = service.rate_template(template_id: template.id, rating: 5)
        expect(result[:success]).to be false
        expect(result[:error]).to include("already rated")
      end

      it "allows update with allow_update flag" do
        result = service.rate_template(
          template_id: template.id,
          rating: 5,
          feedback: { allow_update: true }
        )
        expect(result[:success]).to be true
      end

      it "recalculates average when updating" do
        old_rating_count = template.reload.rating_count
        service.rate_template(
          template_id: template.id,
          rating: 5,
          feedback: { allow_update: true }
        )
        # Count should not change when updating
        expect(template.reload.rating_count).to eq(old_rating_count)
      end
    end

    context "when template is not found" do
      it "returns error" do
        result = service.rate_template(template_id: SecureRandom.uuid, rating: 5)
        expect(result[:success]).to be false
        expect(result[:error]).to include("Template not found")
      end
    end
  end
end
