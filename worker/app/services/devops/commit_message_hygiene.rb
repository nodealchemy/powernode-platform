# frozen_string_literal: true

module Devops
  # The two rules a commit message written by the dev-merge job must satisfy
  # (Git::DevMergeIncrementJob). Commit messages are published through a
  # public mirror, so a message is as public as the diff. Both are REFUSALS,
  # never rewrites: there is no safe edit of a message that would have
  # published either, so the operation stops and says why.
  #
  #   * No AI attribution: a "Co-Authored-By:" or "Generated with" line, or a
  #     trailer whose value names a model or an AI tool. The server refuses
  #     the same in caller text (Ai::DevMerge::CommitMessagePolicy); this
  #     side also covers text the job takes from the submodule's own commit.
  #   * No private extension name. The names arrive in the job payload,
  #     derived on the server from extensions/private/* by the same rule the
  #     core-purity gate uses.
  module CommitMessageHygiene
    ATTRIBUTION_LINE = /^\s*(co-authored-by\s*:|generated\s+(with|by)\b)/i
    TRAILER = /^\s*[A-Za-z][A-Za-z0-9-]*\s*:\s*(?<value>.+)$/
    MODEL_WORDS = /\b(claude|anthropic|openai|chatgpt|gpt-?\d\w*|gemini|grok|codex|copilot|llama|mistral|fable|opus|sonnet|haiku)\b/i

    class Refused < StandardError; end

    module_function

    # "chore(<scope>): bump extension pointer to <short> (<summary>)", the
    # shape the parent repository's pointer bumps already use. `summary` is
    # the caller's (already vetted by the server) or the submodule commit's
    # subject. It is checked as its own line as well as inside the message,
    # so an attribution trailer cannot hide inside the parenthetical.
    def pointer_bump_message(scope:, short_sha:, summary:, forbidden_names:)
      summary = summary.to_s.strip
      raise Refused, "the summary for the generated message is more than one line" if summary.include?("\n")

      message = "chore(#{scope}): bump extension pointer to #{short_sha}"
      message += " (#{summary})" unless summary.empty?

      if attribution_line?(summary) || message.lines.any? { |line| attribution_line?(line) }
        raise Refused, "the generated message would carry an AI attribution line"
      end
      raise Refused, "the generated message would name a private extension" if names_private?(message, forbidden_names)

      message
    end

    def attribution_line?(line)
      return true if line.match?(ATTRIBUTION_LINE)

      trailer = line.match(TRAILER)
      !trailer.nil? && trailer[:value].match?(MODEL_WORDS)
    end

    # The slug as a word in any case, and its PascalCase namespace form
    # (kebab slug -> PascalCase, the core-purity hook's derivation).
    def names_private?(text, forbidden_names)
      Array(forbidden_names).map(&:to_s).reject(&:empty?).any? do |name|
        pascal = name.split("-").map(&:capitalize).join
        text.match?(/(?<![A-Za-z0-9])#{Regexp.escape(name)}(?![A-Za-z0-9])/i) ||
          text.match?(/\b#{Regexp.escape(pascal)}\b/)
      end
    end
  end
end
