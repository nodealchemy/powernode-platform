# frozen_string_literal: true

# ai_missions.ralph_loop_id <-> ai_ralph_loops.mission_id is a circular FK:
# Missions::SkillCompositionService writes the link in both directions when a
# mission spawns its ralph loop. With the default ON DELETE RESTRICT a linked
# pair was undeletable from either side — both destroy endpoints raised
# PG::ForeignKeyViolation, and Account's dependent: :destroy chain (loops
# declared before missions) failed account termination for any account
# holding a linked pair. Both columns are nullable and both associations are
# optional, so SET NULL ("the link evaporates with its partner") is the
# correct semantic and makes deletion order-free at the database level.
class NullifyCircularMissionRalphLoopForeignKeys < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :ai_missions, column: :ralph_loop_id
    add_foreign_key :ai_missions, :ai_ralph_loops, column: :ralph_loop_id, on_delete: :nullify

    remove_foreign_key :ai_ralph_loops, column: :mission_id
    add_foreign_key :ai_ralph_loops, :ai_missions, column: :mission_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :ai_missions, column: :ralph_loop_id
    add_foreign_key :ai_missions, :ai_ralph_loops, column: :ralph_loop_id

    remove_foreign_key :ai_ralph_loops, column: :mission_id
    add_foreign_key :ai_ralph_loops, :ai_missions, column: :mission_id
  end
end
