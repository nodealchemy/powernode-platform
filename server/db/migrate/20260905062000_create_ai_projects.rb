# frozen_string_literal: true

# APO increment `app-4-project-noun` — the platform gets a noun for "project".
#
# Until now a project WAS an infrastructure `Ai::Mission`: the per-project
# metric time series `belongs_to :mission`, the scaling window lived in
# `mission.configuration["watch_policies"]`, and the provisioning brief created
# a bare mission and nothing else. Missions END (they carry
# completed/failed/cancelled and a completed_at); projects do not. So the thing
# that outlives its work had the lifecycle of the work, and nothing bound
# template + repository + owning team + budget/bounds + SLO targets together.
#
# TEMPLATE REFERENCE — WHY POLYMORPHIC. The node template a project is composed
# from is owned by an EXTENSION. Core never depends on an extension, so this
# migration cannot declare a foreign key onto the extension's templates table
# and the model cannot name its class. `template_type` + `template_id` is the
# generic seam: the type is DATA written by whoever attaches the template, so
# core carries the pointer without knowing what it points at, and an
# installation without that extension simply has NULLs here.
#
# `ai_missions.ai_project_id` is NULLABLE and stays that way. Every mission that
# exists today has no project; making the column required would break the whole
# installed base at once. The project is additive.
class CreateAiProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_projects, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, null: false, type: :uuid, foreign_key: false

      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active" # active | paused | archived
      t.text :description

      # The git repository the project is built from — the head of the
      # "a git URL becomes something running" chain.
      t.uuid :repository_id
      # Owning agent team (Ai::AgentTeam).
      t.uuid :ai_agent_team_id
      t.uuid :created_by_id

      # Generic template pointer — see the header. NOT a foreign key.
      t.string :template_type
      t.uuid   :template_id

      # Declarations read by the bounds / utilization ladders, in the SAME
      # shape a mission declares them (`watch_policies`, `slo_targets`), plus
      # the project's budget envelope. One shape means the ladder reads the
      # project rung with the extractor it already had, instead of a second
      # spelling that is free to drift.
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ai_projects, %i[account_id slug], unique: true, name: "index_ai_projects_on_account_and_slug"
    add_index :ai_projects, %i[account_id status]
    add_index :ai_projects, :repository_id
    add_index :ai_projects, :ai_agent_team_id
    add_index :ai_projects, %i[template_type template_id]

    add_column :ai_missions, :ai_project_id, :uuid
    add_index  :ai_missions, :ai_project_id
  end
end
