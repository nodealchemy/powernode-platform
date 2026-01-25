# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  include UserSerialization

  before_action :set_user, only: [ :show, :update, :destroy ]
  before_action -> { require_permission("admin.user.view") }, only: [ :index, :stats ]
  before_action -> { require_permission("admin.user.create") }, only: [ :create ]
  before_action -> { require_permission("admin.user.delete") }, only: [ :destroy ]

  # GET /api/v1/users
  def index
    users = current_account.users.includes(:roles)

    # Pagination using Kaminari
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 25, 100 ].min # Default 25, max 100

    paginated_users = users.page(page).per(per_page)

    render_success(
      paginated_users.map { |user| user_data(user) },
      meta: {
        pagination: {
          current_page: paginated_users.current_page,
          per_page: paginated_users.limit_value,
          total_pages: paginated_users.total_pages,
          total_count: paginated_users.total_count
        }
      }
    )
  end

  # GET /api/v1/users/:id
  def show
    render_success(user_data(@user))
  end

  # POST /api/v1/users
  def create
    # Check usage limit before creating user
    unless Billing::UsageLimitService.can_add_user?(current_account)
      render_error("User limit reached for your current plan", status: :forbidden)
      return
    end

    @user = current_account.users.build(user_params)

    if @user.save
      # Assign default roles based on the current plan
      assign_default_roles(@user)

      render_success(user_data(@user), status: :created)
    else
      render_validation_error(@user)
    end
  end

  # PATCH/PUT /api/v1/users/:id
  def update
    if @user.update(user_update_params)
      render_success(user_data(@user))
    else
      render_validation_error(@user)
    end
  end

  # DELETE /api/v1/users/:id
  def destroy
    if @user == current_user
      return render_error(
        "Cannot delete your own user account",
        :unprocessable_content
      )
    end

    if @user.destroy
      render_success(nil)
    else
      render_validation_error(@user)
    end
  end

  # GET /api/v1/users/stats
  def stats
    users = current_account.users

    stats_data = {
      total_users: users.count,
      active_users: users.where(status: "active").count,
      suspended_users: users.where(status: "suspended").count,
      unverified_users: users.where(email_verified_at: nil).count,
      recent_logins: users.where("last_login_at >= ?", 7.days.ago).count
    }

    render_success(stats_data)
  end

  private

  def set_user
    # Scope query to current_account first to prevent IDOR
    @user = current_account.users.find(params[:id])

    # Users can only access their own data unless they have users.read permission
    if @user != current_user && !current_user.has_permission?("users.read")
      render_error("Access denied", status: :forbidden)
    end
  rescue ActiveRecord::RecordNotFound
    render_error("User not found", status: :not_found)
  end


  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end

  def user_update_params
    permitted_params = [ :name ]

    # Only allow email and password updates for self or if user has users.update permission
    if @user == current_user || current_user.has_permission?("users.update")
      permitted_params += [ :email ]
    end

    # Only allow password updates if current password is provided
    if params[:user][:password].present? && params[:user][:current_password].present?
      if @user.authenticate(params[:user][:current_password])
        permitted_params += [ :password, :password_confirmation ]
      end
    end

    params.require(:user).permit(permitted_params)
  end

  # Remove this method to use the one from UserSerialization concern
  # The concern's user_data method properly handles permissions

  def assign_default_roles(user)
    return unless current_account.subscription&.plan

    # Assign all default roles from the plan using new permission-based system
    plan = current_account.subscription.plan
    plan.default_roles.each do |role_name|
      role = Role.find_by(name: role_name)
      user.add_role(role.name) if role
    end
  end
end
