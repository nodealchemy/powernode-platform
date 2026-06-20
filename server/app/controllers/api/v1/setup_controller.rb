# frozen_string_literal: true

# First-run / incremental setup wizard, driven by Setup::StepRegistry.
#
# All actions are authenticated `system.admin` routes EXCEPT #admin, which runs
# before any user exists and therefore cannot use JWT — it is gated by a one-time
# bootstrap token (Setup::BootstrapToken) and self-disables once an admin exists.
class Api::V1::SetupController < ApplicationController
  include RefreshTokenCookie

  # /setup/admin and /setup/status are reachable before any user exists. status
  # uses optional auth: a logged-in admin gets full per-account detail, while an
  # anonymous first-run visitor still learns whether bootstrap is needed (so the
  # public wizard knows whether to show the admin step).
  skip_before_action :authenticate_request, only: [ :admin, :status ]
  before_action :authenticate_optional, only: [ :status ]
  before_action :require_setup_admin!, only: [ :steps, :submit_step ]

  # GET /api/v1/setup/status
  def status
    if current_account
      render_success(data: {
        bootstrap_complete: Setup::StepRegistry.bootstrap_complete?(current_account),
        pending: Setup::StepRegistry.pending(current_account)
      })
    else
      # Anonymous first-run probe: expose only the global bootstrap fact.
      render_success(data: { bootstrap_complete: User.exists?, pending: [] })
    end
  end

  # GET /api/v1/setup/steps
  def steps
    render_success(data: { steps: Setup::StepRegistry.steps_for(current_account) })
  end

  # POST /api/v1/setup/steps/:key — persist one core step and stamp completion.
  def submit_step
    step = Setup::StepRegistry.find(params[:key])
    return render_not_found("Setup step") if step.nil?

    # Extension steps POST to their own endpoint; the admin step has /setup/admin.
    unless step[:owner] == "core" && step[:key] != "admin"
      return render_error("Step is not submittable here", :unprocessable_content, code: "invalid_setup_step")
    end

    error = persist_core_step(step[:key])
    return render_error(error, :unprocessable_content, code: "invalid_setup_step") if error

    current_account.mark_setup_step!(step[:key])
    render_success(data: { step: Setup::StepRegistry.annotate(step, current_account) })
  end

  # POST /api/v1/setup/admin — UNAUTHENTICATED, bootstrap-token-gated, one-shot.
  def admin
    return already_bootstrapped if User.exists?
    return render_unauthorized("Invalid or missing setup token") unless Setup::BootstrapToken.verify(params[:token])

    result = Setup::FirstAdminService.call(
      email: admin_params[:email],
      password: admin_params[:password],
      name: admin_params[:name]
    )

    Setup::BootstrapToken.clear!

    # Billing seam: the business extension subscribes to this and provisions a
    # subscription. Core never creates billing records.
    ActiveSupport::Notifications.instrument(
      "powernode.user.registered",
      account_id: result.account.id,
      user_id: result.user.id,
      plan_id: nil
    )

    tokens = Security::JwtService.generate_user_tokens(result.user)
    # Establish a full session so the wizard can continue into authenticated
    # steps (domain, …) via the standard refresh-cookie path — same as registration.
    set_refresh_cookie(tokens[:refresh_token])
    render_success(
      status: :created,
      message: "Administrator created",
      data: {
        user: { id: result.user.id, email: result.user.email, name: result.user.name },
        account: { id: result.account.id, name: result.account.name },
        access_token: tokens[:access_token],
        expires_at: tokens[:expires_at]
      }
    )
  rescue Setup::FirstAdminService::AlreadyBootstrapped
    already_bootstrapped
  rescue ActiveRecord::RecordInvalid => e
    render_error(
      e.record.errors.full_messages.first || "Administrator creation failed",
      :unprocessable_content,
      details: e.record.errors.full_messages
    )
  end

  private

  def already_bootstrapped
    render_error("An administrator already exists", :conflict, code: "already_bootstrapped")
  end

  def require_setup_admin!
    require_permission("system.admin")
  end

  def admin_params
    {
      name: params[:name] || params.dig(:admin, :name),
      email: params[:email] || params.dig(:admin, :email),
      password: params[:password] || params.dig(:admin, :password)
    }
  end

  # Persist one core step's payload to its owning core setting, returning an error
  # message string on validation failure (nil on success). Phase 1 owns the domain
  # step; other core config steps (email, general settings) land here in Phase 2.
  def persist_core_step(key)
    case key
    when "domain"
      domain = (params[:domain] || params.dig(:payload, :domain)).to_s.strip
      return "Domain is required" if domain.blank?

      SiteSetting.set("domain", domain, description: "Public domain for this instance", is_public: true)
      nil
    else
      "No handler for setup step '#{key}'"
    end
  end
end
