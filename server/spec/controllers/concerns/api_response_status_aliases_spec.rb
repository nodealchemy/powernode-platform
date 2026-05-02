# frozen_string_literal: true

require "rails_helper"

# Controller used purely as a fixture for the alias spec below. Inheriting
# from ApplicationController gives us the same mixin chain real callers
# get (including ApiResponse), so render_error / render_success behave
# identically to production. Auth is skipped — we're exercising the
# render-status path, not the authentication middleware.
class ApiResponseAliasTestController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :authenticate_request,      raise: false

  def show_unprocessable_entity
    render_error("legacy 422 caller", :unprocessable_entity)
  end

  def show_unprocessable_entity_kwarg
    render_error("legacy 422 caller (kwarg)", status: :unprocessable_entity)
  end

  def show_content_too_large
    render_error("legacy 413", :request_entity_too_large)
  end

  def show_uri_too_long
    render_error("legacy 414", :request_uri_too_long)
  end

  def show_modern
    render_error("modern 422 caller", :unprocessable_content)
  end

  def show_success_with_alias
    render_success(message: "ok", status: :unprocessable_entity)
  end
end

# Locks the deprecated-Rack-status-symbol translation so the 34
# `render_error(..., :unprocessable_entity)` callers across the
# codebase don't 500 after the Rack upgrade.
#
# Symbols affected (per Rack 3 / RFC 9110 alignment):
#   :unprocessable_entity     -> :unprocessable_content (422)
#   :request_entity_too_large -> :content_too_large     (413)
#   :payload_too_large        -> :content_too_large     (413)
#   :request_uri_too_long     -> :uri_too_long          (414)
RSpec.describe "ApiResponse deprecated status aliases", type: :request do
  before do
    Rails.application.routes.draw do
      get "alias_test/unprocessable_entity",       to: "api_response_alias_test#show_unprocessable_entity"
      get "alias_test/unprocessable_entity_kwarg", to: "api_response_alias_test#show_unprocessable_entity_kwarg"
      get "alias_test/content_too_large",          to: "api_response_alias_test#show_content_too_large"
      get "alias_test/uri_too_long",               to: "api_response_alias_test#show_uri_too_long"
      get "alias_test/modern",                     to: "api_response_alias_test#show_modern"
      get "alias_test/success_alias",              to: "api_response_alias_test#show_success_with_alias"
    end
  end
  after { Rails.application.reload_routes! }

  it "translates :unprocessable_entity (positional) to 422" do
    get "/alias_test/unprocessable_entity"
    expect(response.status).to eq(422)
  end

  it "translates :unprocessable_entity (kwarg) to 422" do
    get "/alias_test/unprocessable_entity_kwarg"
    expect(response.status).to eq(422)
  end

  it "translates :request_entity_too_large to 413" do
    get "/alias_test/content_too_large"
    expect(response.status).to eq(413)
  end

  it "translates :request_uri_too_long to 414" do
    get "/alias_test/uri_too_long"
    expect(response.status).to eq(414)
  end

  it "passes the modern :unprocessable_content through unchanged" do
    get "/alias_test/modern"
    expect(response.status).to eq(422)
  end

  it "applies the alias on render_success too" do
    get "/alias_test/success_alias"
    expect(response.status).to eq(422)
  end
end
