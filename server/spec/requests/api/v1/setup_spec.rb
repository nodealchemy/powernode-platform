# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Setup", type: :request do
  describe "POST /api/v1/setup/admin (first-run bootstrap)" do
    let(:valid_params) do
      { name: "Ada Admin", email: "ada@powernode.internal", password: TestUsers::PASSWORD }
    end

    context "with zero users and a valid bootstrap token" do
      let!(:token) { Setup::BootstrapToken.generate! }

      it "creates the first super_admin and returns access tokens" do
        expect do
          post "/api/v1/setup/admin", params: valid_params.merge(token: token), as: :json
        end.to change(User, :count).by(1)

        expect(response).to have_http_status(201)
        data = json_response_data
        expect(data["user"]["email"]).to eq("ada@powernode.internal")
        expect(data["access_token"]).to be_present

        user = User.find(data["user"]["id"])
        expect(user.super_admin?).to be(true)
        expect(user.has_permission?("system.admin")).to be(true)
      end

      it "invalidates the bootstrap token after first use" do
        post "/api/v1/setup/admin", params: valid_params.merge(token: token), as: :json
        expect(Setup::BootstrapToken.present?).to be(false)
      end
    end

    context "with an invalid token" do
      before { Setup::BootstrapToken.generate! }

      it "is rejected and creates no user" do
        expect do
          post "/api/v1/setup/admin", params: valid_params.merge(token: "wrong-token"), as: :json
        end.not_to change(User, :count)

        expect(response).to have_http_status(401)
      end
    end

    context "with no token at all" do
      before { Setup::BootstrapToken.generate! }

      it "is rejected" do
        post "/api/v1/setup/admin", params: valid_params, as: :json
        expect(response).to have_http_status(401)
      end
    end

    context "once an admin already exists (one-shot)" do
      let!(:token) { Setup::BootstrapToken.generate! }
      let!(:existing) { create(:user) }

      it "returns 409 and creates no further user" do
        expect do
          post "/api/v1/setup/admin", params: valid_params.merge(token: token), as: :json
        end.not_to change(User, :count)

        expect(response).to have_http_status(409)
        expect(json_response["code"]).to eq("already_bootstrapped")
      end
    end
  end

  describe "GET /api/v1/setup/status (public first-run probe)" do
    it "reports bootstrap incomplete when no users exist" do
      get "/api/v1/setup/status", as: :json

      expect_success_response
      expect(json_response_data["bootstrap_complete"]).to be(false)
    end

    it "reports bootstrap complete once a user exists" do
      create(:user)
      get "/api/v1/setup/status", as: :json

      expect_success_response
      expect(json_response_data["bootstrap_complete"]).to be(true)
    end
  end

  describe "authenticated setup routes" do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, permissions: [ "system.admin" ]) }
    let(:regular) { create(:user, account: account, permissions: []) }

    describe "GET /api/v1/setup/status" do
      it "reports bootstrap_complete and pending for a system admin" do
        get "/api/v1/setup/status", headers: auth_headers_for(admin), as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key("bootstrap_complete")
        expect(data).to have_key("pending")
      end
    end

    describe "GET /api/v1/setup/steps" do
      it "returns ordered core steps (admin before domain)" do
        get "/api/v1/setup/steps", headers: auth_headers_for(admin), as: :json

        expect_success_response
        keys = json_response_data["steps"].map { |s| s["key"] }
        expect(keys).to include("admin", "domain")
        expect(keys.index("admin")).to be < keys.index("domain")
      end

      it "forbids a user without system.admin" do
        get "/api/v1/setup/steps", headers: auth_headers_for(regular), as: :json
        expect(response).to have_http_status(403)
      end

      it "requires authentication" do
        get "/api/v1/setup/steps", as: :json
        expect(response).to have_http_status(401)
      end
    end

    describe "POST /api/v1/setup/steps/:key" do
      it "persists the domain step and stamps completion" do
        post "/api/v1/setup/steps/domain",
             params: { domain: "fleet.example.com" },
             headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(SiteSetting.get("domain")).to eq("fleet.example.com")
        expect(account.reload.setup_step_completed?("domain")).to be(true)
      end

      it "rejects a blank domain" do
        post "/api/v1/setup/steps/domain",
             params: { domain: "" },
             headers: auth_headers_for(admin), as: :json

        expect(response).to have_http_status(422)
      end

      it "persists the general_settings step" do
        post "/api/v1/setup/steps/general_settings",
             params: { site_name: "My Fleet", support_email: "ops@example.com" },
             headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(SiteSetting.get("site_name")).to eq("My Fleet")
        expect(SiteSetting.get("support_email")).to eq("ops@example.com")
        expect(account.reload.setup_step_completed?("general_settings")).to be(true)
      end

      it "allows general_settings to be submitted blank (optional)" do
        post "/api/v1/setup/steps/general_settings",
             params: {}, headers: auth_headers_for(admin), as: :json

        expect_success_response
      end

      it "persists the email step — non-secret to AdminSetting, password to SecretStore" do
        post "/api/v1/setup/steps/email",
             params: {
               smtp_host: "smtp.example.com", smtp_port: "587", smtp_username: "mailer",
               smtp_password: "Sup3r$ecretX!", smtp_from_address: "noreply@example.com"
             },
             headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(AdminSetting.get("smtp_host")).to eq("smtp.example.com")
        expect(AdminSetting.get("smtp_username")).to eq("mailer")
        expect(Security::SecretStore.read(account: account, scope: "email", key: "smtp_password")).to eq("Sup3r$ecretX!")
        expect(account.reload.setup_step_completed?("email")).to be(true)
      end

      it "never stores the SMTP password in AdminSetting" do
        post "/api/v1/setup/steps/email",
             params: { smtp_host: "smtp.example.com", smtp_password: "Sup3r$ecretX!" },
             headers: auth_headers_for(admin), as: :json

        expect(AdminSetting.get("smtp_password")).to be_nil
        expect(AdminSetting.get("smtp_password_encrypted")).to be_nil
      end

      it "404s an unknown step" do
        post "/api/v1/setup/steps/nope",
             params: {}, headers: auth_headers_for(admin), as: :json
        expect(response).to have_http_status(404)
      end

      it "refuses to submit the admin step through this endpoint" do
        post "/api/v1/setup/steps/admin",
             params: {}, headers: auth_headers_for(admin), as: :json
        expect(response).to have_http_status(422)
      end

      it "stamps the component-based extension_selection step" do
        post "/api/v1/setup/steps/extension_selection",
             params: {}, headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(account.reload.setup_step_completed?("extension_selection")).to be(true)
      end
    end

    describe "GET /api/v1/setup/extensions" do
      it "lists extensions for a system admin" do
        get "/api/v1/setup/extensions", headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(json_response_data["extensions"]).to be_an(Array)
      end

      it "forbids a user without system.admin" do
        get "/api/v1/setup/extensions", headers: auth_headers_for(regular), as: :json
        expect(response).to have_http_status(403)
      end
    end

    describe "POST /api/v1/setup/extensions/:slug" do
      it "404s an extension that is not loaded in this build" do
        post "/api/v1/setup/extensions/does-not-exist",
             params: { enabled: false }, headers: auth_headers_for(admin), as: :json
        expect(response).to have_http_status(404)
      end
    end

    describe "POST /api/v1/setup/seed" do
      it "runs the seed wrapper and stamps the seed step" do
        post "/api/v1/setup/seed", headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(json_response_data).to have_key("seeded")
        expect(account.reload.setup_step_completed?("seed")).to be(true)
      end

      it "forbids a user without system.admin" do
        post "/api/v1/setup/seed", headers: auth_headers_for(regular), as: :json
        expect(response).to have_http_status(403)
      end
    end

    describe "POST /api/v1/setup/extensions/:slug/configured" do
      it "stamps the extension as configured" do
        # 'system' is a real public extension present in the worktree.
        post "/api/v1/setup/extensions/system/configured", headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(account.reload.extension_configured?("system")).to be(true)
      end

      it "404s an extension with no manifest" do
        post "/api/v1/setup/extensions/does-not-exist/configured", headers: auth_headers_for(admin), as: :json
        expect(response).to have_http_status(404)
      end

      it "forbids a user without system.admin" do
        post "/api/v1/setup/extensions/system/configured", headers: auth_headers_for(regular), as: :json
        expect(response).to have_http_status(403)
      end
    end

    describe "GET /api/v1/setup/status — Phase 4 fields" do
      it "includes extensions_pending" do
        get "/api/v1/setup/status", headers: auth_headers_for(admin), as: :json

        expect_success_response
        expect(json_response_data).to have_key("extensions_pending")
        expect(json_response_data["extensions_pending"]).to be_an(Array)
      end
    end
  end
end
