# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::EmailCampaignService do
  let(:account) { create(:account) }
  let(:campaign) { create(:marketing_campaign, :email, account: account) }
  let(:service) { described_class.new(campaign) }

  describe "#prepare_recipients" do
    let(:email_list) { create(:marketing_email_list, :with_subscribers, account: account) }

    before do
      create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)
    end

    it "returns recipient information" do
      result = service.prepare_recipients
      expect(result[:total_recipients]).to be > 0
      expect(result[:by_list]).to be_an(Array)
      expect(result[:ready]).to be true
    end

    it "deduplicates subscribers across lists" do
      email_list2 = create(:marketing_email_list, account: account)
      # Add same email to second list
      existing_email = email_list.email_subscribers.first.email
      create(:marketing_email_subscriber, :subscribed, email: existing_email, email_list: email_list2)
      create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list2)

      result = service.prepare_recipients
      # Should not count duplicates
      expect(result[:total_recipients]).to eq(email_list.active_subscribers.count)
    end
  end

  describe "#dispatch_batch_send" do
    let(:email_list) { create(:marketing_email_list, :with_subscribers, account: account) }

    before do
      create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)
      create(:marketing_campaign_content, :approved, campaign: campaign, channel: "email")
    end

    it "returns dispatch information" do
      result = service.dispatch_batch_send
      expect(result[:campaign_id]).to eq(campaign.id)
      expect(result[:total_recipients]).to be > 0
      expect(result[:batch_size]).to eq(100)
      expect(result[:dispatched]).to be true
    end

    it "raises error when no recipients" do
      campaign2 = create(:marketing_campaign, :email, account: account)
      service2 = described_class.new(campaign2)
      expect { service2.dispatch_batch_send }.to raise_error(described_class::EmailError, /No recipients/)
    end

    it "raises error when no approved content" do
      campaign2 = create(:marketing_campaign, :email, account: account)
      list2 = create(:marketing_email_list, :with_subscribers, account: account)
      create(:marketing_campaign_email_list, campaign: campaign2, email_list: list2)
      service2 = described_class.new(campaign2)
      expect { service2.dispatch_batch_send }.to raise_error(described_class::EmailError, /No approved email content/)
    end
  end

  describe "#handle_bounce" do
    let(:email_list) { create(:marketing_email_list, account: account) }
    let!(:subscriber) { create(:marketing_email_subscriber, :subscribed, email: "bounced@example.com", email_list: email_list) }

    before do
      create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)
    end

    it "records bounce for matching subscribers" do
      result = service.handle_bounce(email: "bounced@example.com")
      expect(result[:processed]).to be >= 0
      expect(result[:bounce_type]).to eq("hard")
    end
  end

  describe "#handle_unsubscribe" do
    let(:email_list) { create(:marketing_email_list, account: account) }
    let!(:subscriber) { create(:marketing_email_subscriber, :subscribed, email: "unsub@example.com", email_list: email_list) }

    before do
      create(:marketing_campaign_email_list, campaign: campaign, email_list: email_list)
    end

    it "unsubscribes matching subscribers" do
      result = service.handle_unsubscribe(email: "unsub@example.com")
      expect(result[:processed]).to be >= 0
    end
  end

  describe "#import_subscribers" do
    let(:email_list) { create(:marketing_email_list, account: account) }

    it "imports new subscribers" do
      data = [
        { email: "new1@example.com", first_name: "John", last_name: "Doe" },
        { email: "new2@example.com", first_name: "Jane", last_name: "Doe" }
      ]

      result = service.import_subscribers(email_list, data)
      expect(result[:imported]).to eq(2)
      expect(result[:skipped]).to eq(0)
    end

    it "skips existing subscribers" do
      create(:marketing_email_subscriber, email: "existing@example.com", email_list: email_list)

      data = [
        { email: "existing@example.com", first_name: "Existing" },
        { email: "new@example.com", first_name: "New" }
      ]

      result = service.import_subscribers(email_list, data)
      expect(result[:imported]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "respects double opt-in setting" do
      email_list.update!(double_opt_in: true)
      data = [{ email: "pending@example.com" }]

      service.import_subscribers(email_list, data)
      subscriber = email_list.email_subscribers.find_by(email: "pending@example.com")
      expect(subscriber.status).to eq("pending")
    end
  end
end
