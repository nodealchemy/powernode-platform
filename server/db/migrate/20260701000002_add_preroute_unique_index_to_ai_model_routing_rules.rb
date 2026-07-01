# frozen_string_literal: true

# Enforce one pre-route rule per (account, deterministic name) for the Fable
# refusal promotion service, so concurrent record-time promotions can't duplicate.
# PARTIAL index (name LIKE 'fable-refusal-preroute:%') so it only constrains the
# framework's own rules and can never collide with pre-existing routing-rule names.
class AddPrerouteUniqueIndexToAiModelRoutingRules < ActiveRecord::Migration[8.1]
  def change
    add_index :ai_model_routing_rules, %i[account_id name],
              unique: true,
              name: "idx_ai_routing_rules_preroute_name_uniq",
              where: "name LIKE 'fable-refusal-preroute:%'"
  end
end
