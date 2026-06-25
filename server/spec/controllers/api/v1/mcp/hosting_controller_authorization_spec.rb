# frozen_string_literal: true

require "rails_helper"

# mcp/hosting_controller previously ran on authentication alone (no authorization)
# — any account member could deploy/rollback/start/stop/publish/delete a hosted MCP
# server. Gate on the mcp.* family: reads -> mcp.servers.read; lifecycle/publish/
# subscribe -> mcp.servers.write; start/stop/restart -> mcp.executions.write.
#
# Hosting's ROUTES live in the business extension (absent in core mode), so this is
# a controller spec with routes.draw rather than a request spec (the sibling
# request spec at spec/requests/api/v1/mcp/hosting_spec.rb skips without business).
RSpec.describe Api::V1::Mcp::HostingController, type: :controller do
  let(:account) { create(:account) }
  let(:no_perm) { create(:user, account: account, permissions: []) }
  let(:reader)  { create(:user, account: account, permissions: [ "mcp.servers.read" ]) }
  let(:writer)  { create(:user, account: account, permissions: [ "mcp.servers.read", "mcp.servers.write" ]) }
  let(:runner)  { create(:user, account: account, permissions: [ "mcp.servers.read", "mcp.executions.write" ]) }

  before do
    routes.draw do
      get  "index"  => "api/v1/mcp/hosting#index"
      post "deploy" => "api/v1/mcp/hosting#deploy"
      post "start"  => "api/v1/mcp/hosting#start"
    end
    # Mcp::HostingService lives in the business extension (absent in core mode);
    # define a no-op stand-in so the PERMITTED cases reach a non-403 response
    # without the real service. (FORBIDDEN cases halt at the gate, before this.)
    stub_const("Mcp::HostingService", Class.new do
      def initialize(*); end
      def respond_to_missing?(*) = true
      def method_missing(*) = {}
    end)
  end

  describe "index (read tier)" do
    it "forbids a user with no mcp perms" do
      sign_in_as_user(no_perm)
      get :index
      expect(response).to have_http_status(:forbidden)
    end

    it "permits mcp.servers.read" do
      sign_in_as_user(reader)
      get :index
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe "deploy (write tier)" do
    it "forbids a read-only holder (read is not write)" do
      sign_in_as_user(reader)
      post :deploy, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:forbidden)
    end

    it "permits mcp.servers.write" do
      sign_in_as_user(writer)
      post :deploy, params: { id: SecureRandom.uuid }
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe "start (executions tier)" do
    it "forbids a servers.write holder lacking mcp.executions.write" do
      sign_in_as_user(writer)
      post :start, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:forbidden)
    end

    it "permits mcp.executions.write" do
      sign_in_as_user(runner)
      post :start, params: { id: SecureRandom.uuid }
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
