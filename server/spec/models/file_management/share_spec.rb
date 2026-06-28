# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileManagement::Share, type: :model do
  describe "URL generation" do
    let(:share) { create(:file_share, share_token: "abc123token") }

    # Regression: #share_url/#download_url referenced Rails.application.config.base_url,
    # which is never assigned in any environment → calling them raised NoMethodError
    # (dead in every env). They now resolve the public base URL via PublicUrlResolver
    # (DB-driven; host-relative in core mode when no domain is configured).
    context "core mode (no public_base_url configured)" do
      it "#share_url returns a host-relative share path without raising" do
        expect { share.share_url }.not_to raise_error
        expect(share.share_url).to eq("/shared/abc123token")
      end

      it "#download_url returns a host-relative download path without raising" do
        expect(share.download_url).to eq("/shared/abc123token/download")
      end

      it "#share_summary builds without raising (it embeds share_url)" do
        expect { share.share_summary }.not_to raise_error
        expect(share.share_summary[:share_url]).to eq("/shared/abc123token")
      end
    end

    context "with a global public_base_url (DB-driven)" do
      before { SiteSetting.set("public_base_url", "https://files.example.com", setting_type: "string") }

      it "#share_url returns an absolute URL" do
        expect(share.share_url).to eq("https://files.example.com/shared/abc123token")
      end

      it "#download_url returns an absolute URL" do
        expect(share.download_url).to eq("https://files.example.com/shared/abc123token/download")
      end
    end
  end
end
