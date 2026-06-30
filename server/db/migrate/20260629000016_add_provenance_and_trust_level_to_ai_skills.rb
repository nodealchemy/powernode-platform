# frozen_string_literal: true

# G6 (Loop Engineering Parity): give ai_skills a provenance / trust signal.
#
# Skill content (system_prompt, command descriptions, recipe steps) is operator-
# or community-supplied and was persisted/attached verbatim with no trust signal.
# Add two string columns mirroring the platform's other origin/trust precedents
# (knowledge provenance, agent trust tiers):
#
#   provenance  — where the skill came from: internal | community | imported
#   trust_level — content-scan verdict: trusted | review | untrusted
#
# Platform-created skills default to internal/trusted; the content scanner
# (Ai::Skill::ContentScanService, wired through SkillService) downgrades the
# trust_level and the attach path gates untrusted external content.
class AddProvenanceAndTrustLevelToAiSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_skills, :provenance, :string, null: false, default: "internal"
    add_column :ai_skills, :trust_level, :string, null: false, default: "trusted"

    add_index :ai_skills, :provenance, name: "index_ai_skills_on_provenance"
    add_index :ai_skills, :trust_level, name: "index_ai_skills_on_trust_level"
  end
end
