# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-db6cc3d85fb6.
#
# The canonical integration controllers live under /api/v1/devops/integration_*.
# The /api/v1/integrations namespace is a thin FACADE that intentionally exposes
# ONLY `instances` (see routes.rb "Integrations facade" comment). Three sibling
# controllers (Integrations::{Templates,Credentials,Executions}Controller) were
# unrouted dead duplicates of the devops tree and have been removed.
#
# This guards the intended surface so the dead duplicates are not reintroduced.
# (The removal is behavior-neutral — those paths were never routed — so this is a
# regression guard, not a red->green spec.)
RSpec.describe 'Integrations API surface', type: :routing do
  it 'routes the canonical devops integration tree' do
    expect(get: '/api/v1/devops/integration_templates').to be_routable
    expect(get: '/api/v1/devops/integration_credentials').to be_routable
    expect(get: '/api/v1/devops/integration_executions').to be_routable
    expect(get: '/api/v1/devops/integration_instances').to be_routable
  end

  it 'exposes ONLY instances under the integrations facade (no dead duplicates)' do
    expect(get: '/api/v1/integrations/instances').to be_routable

    expect(get: '/api/v1/integrations/templates').not_to be_routable
    expect(get: '/api/v1/integrations/credentials').not_to be_routable
    expect(get: '/api/v1/integrations/executions').not_to be_routable
  end
end
