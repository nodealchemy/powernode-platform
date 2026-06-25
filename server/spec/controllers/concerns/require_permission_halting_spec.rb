# frozen_string_literal: true

require "rails_helper"

# Defense-in-depth: require_permission/require_any_permission/require_all_permissions
# must SELF-HALT. Previously they rendered a 403 but did not halt, so they were
# only safe as before_action filters; used inline in an action body the body kept
# running (side effect executed, then a double-render). The hardening makes them
# raise Authentication::PermissionDenied — a deliberately non-StandardError
# exception so action-body `rescue StandardError` / the global rescue_from
# StandardError cannot swallow it into a 500 — handled by a dedicated rescue_from
# that renders the same 403 shape.
RSpec.describe "require_permission self-halting", type: :controller do
  controller(ApplicationController) do
    skip_before_action :authenticate_request, raise: false

    # Canonical correct usage — a before_action gate.
    before_action -> { require_permission("needs.perm") }, only: :gated_action

    def gated_action
      render json: { reached: true }
    end

    # The dangerous pattern: an inline check in an action body. The line AFTER
    # the check must NOT run when denied (this is exactly what the old
    # render-without-halt behavior got wrong).
    def inline_then_mutate
      require_permission("needs.perm")
      @reached_after_check = true
      render json: { reached: true }
    end

    # An inline check wrapped in the kind of `rescue StandardError` several real
    # action bodies use — must still produce a clean 403, not a swallowed 500.
    def inline_guarded_by_rescue
      require_permission("needs.perm")
      render json: { reached: true }
    rescue StandardError => e
      render json: { swallowed: e.class.name }, status: :internal_server_error
    end
  end

  before do
    routes.draw do
      get "gated_action" => "anonymous#gated_action"
      post "inline_then_mutate" => "anonymous#inline_then_mutate"
      post "inline_guarded_by_rescue" => "anonymous#inline_guarded_by_rescue"
    end
    allow(controller).to receive(:has_permission?).and_return(false)
  end

  describe "Authentication::PermissionDenied" do
    it "is defined and lives OUTSIDE the StandardError hierarchy" do
      expect(defined?(Authentication::PermissionDenied)).to be_truthy
      expect(Authentication::PermissionDenied.ancestors).not_to include(StandardError)
      expect(Authentication::PermissionDenied.new("x")).to be_a(Exception)
    end
  end

  describe "as a before_action gate" do
    it "renders 403 and never runs the action" do
      get :gated_action
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("reached")
    end
  end

  describe "inline in an action body" do
    it "halts — code after the check does NOT run when denied" do
      post :inline_then_mutate
      expect(response).to have_http_status(:forbidden)
      expect(controller.instance_variable_get(:@reached_after_check)).to be_falsey
    end
  end

  describe "inline, wrapped in rescue StandardError" do
    it "is NOT swallowed into a 500 — renders a clean 403" do
      post :inline_guarded_by_rescue
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("swallowed")
      expect(response.body).not_to include("reached")
    end
  end
end
