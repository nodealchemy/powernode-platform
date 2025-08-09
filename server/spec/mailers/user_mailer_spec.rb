require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "password_reset" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, email_verified_at: Time.current) }
    let(:mail) { UserMailer.password_reset(user) }

    before do
      user.generate_reset_token!
    end

    it "renders the headers" do
      expect(mail.subject).to eq("Password Reset Instructions - Powernode")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "noreply@powernode.dev" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hello #{user.first_name}")
      expect(mail.body.encoded).to match("reset-password\\?token")
    end
  end
end
