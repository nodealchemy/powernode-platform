# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  include UserSerialization
  
  before_action :set_user, only: [ :show, :update, :destroy ]
  before_action -> { require_permission('admin.user.view') }, only: [:index, :stats]
  before_action -> { require_permission('admin.user.create') }, only: [:create]
  before_action -> { require_permission('admin.user.delete') }, only: [:destroy]

  # GET /api/v1/users
  def index
    users = current_account.users.includes(:roles)

    render json: {
      success: true,
      data: users.map { |user| user_data(user) }
    }, status: :ok
  end

  # GET /api/v1/users/:id
  def show
    render json: {
      success: true,
      data: user_data(@user)
    }, status: :ok
  end

  # POST /api/v1/users
  def create
    @user = current_account.users.build(user_params)

    if @user.save
      # Assign default roles based on the current plan
      assign_default_roles(@user)

      render json: {
        success: true,
        data: user_data(@user),
        message: "User created successfully"
      }, status: :created
    else
      render json: {
        success: false,
        error: "User creation failed",
        details: @user.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PATCH/PUT /api/v1/users/:id
  def update
    if @user.update(user_update_params)
      render json: {
        success: true,
        data: user_data(@user),
        message: "User updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "User update failed",
        details: @user.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/users/:id
  def destroy
    if @user == current_user
      return render json: {
        success: false,
        error: "Cannot delete your own user account"
      }, status: :unprocessable_content
    end

    if @user.destroy
      render json: {
        success: true,
        message: "User deleted successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "User deletion failed",
        details: @user.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # GET /api/v1/users/stats
  def stats
    users = current_account.users
    
    stats_data = {
      total_users: users.count,
      active_users: users.where(status: 'active').count,
      suspended_users: users.where(status: 'suspended').count,
      unverified_users: users.where(email_verified_at: nil).count,
      recent_logins: users.where('last_login_at >= ?', 7.days.ago).count
    }

    render json: {
      success: true,
      data: stats_data
    }, status: :ok
  end

  private

  def set_user
    @user = User.find(params[:id])

    # First check if user is in a different account (account isolation)
    if @user.account != current_account
      return render json: {
        success: false,
        error: "Access denied"
      }, status: :forbidden
    end

    # Users can only access their own data unless they have users.read permission
    if @user != current_user && !current_user.has_permission?("users.read")
      render json: {
        success: false,
        error: "Access denied"
      }, status: :forbidden
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "User not found"
    }, status: :not_found
  end


  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :password, :password_confirmation)
  end

  def user_update_params
    permitted_params = [ :first_name, :last_name ]

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

    # For single role system, assign the first default role from the plan
    default_role = current_account.subscription.plan.default_roles.first
    if default_role
      role_name = default_role.downcase
      user.update!(role: role_name) if %w[admin owner member].include?(role_name)
    end
  end
end
