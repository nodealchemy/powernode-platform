# frozen_string_literal: true

# Shared context for internal API specs that need worker authentication.
# InternalBaseController validates JWT tokens (type: "worker", sub: worker_id).
RSpec.shared_context 'internal api auth' do
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:service_headers) do
    token = Security::JwtService.encode(
      { type: "worker", sub: internal_worker.id },
      5.minutes.from_now
    )
    { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }
  end
end
