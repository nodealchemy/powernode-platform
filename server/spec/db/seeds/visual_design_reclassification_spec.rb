# frozen_string_literal: true

require "rails_helper"

# Visual Design Assistant was mistyped image_generator but produces TEXT (design
# briefs, UI specs, image-generation prompts) with a reasoning-tier text model.
# The image_generator type would steer model selection to an image model. These
# specs pin the reclassification to content_generator — including the in-place
# data-fix for an already-seeded (stale) row, since find_or_create_by!(name:)
# won't update an existing record's agent_type.
RSpec.describe "Visual Design Assistant reclassification (autonomy_data_seed)" do
  def load_seed!
    silence_warnings { load Rails.root.join("db", "seeds", "autonomy_data_seed.rb") }
  end

  let!(:account)  { create(:account, name: "Powernode Admin") }
  let!(:user)     { create(:user, account: account, email: "admin@powernode.org") }
  let!(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }

  it "creates Visual Design Assistant as content_generator (not image_generator)" do
    load_seed!
    agent = Ai::Agent.find_by(account: account, slug: "visual-design-assistant")
    expect(agent).to be_present
    expect(agent.agent_type).to eq("content_generator")
  end

  it "reclassifies an already-seeded image_generator row in place" do
    stale = create(:ai_agent, account: account, name: "Visual Design Assistant",
                              slug: "visual-design-assistant", agent_type: "image_generator")

    load_seed!
    stale.reload

    expect(stale.agent_type).to eq("content_generator")
    expect(Ai::Agent.where(account: account, slug: "visual-design-assistant").count).to eq(1)
  end
end
