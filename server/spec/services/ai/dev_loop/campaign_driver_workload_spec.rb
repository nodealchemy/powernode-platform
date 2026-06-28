# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver do
  let(:account) { create(:account) }
  let(:driver) { described_class.new(account: account) }

  describe "#start workload" do
    it "defaults to improvement-campaign" do
      r = driver.start(name: "improve")
      expect(r[:campaign].configuration["workload"]).to eq("improvement-campaign")
      expect(r[:loop].configuration["workload"]).to eq("improvement-campaign")
    end

    it "supports development workloads on both campaign and loop" do
      %w[feature-development new-project].each do |w|
        r = driver.start(name: "c-#{w}", workload: w)
        expect(r[:campaign].configuration["workload"]).to eq(w)
        expect(r[:loop].configuration["workload"]).to eq(w)
        expect(r[:loop].description).to include(w)
      end
    end

    it "falls back to the default on an unknown workload" do
      r = driver.start(name: "bad", workload: "nonsense")
      expect(r[:campaign].configuration["workload"]).to eq("improvement-campaign")
    end

    it "preserves caller configuration alongside the workload tag" do
      r = driver.start(name: "scoped", workload: "feature-development",
                       configuration: { "scope" => "server/app" })
      expect(r[:campaign].configuration).to include("scope" => "server/app", "workload" => "feature-development")
    end
  end
end
