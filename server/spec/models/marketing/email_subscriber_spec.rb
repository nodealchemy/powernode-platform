# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::EmailSubscriber, type: :model do
  subject { build(:marketing_email_subscriber) }

  describe "associations" do
    it { is_expected.to belong_to(:email_list).class_name("Marketing::EmailList") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Marketing::EmailSubscriber::STATUSES) }

    it "validates email format" do
      subscriber = build(:marketing_email_subscriber, email: "invalid-email")
      expect(subscriber).not_to be_valid
    end

    it "validates email uniqueness within a list" do
      list = create(:marketing_email_list)
      create(:marketing_email_subscriber, email: "test@example.com", email_list: list)
      duplicate = build(:marketing_email_subscriber, email: "test@example.com", email_list: list)
      expect(duplicate).not_to be_valid
    end
  end

  describe "scopes" do
    let(:list) { create(:marketing_email_list) }

    it "filters subscribed" do
      subscribed = create(:marketing_email_subscriber, :subscribed, email_list: list)
      unsubscribed = create(:marketing_email_subscriber, :unsubscribed, email_list: list)

      expect(described_class.subscribed).to include(subscribed)
      expect(described_class.subscribed).not_to include(unsubscribed)
    end

    it "filters active (pending + subscribed)" do
      pending = create(:marketing_email_subscriber, :pending, email_list: list)
      subscribed = create(:marketing_email_subscriber, :subscribed, email_list: list)
      bounced = create(:marketing_email_subscriber, :bounced, email_list: list)

      active = described_class.active
      expect(active).to include(pending, subscribed)
      expect(active).not_to include(bounced)
    end
  end

  describe "#subscribe!" do
    let(:subscriber) { create(:marketing_email_subscriber) }

    it "sets status to subscribed with timestamps" do
      subscriber.subscribe!
      expect(subscriber.status).to eq("subscribed")
      expect(subscriber.subscribed_at).to be_present
      expect(subscriber.confirmed_at).to be_present
    end
  end

  describe "#unsubscribe!" do
    let(:subscriber) { create(:marketing_email_subscriber, :subscribed) }

    it "sets status to unsubscribed" do
      subscriber.unsubscribe!
      expect(subscriber.status).to eq("unsubscribed")
      expect(subscriber.unsubscribed_at).to be_present
    end
  end

  describe "#record_bounce!" do
    let(:subscriber) { create(:marketing_email_subscriber, :subscribed) }

    it "increments bounce count" do
      expect { subscriber.record_bounce! }.to change { subscriber.reload.bounce_count }.by(1)
    end

    it "marks as bounced after 3 bounces" do
      subscriber.update!(bounce_count: 2)
      subscriber.record_bounce!
      expect(subscriber.status).to eq("bounced")
    end
  end

  describe "#full_name" do
    it "returns combined first and last name" do
      subscriber = build(:marketing_email_subscriber, first_name: "John", last_name: "Doe")
      expect(subscriber.full_name).to eq("John Doe")
    end

    it "returns nil when both names are blank" do
      subscriber = build(:marketing_email_subscriber, first_name: nil, last_name: nil)
      expect(subscriber.full_name).to be_nil
    end
  end

  describe "email normalization" do
    it "downcases and strips email" do
      subscriber = create(:marketing_email_subscriber, email: "  Test@EXAMPLE.com  ")
      expect(subscriber.email).to eq("test@example.com")
    end
  end

  describe "confirmation token generation" do
    it "generates token on create" do
      subscriber = create(:marketing_email_subscriber)
      expect(subscriber.confirmation_token).to be_present
    end
  end
end
