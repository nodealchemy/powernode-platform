# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::WaitlistSignup, type: :model do
  subject { build(:marketing_waitlist_signup) }

  describe "table mapping" do
    it "maps to marketing_waitlist_signups table" do
      expect(described_class.table_name).to eq("marketing_waitlist_signups")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:email_subscriber).class_name("Marketing::EmailSubscriber").optional }
    it { is_expected.to belong_to(:converted_account).class_name("Account").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }

    it "rejects invalid email format" do
      signup = build(:marketing_waitlist_signup, email: "not-an-email")
      expect(signup).not_to be_valid
      expect(signup.errors[:email]).to be_present
    end

    it "enforces email uniqueness (case-insensitive)" do
      create(:marketing_waitlist_signup, email: "Dup@Example.com")
      duplicate = build(:marketing_waitlist_signup, email: "DUP@example.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end

    it "rejects status outside the allowed set" do
      signup = build(:marketing_waitlist_signup, status: "bogus")
      expect(signup).not_to be_valid
    end
  end

  describe "callbacks" do
    it "downcases email before validation" do
      signup = create(:marketing_waitlist_signup, email: "MIXED@Example.COM")
      expect(signup.email).to eq("mixed@example.com")
    end

    it "strips whitespace from email" do
      signup = create(:marketing_waitlist_signup, email: "  spaced@example.com  ")
      expect(signup.email).to eq("spaced@example.com")
    end

    it "auto-generates a confirmation_token on create" do
      signup = create(:marketing_waitlist_signup)
      expect(signup.confirmation_token).to be_present
      expect(signup.confirmation_token.length).to be >= 16
    end
  end

  describe "scopes" do
    let!(:pending_signup)      { create(:marketing_waitlist_signup) }
    let!(:confirmed_signup)    { create(:marketing_waitlist_signup, :confirmed) }
    let!(:unsubscribed_signup) { create(:marketing_waitlist_signup, :unsubscribed) }
    let!(:converted_signup) do
      account = create(:account)
      create(:marketing_waitlist_signup, :confirmed).tap { |s| s.mark_converted!(account) }
    end

    describe ".pending" do
      it "returns only pending-status signups" do
        expect(described_class.pending).to contain_exactly(pending_signup)
      end
    end

    describe ".confirmed" do
      it "returns confirmed-status signups (including converted ones, which keep status=confirmed)" do
        expect(described_class.confirmed).to contain_exactly(confirmed_signup, converted_signup)
      end
    end

    describe ".unsubscribed" do
      it "returns only unsubscribed-status signups" do
        expect(described_class.unsubscribed).to contain_exactly(unsubscribed_signup)
      end
    end

    describe ".converted" do
      it "returns signups with a converted_account, regardless of status" do
        expect(described_class.converted).to contain_exactly(converted_signup)
      end
    end
  end

  describe "lifecycle methods" do
    describe "#confirm!" do
      it "transitions pending → confirmed, stamps confirmed_at, and clears the token" do
        signup = create(:marketing_waitlist_signup)
        original_token = signup.confirmation_token
        expect(original_token).to be_present

        expect { signup.confirm! }.to change(signup, :status).from("pending").to("confirmed")
        expect(signup.confirmed_at).to be_within(2.seconds).of(Time.current)
        expect(signup.confirmation_token).to be_nil
      end

      context "EmailSubscriber sync" do
        let!(:account) { create(:account) }

        it "auto-creates the 'Cloud Waitlist' EmailList on first sync" do
          signup = create(:marketing_waitlist_signup)
          expect {
            signup.confirm!
          }.to change { Marketing::EmailList.where(name: "Cloud Waitlist").count }.by(1)

          list = Marketing::EmailList.find_by(name: "Cloud Waitlist")
          expect(list.account_id).to eq(account.id)
          expect(list.list_type).to eq("standard")
        end

        it "reuses an existing 'Cloud Waitlist' EmailList on subsequent syncs" do
          create(:marketing_email_list, account: account, name: "Cloud Waitlist")
          signup = create(:marketing_waitlist_signup)

          expect {
            signup.confirm!
          }.not_to change(Marketing::EmailList, :count)
        end

        it "creates an EmailSubscriber and links it via email_subscriber_id" do
          signup = create(:marketing_waitlist_signup)

          expect {
            signup.confirm!
          }.to change(Marketing::EmailSubscriber, :count).by(1)

          subscriber = Marketing::EmailSubscriber.find_by(email: signup.email)
          expect(subscriber).to be_present
          expect(subscriber.status).to eq("subscribed")
          expect(subscriber.source).to eq("waitlist")
          expect(signup.reload.email_subscriber_id).to eq(subscriber.id)
        end

        it "is idempotent — re-confirming doesn't create a second subscriber" do
          signup = create(:marketing_waitlist_signup)
          signup.confirm!

          expect {
            signup.confirm!
          }.not_to change(Marketing::EmailSubscriber, :count)
        end

        it "logs and continues when sync fails (status still transitions)" do
          allow(Marketing::EmailList).to receive(:find_or_create_by!).and_raise(StandardError.new("simulated failure"))
          allow(Rails.logger).to receive(:error)
          signup = create(:marketing_waitlist_signup)

          expect { signup.confirm! }.not_to raise_error
          expect(signup.reload.status).to eq("confirmed")
          expect(signup.email_subscriber_id).to be_nil
          expect(Rails.logger).to have_received(:error).with(/sync_to_email_subscriber!/)
        end
      end
    end

    describe "#unsubscribe!" do
      it "transitions to unsubscribed and stamps unsubscribed_at" do
        signup = create(:marketing_waitlist_signup, :confirmed)
        expect { signup.unsubscribe! }.to change(signup, :status).from("confirmed").to("unsubscribed")
        expect(signup.unsubscribed_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe "#mark_converted!" do
      it "associates with an Account, stamps converted_at, and keeps status unchanged" do
        signup = create(:marketing_waitlist_signup, :confirmed)
        account = create(:account)

        expect { signup.mark_converted!(account) }.to change(signup, :converted_account_id).from(nil).to(account.id)
        expect(signup.converted_at).to be_within(2.seconds).of(Time.current)
        expect(signup.status).to eq("confirmed") # status untouched
      end
    end
  end
end
