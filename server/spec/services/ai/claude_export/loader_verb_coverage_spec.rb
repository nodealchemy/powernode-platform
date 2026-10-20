# frozen_string_literal: true

require "rails_helper"

# A thin loader is useless if its `tools:` cannot call the verbs its own skills
# name: ToolSearch only searches inside the allowlist. So for EVERY roster
# agent, each verb named by a capability skill the agent can be assembled with
# (its domain ceiling; for a read-only role only the skills that are
# manifest.read_only, since assembly never hands it the others) must be
# callable from its loader: listed by exact name, or covered by the whole-server
# grant and not denied. The only verbs outside a granted role are the ones the
# loader denies BY NAME (ThinLoader::DENIED_ACTIONS: destroy-shaped or
# credential-minting steps the skill describes for an operator and an autonomous
# executor must report rather than perform).
RSpec.describe "thin loaders grant the verbs their skills name" do
  loader = Ai::ClaudeExport::ThinLoader

  # Every loaded owner's authored skills (core's, plus each loaded extension's).
  entries = begin
    dirs = [ Rails.root.join("db", "seeds", "capability_skills") ] +
           Powernode::ExtensionRegistry.all.values.map { |ext| ext[:engine].root.join("db", "seeds", "capability_skills") }
    dirs.select(&:directory?).flat_map { |dir| Ai::Skills::CapabilitySeeder.load_entries(dir) }
  end

  def frontmatter(content) = YAML.safe_load(content.split(/^---$/, 3)[1])
  def listed(content, key) = frontmatter(content)[key].to_s.split(",").map(&:strip)

  Ai::Agents::CanonicalRoster.slugs.each do |slug|
    describe slug do
      let(:spec) { Ai::Agents::CanonicalRoster.fetch(slug) }
      let(:content) { loader.render(slug) }
      let(:granted) { listed(content, "tools") }
      let(:denied) { listed(content, "disallowedTools") }
      let(:eligible) do
        entries.select { |e| spec[:domains].include?(e["domain"]) && (!spec[:role][:read_only] || e.dig("manifest", "read_only") == true) }
      end

      def loader = Ai::ClaudeExport::ThinLoader

      def callable?(verb)
        name = "#{loader::MCP_PREFIX}#{verb}"
        return true if granted.include?(name)

        granted.include?(loader::SERVER_GRANT) && !denied.include?(name)
      end

      it "can call every verb its eligible skills name, except the verbs the loader denies by name" do
        named = eligible.flat_map { |e| Array(e.dig("manifest", "verbs")) }.uniq
        expect(named).not_to be_empty
        uncallable = named.reject { |verb| callable?(verb) }

        expect(uncallable - loader::DENIED_ACTIONS).to be_empty, "named by skills but not callable from #{slug}'s loader: #{(uncallable - loader::DENIED_ACTIONS).inspect}"
      end

      it "lists only registered verbs in its explicit verb list" do
        registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)

        expect(spec[:role][:verbs] - registered).to be_empty
        expect(spec[:role][:verbs].uniq).to eq(spec[:role][:verbs])
        expect(spec[:role][:verbs] & loader::BOOTSTRAP_ACTIONS).to be_empty, "bootstrap verbs are already granted"
      end

      if Ai::Agents::CanonicalRoster.fetch(slug)[:role][:read_only]
        it "grants a read-only role no mutating verb except record_agent_execution" do
          registry = Ai::Tools::PlatformApiToolRegistry.all_tools
          mutating = (spec[:role][:verbs] + loader::BOOTSTRAP_ACTIONS).select do |verb|
            declaration = registry[verb]&.constantize&.declared_action(Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.fetch(verb, verb))
            declaration.nil? || declaration[:mutating]
          end

          expect(mutating).to eq([ "record_agent_execution" ])
          expect(granted).not_to include(loader::SERVER_GRANT, "Edit", "Write")
        end
      end
    end
  end
end
