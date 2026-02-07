# frozen_string_literal: true

class AddTlsVerifyToDockerHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :devops_docker_hosts, :tls_verify, :boolean, default: true, null: false
  end
end
