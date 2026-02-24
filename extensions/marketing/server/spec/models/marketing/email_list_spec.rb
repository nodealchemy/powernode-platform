# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::EmailList, type: :model do
  subject { build(:marketing_email_list) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:email_subscribers).dependent(:destroy) }
    it { is_expected.to have_many(:campaign_email_lists).dependent(:destroy) }
    it { is_expected.to have_many(:campaigns).through(:campaign_email_lists) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    # slug is auto-generated via before_validation callback
    it { is_expected.to validate_presence_of(:list_type) }
    it { is_expected.to validate_inclusion_of(:list_type).in_array(Marketing::EmailList::LIST_TYPES) }
    it { is_expected.to validate_numericality_of(:subscriber_count).is_greater_than_or_equal_to(0) }
  end

  describe "scopes" do
    let(:account) { create(:account) }

    it "filters by type" do
      standard = create(:marketing_email_list, account: account, list_type: "standard")
      dynamic = create(:marketing_email_list, :dynamic, account: account)

      expect(described_class.by_type("standard")).to include(standard)
      expect(described_class.by_type("standard")).not_to include(dynamic)
    end

    it "filters lists with subscribers" do
      with_subs = create(:marketing_email_list, :with_subscribers, account: account)
      without_subs = create(:marketing_email_list, account: account)

      expect(described_class.with_subscribers).to include(with_subs)
      expect(described_class.with_subscribers).not_to include(without_subs)
    end
  end

  describe "#update_subscriber_count!" do
    let(:email_list) { create(:marketing_email_list) }

    it "updates count based on subscribed subscribers" do
      create_list(:marketing_email_subscriber, 3, :subscribed, email_list: email_list)
      create(:marketing_email_subscriber, :unsubscribed, email_list: email_list)

      email_list.update_subscriber_count!
      expect(email_list.subscriber_count).to eq(3)
    end
  end

  describe "#active_subscribers" do
    let(:email_list) { create(:marketing_email_list) }

    it "returns only subscribed subscribers" do
      subscribed = create(:marketing_email_subscriber, :subscribed, email_list: email_list)
      create(:marketing_email_subscriber, :unsubscribed, email_list: email_list)

      expect(email_list.active_subscribers).to include(subscribed)
      expect(email_list.active_subscribers.count).to eq(1)
    end
  end

  describe "#list_summary" do
    let(:email_list) { create(:marketing_email_list) }

    it "returns summary with expected keys" do
      summary = email_list.list_summary
      expect(summary).to include(:id, :name, :slug, :list_type, :subscriber_count, :double_opt_in)
    end
  end

  describe "slug generation" do
    let(:account) { create(:account) }

    it "auto-generates slug from name" do
      list = create(:marketing_email_list, name: "VIP Customers", account: account)
      expect(list.slug).to eq("vip-customers")
    end
  end
end
