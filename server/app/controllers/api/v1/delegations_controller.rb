class Api::V1::DelegationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account
  before_action :set_delegation, only: [:show, :update, :destroy, :activate, :deactivate, :revoke]
  before_action :authorize_delegation_management!, except: [:show]
  before_action :authorize_delegation_view!, only: [:show]

  # GET /api/v1/accounts/:account_id/delegations
  def index
    @delegations = @account.account_delegations
                          .includes(:delegated_user, :delegated_by, :role, :revoked_by)
                          .order(:created_at)
    
    # Filter by status if provided
    @delegations = @delegations.where(status: params[:status]) if params[:status].present?
    
    # Filter by role if provided
    @delegations = @delegations.where(role_id: params[:role_id]) if params[:role_id].present?
    
    render json: {
      delegations: @delegations.map { |d| delegation_json(d) },
      meta: {
        total_count: @delegations.count,
        active_count: @delegations.active.count,
        expired_count: @delegations.select(&:expired?).count
      }
    }
  end

  # GET /api/v1/accounts/:account_id/delegations/:id
  def show
    render json: { delegation: delegation_json(@delegation) }
  end

  # POST /api/v1/accounts/:account_id/delegations
  def create
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.create_delegation(
      delegated_user_email: delegation_params[:delegated_user_email],
      role_id: delegation_params[:role_id],
      permission_ids: delegation_params[:permission_ids],
      expires_at: delegation_params[:expires_at],
      notes: delegation_params[:notes]
    )
    
    if result[:success]
      render json: { 
        delegation: delegation_json(result[:delegation]),
        message: "Delegation created successfully"
      }, status: :created
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to create delegation"
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/accounts/:account_id/delegations/:id
  def update
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.update_delegation(
      delegation: @delegation,
      role_id: delegation_params[:role_id],
      permission_ids: delegation_params[:permission_ids],
      expires_at: delegation_params[:expires_at],
      notes: delegation_params[:notes]
    )
    
    if result[:success]
      render json: { 
        delegation: delegation_json(@delegation.reload),
        message: "Delegation updated successfully"
      }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to update delegation"
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/accounts/:account_id/delegations/:id
  def destroy
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.revoke_delegation(@delegation)
    
    if result[:success]
      render json: { message: "Delegation revoked successfully" }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to revoke delegation"
      }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/accounts/:account_id/delegations/:id/activate
  def activate
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.activate_delegation(@delegation)
    
    if result[:success]
      render json: { 
        delegation: delegation_json(@delegation.reload),
        message: "Delegation activated successfully"
      }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to activate delegation"
      }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/accounts/:account_id/delegations/:id/deactivate
  def deactivate
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.deactivate_delegation(@delegation)
    
    if result[:success]
      render json: { 
        delegation: delegation_json(@delegation.reload),
        message: "Delegation deactivated successfully"
      }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to deactivate delegation"
      }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/accounts/:account_id/delegations/:id/revoke
  def revoke
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.revoke_delegation(@delegation)
    
    if result[:success]
      render json: { 
        delegation: delegation_json(@delegation.reload),
        message: "Delegation revoked successfully"
      }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to revoke delegation"
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/accounts/:account_id/delegations/available_permissions
  def available_permissions
    delegation_service = DelegationService.new(current_user, @account)
    role_id = params[:role_id]
    
    permissions = delegation_service.list_available_permissions_for_delegation(role_id: role_id)
    
    render json: {
      permissions: permissions.map { |permission| permission_json(permission) },
      role_id: role_id
    }
  end

  # POST /api/v1/accounts/:account_id/delegations/:id/permissions
  def add_permission
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.add_permission_to_delegation(
      delegation: @delegation,
      permission_id: params[:permission_id]
    )
    
    if result[:success]
      render json: { 
        delegation: delegation_json(@delegation.reload),
        message: "Permission added successfully"
      }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to add permission"
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/accounts/:account_id/delegations/:id/permissions/:permission_id
  def remove_permission
    delegation_service = DelegationService.new(current_user, @account)
    
    result = delegation_service.remove_permission_from_delegation(
      delegation: @delegation,
      permission_id: params[:permission_id]
    )
    
    if result[:success]
      render json: { 
        delegation: delegation_json(@delegation.reload),
        message: "Permission removed successfully"
      }
    else
      render json: { 
        errors: result[:errors],
        message: "Failed to remove permission"
      }, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = current_user.account
    
    # Allow admins to manage delegations for other accounts
    if params[:account_id] && current_user.admin?
      @account = Account.find(params[:account_id])
    end
  end

  def set_delegation
    @delegation = @account.account_delegations.find(params[:id])
  end

  def authorize_delegation_management!
    unless current_user.owner? || current_user.admin?
      render json: { error: "Insufficient permissions to manage delegations" }, status: :forbidden
    end
  end

  def authorize_delegation_view!
    unless current_user.owner? || current_user.admin? || @delegation.delegated_user == current_user
      render json: { error: "Insufficient permissions to view this delegation" }, status: :forbidden
    end
  end

  def delegation_params
    params.require(:delegation).permit(:delegated_user_email, :role_id, :expires_at, :notes, permission_ids: [])
  end

  def delegation_json(delegation)
    {
      id: delegation.id,
      account: {
        id: delegation.account.id,
        name: delegation.account.name,
        subdomain: delegation.account.subdomain
      },
      delegated_user: {
        id: delegation.delegated_user.id,
        email: delegation.delegated_user.email,
        full_name: delegation.delegated_user.full_name
      },
      delegated_by: {
        id: delegation.delegated_by.id,
        email: delegation.delegated_by.email,
        full_name: delegation.delegated_by.full_name
      },
      role: delegation.role ? {
        id: delegation.role.id,
        name: delegation.role.name,
        description: delegation.role.description
      } : nil,
      permissions: delegation.permissions.map { |permission| permission_json(permission) },
      permission_source: delegation.permission_source,
      permissions_summary: delegation.permissions_summary,
      available_permissions: delegation.available_permissions.map { |permission| permission_json(permission) },
      status: delegation.status,
      expires_at: delegation.expires_at,
      revoked_at: delegation.revoked_at,
      revoked_by: delegation.revoked_by ? {
        id: delegation.revoked_by.id,
        email: delegation.revoked_by.email,
        full_name: delegation.revoked_by.full_name
      } : nil,
      notes: delegation.notes,
      is_active: delegation.active?,
      is_expired: delegation.expired?,
      created_at: delegation.created_at,
      updated_at: delegation.updated_at
    }
  end

  def permission_json(permission)
    {
      id: permission.id,
      resource: permission.resource,
      action: permission.action,
      description: permission.description,
      key: "#{permission.resource}.#{permission.action}"
    }
  end
end