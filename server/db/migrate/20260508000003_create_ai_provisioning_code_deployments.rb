# frozen_string_literal: true

# AI-Driven Provisioning M3 — "Run My Code" deployment ledger.
#
# Each row tracks one repository deployment from a provisioning mission
# onto a specific NodeInstance: the executor (`DeployAppCodeExecutor`)
# inserts a row in `pending`, drives it through `cloning|installing|
# starting`, and lands on `running` (success) or `failed` (with
# last_error captured for the operator).
#
# `commit_sha` and `public_url` are populated by Slice A's
# `System::CodeDeployService` once the SSH+systemd deploy lands.
#
# Reference: how-can-we-provide-flickering-candy plan, M3 slice 2.
class CreateAiProvisioningCodeDeployments < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_provisioning_code_deployments, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :mission,
                   type: :uuid,
                   null: false,
                   foreign_key: { to_table: :ai_missions }
      t.references :node_instance,
                   type: :uuid,
                   null: false,
                   foreign_key: { to_table: :system_node_instances }
      t.string :repo_url, null: false
      t.string :branch, null: false, default: "main"
      t.string :start_command
      t.string :commit_sha
      t.string :public_url
      # pending|cloning|installing|starting|running|failed|rolled_back
      t.string :status, null: false, default: "pending"
      t.text :last_error
      t.datetime :deployed_at
      t.timestamps
    end
  end
end
