# frozen_string_literal: true

module Devops
  # The two rules a commit message written by the dev-merge job must satisfy
  # (Git::DevMergeIncrementJob). Commit messages are published through a
  # public mirror, so a message is as public as the diff.
  #
  #   * No AI attribution. A "Co-Authored-By:" or "Generated with" line, or a
  #     trailer whose value names a model or an AI tool, is STRIPPED from
  #     generated text. (The server REFUSES such text when a caller supplies
  #     it: Ai::DevMerge::CommitMessagePolicy.)
  #   * No private extension name. The names arrive in the job payload,
  #     derived on the server from extensions/private/* by the same rule the
  #     core-purity gate uses. A generated message that names one is refused,
  #     never rewritten: there is no safe paraphrase of a name that must not
  #     appear.
  module CommitMessageHygiene
    ATTRIBUTION_LINE = /^\s*(co-authored-by\s*:|generated\s+(with|by)\b)/i
    TRAILER = /^\s*[A-Za-z][A-Za-z0-9-]*\s*:\s*(?<value>.+)$/
    MODEL_WORDS = /\b(claude|anthropic|openai|chatgpt|gpt-?\d\w*|gemini|grok|codex|copilot|llama|mistral|fable|opus|sonnet|haiku)\b/i

    class Refused < StandardError; end

    module_function

    # "chore(<scope>): bump extension pointer to <short> (<summary>)", the
    # shape the parent repository's pointer bumps already use. `summary` is
    # the caller's (already vetted by the server) or the submodule commit's
    # subject; attribution is stripped from it, and an empty summary drops the
    # parenthetical.
    def pointer_bump_message(scope:, short_sha:, summary:, forbidden_names:)
      cleaned = strip_attribution(summary.to_s.lines.first.to_s).strip
      message = "chore(#{scope}): bump extension pointer to #{short_sha}"
      message += " (#{cleaned})" unless cleaned.empty?
      message = strip_attribution(message).strip

      raise Refused, "the generated message names a private extension" if names_private?(message, forbidden_names)
      raise Refused, "the generated message is empty" if message.empty?

      message
    end

    def strip_attribution(text)
      text.to_s.lines.reject { |line| attribution_line?(line) }.join
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
