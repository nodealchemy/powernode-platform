# frozen_string_literal: true

require "rails_helper"

# Fixture controller mirroring api_response_status_aliases_spec.rb's own
# pattern: a minimal ApplicationController subclass so #render_pending_approval
# behaves exactly as it does for every real caller, isolated from any one
# production controller's routing/permission concerns.
class ApiResponsePendingApprovalTestController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_request,      raise: false

  def show_human_session
    render_pending_approval(fixture_operation(requires_human_session: true))
  end

  def show_ordinary
    render_pending_approval(fixture_operation(requires_human_session: false))
  end

  def show_no_approval_request
    render_pending_approval(fixture_operation(approval_request: nil))
  end

  private

  # Plain Structs, not RSpec doubles — this method runs inside the
  # controller's OWN execution context (a real HTTP request), where
  # `instance_double` (an RSpec::Mocks method, only available in the example
  # context) does not exist at all.
  FixtureApprovalRequest = Struct.new(:id, :requires_human_session) do
    def requires_human_session?
      requires_human_session
    end
  end
  FixtureDeferredOperation = Struct.new(:id, :action_category, :approval_request)

  def fixture_operation(requires_human_session: false, approval_request: :build)
    request =
      if approval_request == :build
        FixtureApprovalRequest.new("req-1", requires_human_session)
      else
        approval_request
      end

    FixtureDeferredOperation.new("op-1", "spec.fixture", request)
  end
end

# IMP-9ce0ed39c557 (security review finding S1) — #render_pending_approval
# gained a `requires_human_session` key so a REST caller deciding a pending
# approval sees the same signal Ai::Tools::BaseTool#pending_payload already
# surfaces to an MCP caller (both read Ai::ApprovalRequest#requires_human_session?).
# Conditional merge, mirroring BaseTool's own: the key must be ABSENT (not
# merely false) for the overwhelming majority of pending-approval responses
# that were never human_only, so this stays a no-op for every other REST
# door.
RSpec.describe "ApiResponse#render_pending_approval — requires_human_session (IMP-9ce0ed39c557)", type: :request do
  before do
    Rails.application.routes.draw do
      get "pending_approval_test/human_session",     to: "api_response_pending_approval_test#show_human_session"
      get "pending_approval_test/ordinary",           to: "api_response_pending_approval_test#show_ordinary"
      get "pending_approval_test/no_approval_request", to: "api_response_pending_approval_test#show_no_approval_request"
    end
  end
  after { Rails.application.reload_routes! }

  it "includes requires_human_session: true when the approval request is human_only" do
    get "/pending_approval_test/human_session"

    expect(response).to have_http_status(:accepted)
    body = response.parsed_body
    expect(body["data"]["pending"]).to be true
    expect(body["data"]["requires_human_session"]).to be true
  end

  it "omits the key entirely for an ordinary (non-human_only) approval request" do
    get "/pending_approval_test/ordinary"

    body = response.parsed_body
    expect(body["data"]["pending"]).to be true
    expect(body["data"]).not_to have_key("requires_human_session")
  end

  it "omits the key when the operation carries no approval_request at all" do
    get "/pending_approval_test/no_approval_request"

    body = response.parsed_body
    expect(body["data"]["pending"]).to be true
    expect(body["data"]).not_to have_key("requires_human_session")
  end
end
