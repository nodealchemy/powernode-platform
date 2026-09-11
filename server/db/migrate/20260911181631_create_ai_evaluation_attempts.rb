# frozen_string_literal: true

# D5 review F-D5-1 — the judge's daily cap counts ATTEMPTS: one row per paid
# judge call, written BEFORE the call. It used to count ai_evaluation_results
# rows, and a degraded verdict (the provider answered, but not with a usable
# score) writes none. With the cap at 1, five degraded verdicts made five paid
# calls, wrote no row, and never tripped the cap.
#
# account_id is NOT NULL: an attempt is always spent against an account.
# `index: false` on the reference, because the one index below leads with
# account_id and is also the cap's only read. execution_id carries no foreign
# key, the same as ai_evaluation_results.execution_id.
class CreateAiEvaluationAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_evaluation_attempts, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, index: false,
                             foreign_key: { on_delete: :cascade }
      t.uuid :execution_id, null: false
      t.uuid :task_id
      # pending | evaluated | not_measured, validated on the model.
      t.string :outcome, null: false, default: "pending"
      t.string :reason

      t.timestamps
    end

    add_index :ai_evaluation_attempts, %i[account_id created_at],
              name: "index_ai_evaluation_attempts_on_account_and_created_at"
  end
end
