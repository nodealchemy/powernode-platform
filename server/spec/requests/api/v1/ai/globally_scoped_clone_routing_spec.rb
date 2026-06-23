# frozen_string_literal: true

require "rails_helper"

# Regression guard for the GloballyScopedContent `clone` endpoint.
#
# `clone` collides with Ruby's Object#clone: Rails' action_methods only re-adds
# Object-masked methods that are defined *directly* on the controller, so a
# module-provided `clone` was omitted and POST .../clone raised
# AbstractController::ActionNotFound (500). The concern now exposes
# `perform_clone`, and the `clone` URL segment is routed to it via
# `action: :perform_clone`. These endpoints had no request-spec coverage, which
# is how the bug shipped.
RSpec.describe "GloballyScopedContent clone routing", type: :request do
  # controller path => POST clone URL (":id" stubbed)
  CLONE_ENDPOINTS = {
    "api/v1/ai/skills"                 => "/api/v1/ai/skills/x/clone",
    "api/v1/ai/rag"                    => "/api/v1/ai/rag/knowledge_bases/x/clone",
    "api/v1/ai/prompt_templates"       => "/api/v1/ai/prompt_templates/x/clone",
    "api/v1/ai/mission_templates"      => "/api/v1/ai/mission_templates/x/clone",
    "api/v1/ai/team_templates_reviews" => "/api/v1/ai/teams/templates/x/clone",
    "api/v1/ai/devops"                 => "/api/v1/ai/devops/templates/x/clone"
  }.freeze

  it "exposes #perform_clone as a dispatchable action and never overrides Object#clone" do
    CLONE_ENDPOINTS.each_key do |controller_path|
      klass = "#{controller_path}_controller".camelize.constantize
      expect(klass.action_methods).to include("perform_clone"),
        "#{klass} must expose #perform_clone as a routable action"
      expect(klass.action_methods).not_to include("clone"),
        "#{klass} must not override Object#clone"
    end
  end

  it "routes every clone URL to #perform_clone" do
    CLONE_ENDPOINTS.each do |controller_path, url|
      recognized = Rails.application.routes.recognize_path(url, method: :post)
      expect(recognized[:controller]).to eq(controller_path)
      expect(recognized[:action]).to eq("perform_clone")
    end
  end
end
