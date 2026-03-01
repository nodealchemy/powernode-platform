# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing Content Calendar API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("marketing.calendar.read", "marketing.calendar.manage", account: account) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/marketing/calendar" do
    let!(:entry1) { create(:marketing_content_calendar, account: account, scheduled_date: Date.current) }
    let!(:entry2) { create(:marketing_content_calendar, account: account, scheduled_date: 1.week.from_now.to_date) }
    let!(:other_account_entry) { create(:marketing_content_calendar) }

    it "returns calendar entries for the account" do
      get "/api/v1/marketing/calendar", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(2)
    end

    it "filters by date range" do
      get "/api/v1/marketing/calendar",
          params: { start_date: Date.current.to_s, end_date: (Date.current + 2.days).to_s },
          headers: headers

      expect(response).to have_http_status(:ok)
      items = json_response["data"]["items"]
      expect(items.length).to eq(1)
    end

    it "filters by entry type" do
      email_entry = create(:marketing_content_calendar, :email, account: account)
      get "/api/v1/marketing/calendar", params: { entry_type: "email" }, headers: headers

      expect(response).to have_http_status(:ok)
      ids = json_response["data"]["items"].map { |i| i["id"] }
      expect(ids).to include(email_entry.id)
    end

    it "requires authentication" do
      get "/api/v1/marketing/calendar"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires permission" do
      no_perm_user = user_with_permissions(account: account)
      get "/api/v1/marketing/calendar", headers: auth_headers_for(no_perm_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/marketing/calendar" do
    let(:valid_params) do
      {
        calendar: {
          title: "Blog Post",
          entry_type: "post",
          scheduled_date: 1.week.from_now.to_date.to_s,
          scheduled_time: "09:00",
          status: "planned"
        }
      }
    end

    it "creates a calendar entry" do
      expect {
        post "/api/v1/marketing/calendar", params: valid_params.to_json, headers: headers
      }.to change(Marketing::ContentCalendar, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["entry"]["title"]).to eq("Blog Post")
    end

    it "validates required fields" do
      post "/api/v1/marketing/calendar",
           params: { calendar: { title: "" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/marketing/calendar/:id" do
    let!(:entry) { create(:marketing_content_calendar, account: account) }

    it "updates the entry" do
      patch "/api/v1/marketing/calendar/#{entry.id}",
            params: { calendar: { title: "Updated Title" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["entry"]["title"]).to eq("Updated Title")
    end
  end

  describe "DELETE /api/v1/marketing/calendar/:id" do
    let!(:entry) { create(:marketing_content_calendar, account: account) }

    it "deletes the entry" do
      expect {
        delete "/api/v1/marketing/calendar/#{entry.id}", headers: headers
      }.to change(Marketing::ContentCalendar, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/marketing/calendar/conflicts" do
    let(:date) { 1.week.from_now.to_date }

    before do
      create(:marketing_content_calendar, account: account, scheduled_date: date, scheduled_time: "09:00")
    end

    it "detects conflicts" do
      get "/api/v1/marketing/calendar/conflicts",
          params: { date: date.to_s },
          headers: headers

      expect(response).to have_http_status(:ok)
      conflicts = json_response["data"]["conflicts"]
      expect(conflicts["has_conflicts"]).to be true
      expect(conflicts["count"]).to eq(1)
    end
  end
end
