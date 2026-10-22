# frozen_string_literal: true

require 'rails_helper'
require 'rack/mock'

# The server signs the JWTs it sends the worker with aud "worker"
# (Security::JwtService.encode_for_worker), so a worker job token is never a
# valid server API token and a server API token is never a worker job token.
# The worker requires exactly aud "worker": an older server signs with
# aud "powernode-api", so the backend must be deployed before the worker (on
# the hub both ship in one build).
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

  it 'refuses a worker token with no aud' do
    expect(controller.send(:authenticated?, request_with({}))).to be(false)
  end

  it 'refuses a token whose type is not worker, even with aud "worker"' do
    expect(controller.send(:authenticated?, request_with('aud' => 'worker', 'type' => 'access'))).to be(false)
  end

  it 'refuses a token minted for the server API' do
    expect(controller.send(:authenticated?, request_with('aud' => 'powernode-api'))).to be(false)
  end
end
