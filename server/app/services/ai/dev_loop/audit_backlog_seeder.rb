# frozen_string_literal: true

module Ai
  module DevLoop
    # Parses a verified-findings audit backlog (## Fx-yy — S2 [M] kind (CONFIRMED)
    # sections with **File:/Claim:/Evidence:/Repro:/Fix:** fields) into a Ralph
    # Loop task queue consumable through Ai::Tools::DevLoopTool. Deterministic —
    # no LLM involved. Idempotent: existing task_keys are left untouched.
    class AuditBacklogSeeder
      LOOP_NAME = "dev-audit-fleet-substrate"
      DEFAULT_SEVERITIES = %w[S2 S3].freeze

      # Findings that are architecture decisions, not loop fodder — seeded as
      # execution_type "human" so executors never pull them but operators see them.
      HUMAN_DECISION_KEYS = %w[F3-01].freeze

      SEVERITY_PRIORITY = { "S1" => 30, "S2" => 20, "S3" => 10, "S4" => 5 }.freeze
      SIZE_BONUS = { "XS" => 3, "S" => 2, "M" => 1, "L" => 0 }.freeze

      HEADING = /^## (F\d+-\d+) — (S\d) \[(XS|S|M|L)\] ([a-z_-]+) \((\w+)\)\s*$/

      GUARDRAILS = [
        "One task per iteration — finish or report before pulling the next",
        "Consult model-agnostic guidance BEFORE changing code: run search_knowledge with tag guidance-* and honor the applicable safety/governance/convention rules — the SessionStart digest is Claude-only, so non-Claude executors MUST query",
        "Write a failing spec reproducing the finding BEFORE the fix; confirm it is red",
        "Search before changing — verify the claim against current code first (findings may have rotted)",
        "No placeholder implementations",
        "After 3 failed attempts on the same task, report outcome=failed and stop",
        "Commit only to the loop branch — never develop/master, never push"
      ].freeze

      Result = Struct.new(:ralph_loop, :created, :skipped, :total_parsed, keyword_init: true)

      def initialize(account:, path:, severities: DEFAULT_SEVERITIES)
        @account = account
        @path = path
        @severities = severities
      end

      def call
        findings = parse_findings
        ralph_loop = find_or_create_loop

        created = 0
        skipped = 0
        findings.each do |finding|
          next unless seedable?(finding)

          task = ralph_loop.ralph_tasks.find_or_initialize_by(task_key: finding[:key])
          if task.persisted?
            skipped += 1
            next
          end

          task.assign_attributes(task_attributes(finding))
          task.save!
          created += 1
        end

        Result.new(ralph_loop: ralph_loop, created: created, skipped: skipped, total_parsed: findings.size)
      end

      private

      attr_reader :account, :path, :severities

      def parse_findings
        content = File.read(path)
        content.split(/^(?=## F\d+-\d+ — )/).filter_map do |section|
          heading = section.lines.first&.match(HEADING)
          next unless heading

          {
            key: heading[1],
            severity: heading[2],
            size: heading[3],
            kind: heading[4],
            status: heading[5],
            file: field(section, "File"),
            claim: field(section, "Claim"),
            evidence: field(section, "Evidence"),
            repro: field(section, "Repro"),
            fix: field(section, "Fix")
          }
        end
      end

      def field(section, name)
        section[/^\*\*#{name}:\*\* (.*)$/, 1]
      end

      def seedable?(finding)
        return false unless finding[:status] == "CONFIRMED"

        severities.include?(finding[:severity]) || HUMAN_DECISION_KEYS.include?(finding[:key])
      end

      def find_or_create_loop
        account.ai_ralph_loops.find_or_create_by!(name: LOOP_NAME) do |l|
          l.description = "Burn-down of the #{File.basename(path, '.md')} verified findings " \
                          "(#{severities.join('/')} + human-decision items). Executed via dev_next_task/dev_complete_task."
          l.ai_tool = "claude_code"
          l.scheduling_mode = "manual"
          l.status = "pending"
          l.branch = "dev-loop/dev-audit"
          l.max_iterations = 200
          l.configuration = {
            "workload" => "audit-burn-down",
            "loop_spec_path" => ".claude/loops/dev-audit/PROMPT.md",
            "source_document" => path.to_s,
            "guardrails" => GUARDRAILS
          }
        end
      end

      def task_attributes(finding)
        human = HUMAN_DECISION_KEYS.include?(finding[:key])
        {
          description: finding[:claim],
          acceptance_criteria: acceptance_criteria(finding, human: human),
          priority: SEVERITY_PRIORITY.fetch(finding[:severity], 0) + SIZE_BONUS.fetch(finding[:size], 0),
          execution_type: human ? "human" : "agent",
          metadata: {
            "severity" => finding[:severity],
            "size" => finding[:size],
            "kind" => finding[:kind],
            "audit_status" => finding[:status],
            "files" => finding[:file],
            "repro" => finding[:repro],
            "evidence" => finding[:evidence]&.truncate(2000),
            "source" => File.basename(path.to_s)
          }.tap { |m| m["executor_hint"] = "claude_code" unless human }
        }
      end

      def acceptance_criteria(finding, human:)
        if human
          "Operator decision required — not executable by loop agents. #{finding[:fix]}"
        else
          "Write a failing spec reproducing the finding FIRST and confirm it is red. Then: #{finding[:fix]}"
        end
      end
    end
  end
end
