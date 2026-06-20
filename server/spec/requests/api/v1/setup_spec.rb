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
    end
  end
end
