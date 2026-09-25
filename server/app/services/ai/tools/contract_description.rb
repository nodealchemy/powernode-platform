# frozen_string_literal: true

module Ai
  module Tools
    # Composes an action's advertised description from the hand-written text
    # plus contract sentences generated from its declaration
    # (BaseTool.declare_action), so the contract a caller reads cannot drift
    # from what the code does:
    #
    #   gate          "May return pending: true …"      (gated_declaration?)
    #   human_only    "Runs only after a person …"
    #   destructive   "Destructive: …" (the MCP destructiveHint sense: MAY delete
    #                 or overwrite state, not necessarily irreversibly)
    #   limit:        "Returns at most N rows; not paginated."
    #   paginated:    the cursor / count / has_more contract
    #   returns:      "Returns <clause>."
    #   refuses:      "Refuses when <condition>; <condition>."
    #   see_also:     "For <purpose>, use <action>."
    #
    # The hand-written text keeps sentence 1 (the tools/list summary,
    # Mcp::ToolCatalog.summarize), so it must state purpose and object. A
    # generated sentence is skipped when the text already says the same thing,
    # so a description written before this existed is not doubled.
    #
    # BaseTool prepends this onto every subclass's singleton, so it wraps
    # whatever .action_definitions a tool defines. Composition runs once per
    # call chain even when a subclass inherits a parent's wrapped method.
    module ContractDescription
      GATED = "May return pending: true instead of running: the call parks until the approval it names is decided."
      HUMAN_ONLY = "Runs only after a person approves it in their own session; called from a tool it returns " \
                   "pending: true with requires_human_session."
      DESTRUCTIVE = "Destructive: it may delete or overwrite state."
      PAGINATED = "Paginated: returns count (all matches) and has_more; pass next_cursor as cursor for the next page."

      ALREADY_SAYS = {
        gated: /pending: ?true|approval[- ]gated|parks?\b/i,
        destructive: /irreversibl|cannot be undone|permanently|destructive/i,
        paginated: /next_cursor|has_more/i
      }.freeze

      def action_definitions
        return super if Thread.current[:ai_tools_composing_contract]

        begin
          Thread.current[:ai_tools_composing_contract] = true
          super.to_h do |registry_key, spec|
            [ registry_key, spec.merge(description: ContractDescription.compose(self, registry_key, spec[:description])) ]
          end
        ensure
          Thread.current[:ai_tools_composing_contract] = nil
        end
      end

      module_function

      def compose(tool_class, registry_key, text)
        declaration = declaration_for(tool_class, registry_key)
        return text if declaration.nil?

        sentences = contract_sentences(tool_class, declaration, text.to_s)
        return text if sentences.empty?

        [ text.to_s.strip.sub(/(?<![.!?])\z/, "."), *sentences ].join(" ")
      end

      def contract_sentences(tool_class, declaration, text)
        out = []
        if declaration[:human_only]
          out << HUMAN_ONLY unless text.match?(ALREADY_SAYS[:gated])
        elsif tool_class.gated_declaration?(declaration)
          out << GATED unless text.match?(ALREADY_SAYS[:gated])
        end
        out << DESTRUCTIVE if declaration[:destructive] && !text.match?(ALREADY_SAYS[:destructive])
        if declaration[:paginated]
          out << PAGINATED unless text.match?(ALREADY_SAYS[:paginated])
        elsif declaration[:limit]
          out << "Returns at most #{declaration[:limit]} rows; not paginated."
        end
        out << "Returns #{declaration[:returns].to_s.sub(/\.\z/, '')}." if declaration[:returns].present?
        refuses = Array(declaration[:refuses]).map { |c| c.to_s.sub(/\.\z/, "") }.reject(&:empty?)
        out << "Refuses when #{refuses.join('; ')}." if refuses.any?
        (declaration[:see_also] || {}).each { |action, purpose| out << "For #{purpose.to_s.sub(/\.\z/, '')}, use #{action}." }
        out
      end

      # The declaration BaseTool#execute would dispatch on: an aliased
      # registry key first, then the key itself, then a single-action tool's
      # own name.
      def declaration_for(tool_class, registry_key)
        return nil unless tool_class.respond_to?(:declared_action)

        aliased = ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(registry_key, registry_key)
        tool_class.declared_action(aliased) || tool_class.declared_action(registry_key)
      end
    end
  end
end
