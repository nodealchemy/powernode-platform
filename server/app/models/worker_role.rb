# frozen_string_literal: true

class WorkerRole < ApplicationRecord
  # Table configuration
  self.table_name = 'worker_roles'
  
  # Associations
  belongs_to :worker
  belongs_to :role
  
  # Validations
  validates :worker_id, uniqueness: { scope: :role_id, message: 'already has this role' }
  
  # Callbacks
  after_create :log_role_grant
  after_destroy :log_role_revoke
  
  private
  
  def log_role_grant
    Rails.logger.info "Role #{role.name} granted to worker #{worker.name}"
  end
  
  def log_role_revoke
    Rails.logger.info "Role #{role.name} revoked from worker #{worker.name}"
  end
end