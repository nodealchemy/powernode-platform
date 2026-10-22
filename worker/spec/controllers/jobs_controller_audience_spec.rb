# frozen_string_literal: true

require 'rails_helper'
require 'rack/mock'

# The server signs the JWTs it sends the worker with aud "worker"
# (Security::JwtService.encode_for_worker), so a worker job token is never a
# valid server API token and a server API token is never a worker job token.
#
# Compatibility for one release: a token with NO aud is still accepted, so the
# server and the worker can be deployed in either order. Remove that branch
# once every server signs with aud "worker".
RSpec.describe JobsController, 'worker JWT audience' do
  let(:secret) { 'test-jobs-controller-audience-secret' }
  let(:controller) { described_class.new }

  before { allow(controller).to receive(:jwt_secret_key).and_return(secret) }

  def request_with(claims)
    token = JWT.encode({ 'type' => 'worker', 'sub' => 'system' }.merge(claims), secret, 'HS256')
    Rack::Request.new(Rack::MockRequest.env_for('/', 'HTTP_AUTHORIZATION' => "Bearer #{token}"))
  end

  it 'accepts a worker token whose aud is "worker"' do
    expect(controller.send(:authenticated?, request_with('aud' => 'worker'))).to be(true)
  end

  it 'accepts a worker token with no aud (servers older than this release)' do
    expect(controller.send(:authenticated?, request_with({}))).to be(true)
  end

  it 'refuses a token minted for the server API' do
    expect(controller.send(:authenticated?, request_with('aud' => 'powernode-api'))).to be(false)
  end
end
