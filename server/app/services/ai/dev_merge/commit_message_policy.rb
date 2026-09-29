# frozen_string_literal: true

module Ai
  module DevMerge
    # What caller-supplied text may reach a commit message written by
    # dev_merge_increment (Ai::Tools::DevMergeTool). Commit messages are
    # published: origin mirrors to a public host, so a message is as public as
    # the diff. Two things are refused outright:
    #
    #   * AI attribution — a "Co-Authored-By:" or "Generated with" line, or any
    #     trailer whose value names a model or an AI tool. The rule binds every
    #     executor class, so the pattern names the class, not one vendor.
    #   * a private extension's name — as resolved by
    #     Ai::DevMerge::ForbiddenNames (extensions/private/* on disk, the
    #     extension registry, and the operator's declaration). A private
    #     extension is absent from public clones, so naming one in a published
    #     message leaks it.
    #
    # The worker applies the same two rules to the message it GENERATES
    # (Devops::CommitMessageHygiene), with the names this class derives handed
    # to it in the job payload. This side REFUSES caller text before the call
    # parks, so no person is asked to approve a merge that could only be
    # refused on replay.
    class CommitMessagePolicy
      ATTRIBUTION_LINE = /^\s*(co-authored-by\s*:|generated\s+(with|by)\b)/i
      TRAILER = /^\s*[A-Za-z][A-Za-z0-9-]*\s*:\s*(?<value>.+)$/
      MODEL_WORDS = /\b(claude|anthropic|openai|chatgpt|gpt-?\d\w*|gemini|grok|codex|copilot|llama|mistral|fable|opus|sonnet|haiku)\b/i

      def self.violation(text, forbidden_names: ::Ai::DevMerge::ForbiddenNames.resolve.names)
        new(forbidden_names).violation(text)
      end

      def initialize(forbidden_names)
        @forbidden_names = Array(forbidden_names).map(&:to_s).reject(&:empty?)
      end

      # The reason `text` may not reach a commit message, or nil. The reason
      # never quotes the matched private name back: the refusal travels to the
      # caller, and echoing the name would be the leak the rule exists to stop.
      def violation(text)
        body = text.to_s
        return "it carries an AI attribution line" if body.each_line.any? { |line| attribution_line?(line) }
        return "it names a private extension" if names_private_extension?(body)

        nil
      end

      private

      def attribution_line?(line)
        return true if line.match?(ATTRIBUTION_LINE)

        trailer = line.match(TRAILER)
        !trailer.nil? && trailer[:value].match?(MODEL_WORDS)
      end

      def names_private_extension?(body)
        @forbidden_names.any? do |name|
          body.match?(/(?<![A-Za-z0-9])#{Regexp.escape(name)}(?![A-Za-z0-9])/i) ||
            body.match?(/\b#{Regexp.escape(pascal(name))}\b/)
        end
      end

      # Kebab slug -> PascalCase namespace, the derivation the core-purity hook
      # uses for `<Namespace>::`.
      def pascal(name)
        name.split("-").map(&:capitalize).join
      end
    end
  end
end
