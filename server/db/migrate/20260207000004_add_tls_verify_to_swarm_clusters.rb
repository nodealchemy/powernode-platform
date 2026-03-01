# frozen_string_literal: true

class AddTlsVerifyToSwarmClusters < ActiveRecord::Migration[8.0]
  def change
    add_column :devops_swarm_clusters, :tls_verify, :boolean, default: true, null: false
  end
end
