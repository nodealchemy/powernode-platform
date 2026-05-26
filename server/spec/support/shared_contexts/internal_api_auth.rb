# frozen_string_literal: true

# Shared context for internal API specs that need worker authentication.
# InternalBaseController authenticates via mTLS: the reverse proxy verifies
# the worker's client cert and forwards the subject CN (=worker.id) via
# X-Forwarded-Tls-Client-Cert-Info. Specs simulate that by setting the
# header directly.
RSpec.shared_context 'internal api auth' do
  let(:internal_account) { create(:account) }
  let(:internal_worker)  { create(:worker, account: internal_account) }
  let(:service_headers) do
    {
      'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")),
      'Content-Type' => 'application/json'
    }
  end
end
