# frozen_string_literal: true

require 'spec_helper'

# IMP-d790553994c2: expect_api_request silently ignored a passed block, so
# block-form body assertions across the suite never executed (false green).
# The helper must yield each matched request to the block and surface the
# block's assertion failures.
RSpec.describe 'ApiTestHelpers#expect_api_request' do
  include ApiTestHelpers

  let(:url) { build_api_url('/api/v1/probe') }

  before do
    stub_request(:post, url).to_return(status: 200, body: '{}')
    HTTParty.post(url, headers: expected_request_headers, body: { probe: 42 }.to_json)
  end

  it 'yields the matched request to a passed block' do
    yielded_body = nil
    expect_api_request(:post, '/api/v1/probe') do |request|
      yielded_body = JSON.parse(request.body)
    end

    expect(yielded_body).to eq('probe' => 42)
  end

  it 'surfaces assertion failures raised inside the block' do
    expect do
      expect_api_request(:post, '/api/v1/probe') do |request|
        expect(JSON.parse(request.body)['probe']).to eq(999)
      end
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it 'still verifies the request without a block (existing behavior)' do
    expect_api_request(:post, '/api/v1/probe', with_body: { probe: 42 })
  end
end
