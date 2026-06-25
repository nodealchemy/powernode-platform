# frozen_string_literal: true

require "rails_helper"

# The chat `resources :sessions`/`resources :channels` blocks must expose only
# the RESTful actions their controllers actually implement. SessionsController
# implements index/show/update/destroy (+ custom member/collection actions) but
# NOT create/new/edit; routing those generated a POST /chat/sessions with no
# action (404 ActionNotFound) that could not be gated at the controller layer
# (Rails 8 raise_on_missing_callback_actions). Closing the route is the fix.
RSpec.describe "Api::V1::Chat routes", type: :routing do
  describe "sessions" do
    it "does NOT route the unimplemented create (POST /api/v1/chat/sessions)" do
      expect(post: "/api/v1/chat/sessions").not_to be_routable
    end

    it "does NOT route the unimplemented new (GET /api/v1/chat/sessions/new) to #new" do
      # With create/new/edit removed, /new falls through to #show (id: 'new').
      expect(get: "/api/v1/chat/sessions/new")
        .not_to route_to(controller: "api/v1/chat/sessions", action: "new")
    end

    it "still routes the implemented RESTful actions" do
      expect(get: "/api/v1/chat/sessions").to route_to("api/v1/chat/sessions#index")
      expect(get: "/api/v1/chat/sessions/abc").to route_to("api/v1/chat/sessions#show", id: "abc")
      expect(patch: "/api/v1/chat/sessions/abc").to route_to("api/v1/chat/sessions#update", id: "abc")
      expect(delete: "/api/v1/chat/sessions/abc").to route_to("api/v1/chat/sessions#destroy", id: "abc")
    end

    it "still routes the custom member/collection actions" do
      expect(post: "/api/v1/chat/sessions/abc/close").to route_to("api/v1/chat/sessions#close", id: "abc")
      expect(get: "/api/v1/chat/sessions/active").to route_to("api/v1/chat/sessions#active")
      expect(get: "/api/v1/chat/sessions/stats").to route_to("api/v1/chat/sessions#stats")
    end
  end

  describe "channels" do
    it "does NOT route the unimplemented new (GET /api/v1/chat/channels/new) to #new" do
      expect(get: "/api/v1/chat/channels/new")
        .not_to route_to(controller: "api/v1/chat/channels", action: "new")
    end

    it "still routes the implemented RESTful + custom actions" do
      expect(get: "/api/v1/chat/channels").to route_to("api/v1/chat/channels#index")
      expect(post: "/api/v1/chat/channels").to route_to("api/v1/chat/channels#create")
      expect(post: "/api/v1/chat/channels/abc/regenerate_token")
        .to route_to("api/v1/chat/channels#regenerate_token", id: "abc")
      expect(post: "/api/v1/chat/channels/cleanup_sessions")
        .to route_to("api/v1/chat/channels#cleanup_sessions")
    end
  end
end
