# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing Email Lists API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("marketing.email_lists.read", "marketing.email_lists.manage", account: account) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/marketing/email_lists" do
    let!(:list1) { create(:marketing_email_list, account: account) }
    let!(:list2) { create(:marketing_email_list, :dynamic, account: account) }
    let!(:other_account_list) { create(:marketing_email_list) }

    it "returns email lists for the account" do
      get "/api/v1/marketing/email_lists", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(2)
    end

    it "filters by list type" do
      get "/api/v1/marketing/email_lists", params: { list_type: "dynamic" }, headers: headers

      expect(response).to have_http_status(:ok)
      items = json_response["data"]["items"]
      expect(items.length).to eq(1)
      expect(items.first["list_type"]).to eq("dynamic")
    end

    it "requires authentication" do
      get "/api/v1/marketing/email_lists"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires permission" do
      no_perm_user = user_with_permissions(account: account)
      get "/api/v1/marketing/email_lists", headers: auth_headers_for(no_perm_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/marketing/email_lists/:id" do
    let!(:email_list) { create(:marketing_email_list, account: account) }

    it "returns list details" do
      get "/api/v1/marketing/email_lists/#{email_list.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["email_list"]["id"]).to eq(email_list.id)
    end

    it "returns 404 for non-existent list" do
      get "/api/v1/marketing/email_lists/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/marketing/email_lists" do
    let(:valid_params) do
      {
        email_list: {
          name: "VIP Customers",
          list_type: "standard",
          double_opt_in: true
        }
      }
    end

    it "creates a new email list" do
      expect {
        post "/api/v1/marketing/email_lists", params: valid_params.to_json, headers: headers
      }.to change(Marketing::EmailList, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["email_list"]["name"]).to eq("VIP Customers")
    end

    it "validates required fields" do
      post "/api/v1/marketing/email_lists",
           params: { email_list: { name: "" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/marketing/email_lists/:id" do
    let!(:email_list) { create(:marketing_email_list, account: account) }

    it "updates the list" do
      patch "/api/v1/marketing/email_lists/#{email_list.id}",
            params: { email_list: { name: "Updated List" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["email_list"]["name"]).to eq("Updated List")
    end
  end

  describe "DELETE /api/v1/marketing/email_lists/:id" do
    let!(:email_list) { create(:marketing_email_list, account: account) }

    it "deletes the list" do
      expect {
        delete "/api/v1/marketing/email_lists/#{email_list.id}", headers: headers
      }.to change(Marketing::EmailList, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/marketing/email_lists/:id/import" do
    let!(:email_list) { create(:marketing_email_list, account: account) }

    it "imports subscribers" do
      params = {
        subscribers: [
          { email: "new1@example.com", first_name: "John" },
          { email: "new2@example.com", first_name: "Jane" }
        ]
      }

      post "/api/v1/marketing/email_lists/#{email_list.id}/import",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      result = json_response["data"]["import_result"]
      expect(result["imported"]).to eq(2)
    end
  end

  describe "GET /api/v1/marketing/email_lists/:id/subscribers" do
    let!(:email_list) { create(:marketing_email_list, :with_subscribers, account: account) }

    it "returns subscribers" do
      get "/api/v1/marketing/email_lists/#{email_list.id}/subscribers", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"]).to be_an(Array)
      expect(json_response["data"]["items"].length).to be > 0
    end

    it "filters by status" do
      create(:marketing_email_subscriber, :unsubscribed, email_list: email_list)

      get "/api/v1/marketing/email_lists/#{email_list.id}/subscribers",
          params: { status: "subscribed" },
          headers: headers

      expect(response).to have_http_status(:ok)
      json_response["data"]["items"].each do |sub|
        expect(sub["status"]).to eq("subscribed")
      end
    end
  end

  describe "POST /api/v1/marketing/email_lists/:id/add_subscriber" do
    let!(:email_list) { create(:marketing_email_list, account: account) }

    it "adds a subscriber" do
      params = {
        subscriber: {
          email: "new@example.com",
          first_name: "John",
          last_name: "Doe"
        }
      }

      expect {
        post "/api/v1/marketing/email_lists/#{email_list.id}/add_subscriber",
             params: params.to_json,
             headers: headers
      }.to change(Marketing::EmailSubscriber, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["subscriber"]["email"]).to eq("new@example.com")
    end
  end

  describe "DELETE /api/v1/marketing/email_lists/:id/remove_subscriber" do
    let!(:email_list) { create(:marketing_email_list, :with_subscribers, account: account) }
    let(:subscriber) { email_list.email_subscribers.first }

    it "removes a subscriber" do
      expect {
        delete "/api/v1/marketing/email_lists/#{email_list.id}/remove_subscriber",
               params: { subscriber_id: subscriber.id }.to_json,
               headers: headers
      }.to change(Marketing::EmailSubscriber, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end
end
