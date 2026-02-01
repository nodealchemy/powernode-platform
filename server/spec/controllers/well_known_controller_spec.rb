# frozen_string_literal: true

require "rails_helper"

RSpec.describe WellKnownController, type: :controller do
  describe "GET #agent_card" do
    it "returns the platform agent card" do
      get :agent_card

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["name"]).to eq("Powernode")
      expect(json["url"]).to include("/a2a")
      expect(json["version"]).to be_present
      expect(json["protocolVersion"]).to be_present
    end

    it "includes capabilities" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["capabilities"]).to include(
        "streaming" => true,
        "pushNotifications" => true
      )
    end

    it "includes authentication schemes" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["authentication"]["schemes"]).to include("bearer", "api_key")
    end

    it "includes skills" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["skills"]).to be_an(Array)
      expect(json["skills"].first).to include("id", "name", "description")
    end

    it "includes input/output modes" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["defaultInputModes"]).to include("text/plain", "application/json")
      expect(json["defaultOutputModes"]).to include("text/plain", "application/json")
    end
  end
end
