# frozen_string_literal: true

# Public discovery surface for the runtime (dedicated-module) extension frontend
# loader. The React app fetches this before first render to decide which
# extension frontend bundles to load and register at runtime.
class Api::V1::ExtensionsController < ApplicationController
  # authz-ok: public bootstrap discovery, read-only, no tenant state. Runs during
  # app boot before any session exists; returns only extension slug/version/enabled
  # which are already present in the public frontend bundle (__EXTENSIONS__) and
  # non-secret. Mirrors config#index (also unauthenticated bootstrap config).
  #
  # UNAUTHENTICATED: this runs during app bootstrap, before any session exists.
  # Disclosure is ~zero — extension slugs are already present in the public
  # frontend bundle (compiled into __EXTENSIONS__) and versions are non-secret.
  skip_before_action :authenticate_request, only: [ :ui ]

  # GET /api/v1/extensions/ui
  # Enabled/disabled state of every on-disk extension that ships a frontend.
  # -> { extensions: [{ slug:, version:, enabled: }] }
  def ui
    render_success(data: { extensions: Shared::FeatureGateService.frontend_extensions })
  end
end
