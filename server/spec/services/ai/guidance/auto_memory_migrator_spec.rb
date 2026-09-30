# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe Ai::Guidance::AutoMemoryMigrator do
  include_context "auto memory fixtures"

  let(:account) { create(:account) }

  def migrator(apply: false, include_sensitive: false, acct: account, **opts)
    described_class.new(
      dir: memory_dir, account: acct, apply: apply, include_sensitive: include_sensitive,
      identifiers_path: identifiers_file, private_names: synthetic_private_names,
      manifest_dir: manifest_dir, **opts
    )
  end

  def entry_for(slug)
    Ai::SharedKnowledge.where(account: account).where("provenance->>'guidance_key' = ?", "memory:#{slug}").first
  end

  def entries(report)
    report.entries.index_by(&:slug)
  end

  before do
    write_memory("plain-note", body: "Nothing special.")
    write_memory("ident-note", body: "Host is #{identifier_marker} here.")
    write_memory("sensitive-note", body: "How to use #{sensitive_marker} access.")
    write_memory("private-note", body: "Relates to #{private_marker} internals.")
    write_memory("big-note", body: "x" * 9000)
  end

  describe "triage sets (synthetic fixtures)" do
    subject(:report) { migrator.call }

    it "(a) flags content matching the deployment-identifiers list" do
      expect(report.by_set(:identifiers)).to eq(%w[ident-note])
    end

    it "(b) flags break-glass / security-gap content" do
      expect(report.by_set(:sensitive)).to eq(%w[sensitive-note])
    end

    it "(b) matches every pattern in the explicit list" do
      samples = {
        "break_glass" => "break glass account", "security_gap" => "a security gap", "unauthenticated" => "unauthenticated port",
        "bypass" => "an auth bypass", "exploit" => "an exploit path", "credential_material" => "the api key",
        "cve" => "CVE-2026-12345", "privilege_escalation" => "self-regrant path",
        "secrets" => "rotate the secrets", "credentials" => "credential handling", "token" => "the vault token"
      }
      expect(described_class::SENSITIVE_PATTERNS.keys).to match_array(samples.keys)
      samples.each { |label, text| expect(text).to match(described_class::SENSITIVE_PATTERNS.fetch(label)) }
      # each alternative of the token / mnemonic / password entries
      [ "deploy-token", "token: abc", "access token", "a seed phrase", "the mnemonic", "the password" ].each do |text|
        expect(text).to match(Regexp.union(described_class::SENSITIVE_PATTERNS.values))
      end
      expect("A harmless note about rendering.").not_to match(Regexp.union(described_class::SENSITIVE_PATTERNS.values))
    end

    it "(c) flags a private-extension name from the injected (runtime-derived) list" do
      expect(report.by_set(:private_names)).to eq(%w[private-note])
    end

    it "(c) derives its names from extensions/private when none are injected" do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob).with(Rails.root.parent.join("extensions", "private", "*"))
                                  .and_return([ "/nowhere/extensions/private/quokkaworks" ])
      allow(File).to receive(:directory?).and_call_original
      allow(File).to receive(:directory?).with("/nowhere/extensions/private/quokkaworks").and_return(true)

      derived = described_class.new(dir: memory_dir, identifiers_path: identifiers_file, manifest_dir: manifest_dir).call

      expect(derived.by_set(:private_names)).to eq(%w[private-note])
    end

    it "(d) flags content over the 8000-character embedding limit only" do
      expect(described_class::EMBEDDING_LIMIT).to eq(8000)
      expect(report.by_set(:oversize)).to eq(%w[big-note])
    end

    it "leaves an unflagged note in no set" do
      expect(entries(report).fetch("plain-note").sets).to be_empty
    end
  end

  describe "the no-echo rule" do
    it "never puts matched text in the report lines, the manifest or an error" do
      report = migrator.call
      surfaces = report.lines.join("\n") + File.read(report.manifest_path)

      [ identifier_marker, private_marker, sensitive_marker ].each do |marker|
        expect(surfaces).not_to include(marker)
      end
      expect(surfaces).to include("ident-note", "sensitive-note", "private-note")
    end

    it "does not echo an identifier pattern that Ruby cannot compile" do
      File.write(identifiers_file, "ZQID-[0-9]+\nBROKEN(\n")
      write_memory("literal-note", body: "mentions BROKEN( literally")

      report = migrator.call

      expect(report.by_set(:identifiers)).to include("literal-note")
      expect(report.lines.join).not_to include("BROKEN")
    end

    it "does not echo the matched text when APPLY refuses" do
      File.write(identifiers_file, "# nothing\n")

      expect { migrator(apply: true).call }.to raise_error(described_class::Error) { |e| expect(e.message).not_to include(identifier_marker) }
    end
  end

  describe "dry run (the default)" do
    it "writes nothing to the database, not even a graph node" do
      write_memory("linker", body: "See [[plain-note]].")

      expect { migrator.call }.not_to change {
        [ Ai::SharedKnowledge.count, Ai::KnowledgeGraphNode.count, Ai::KnowledgeGraphEdge.count ]
      }
    end

    it "needs no account" do
      report = migrator(acct: nil).call

      expect(report.mode).to eq(:dry_run)
      expect(entries(report).fetch("plain-note").action).to eq(:planned)
    end

    it "writes a manifest marked planned, with no ids, to a different file than apply uses" do
      report = migrator.call

      expect(File.basename(report.manifest_path)).to eq(described_class::DRY_RUN_MANIFEST_FILE)
      manifest = JSON.parse(File.read(report.manifest_path))
      expect(manifest).to include("mode" => "dry_run")
      expect(manifest["entries"]["plain-note"]).to include("status" => "planned", "knowledge_id" => nil)
      expect(manifest["entries"]["ident-note"]).to include("status" => "skipped", "sets" => [ "identifiers" ])
    end

    it "does not clobber an apply manifest" do
      migrator(apply: true).call
      apply_manifest = File.join(manifest_dir, described_class::MANIFEST_FILE)
      before = File.read(apply_manifest)

      migrator.call

      expect(File.read(apply_manifest)).to eq(before)
    end

    it "the default manifest directory is gitignored" do
      default = described_class::MANIFEST_DIR
      path = Rails.root.parent.join(*default, described_class::MANIFEST_FILE).to_s

      _out, status = Open3.capture2e("git", "-C", Rails.root.parent.to_s, "check-ignore", "-q", path)

      expect(status.exitstatus).to eq(0)
    end
  end

  describe "APPLY" do
    it "requires an account" do
      expect { migrator(apply: true, acct: nil) }.to raise_error(described_class::Error, /requires an account/)
    end

    it "applies plain and oversize notes; skips identifiers, private names and (by default) sensitive" do
      report = migrator(apply: true).call

      expect(entries(report).transform_values(&:action)).to eq(
        "plain-note" => :created, "big-note" => :created,
        "ident-note" => :skipped, "private-note" => :skipped, "sensitive-note" => :skipped
      )
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(2)
      expect(entry_for("ident-note")).to be_nil
      expect(entry_for("private-note")).to be_nil
      expect(entry_for("sensitive-note")).to be_nil
    end

    it "applies set (b) only with INCLUDE_SENSITIVE" do
      report = migrator(apply: true, include_sensitive: true).call

      expect(entries(report).fetch("sensitive-note").action).to eq(:created)
      expect(entry_for("sensitive-note").access_level).to eq("account")
    end

    it "INCLUDE_SENSITIVE does not release sets (a) or (c)" do
      report = migrator(apply: true, include_sensitive: true).call

      expect(entries(report).fetch("ident-note").action).to eq(:skipped)
      expect(entries(report).fetch("private-note").action).to eq(:skipped)
    end

    it "skips a note in several sets when ANY skipping rule fires" do
      write_memory("both", body: "#{sensitive_marker} and #{identifier_marker}")

      report = migrator(apply: true, include_sensitive: true).call

      expect(entries(report).fetch("both")).to have_attributes(action: :skipped, sets: %i[identifiers sensitive])
    end

    it "stores the oversize note in full (only the embedding truncates)" do
      migrator(apply: true).call

      expect(entry_for("big-note").content.length).to be > described_class::EMBEDDING_LIMIT
    end

    it "refuses when the identifiers list is missing or empty, unless explicitly allowed" do
      File.write(identifiers_file, "# nothing\n")

      expect { migrator(apply: true).call }.to raise_error(described_class::Error, /identifiers list is missing or empty/)
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)
      expect(migrator(apply: true, require_identifiers: false).call.mode).to eq(:apply)
    end

    it "is idempotent: a re-run updates by guidance_key and never duplicates" do
      migrator(apply: true).call
      ids = Ai::SharedKnowledge.where(account: account).order(:id).pluck(:id)
      write_memory("plain-note", body: "Edited.")

      report = migrator(apply: true).call

      expect(entries(report).fetch("plain-note").action).to eq(:updated)
      expect(entries(report).fetch("big-note").action).to eq(:unchanged)
      expect(Ai::SharedKnowledge.where(account: account).order(:id).pluck(:id)).to eq(ids)
    end

    it "writes a slug -> knowledge-id manifest" do
      report = migrator(apply: true).call

      manifest = JSON.parse(File.read(report.manifest_path))
      expect(File.basename(report.manifest_path)).to eq(described_class::MANIFEST_FILE)
      expect(manifest).to include("mode" => "apply", "account_id" => account.id)
      expect(manifest["entries"]["plain-note"]).to include("status" => "created", "knowledge_id" => entry_for("plain-note").id)
      expect(manifest["entries"]["ident-note"]).to include("status" => "skipped", "knowledge_id" => nil)
    end
  end

  describe "graph edges from [[slug]] links" do
    before do
      write_memory("src-a", body: "Related: [[plain-note]] and [[ident-note]] and [[nonexistent]].")
    end

    it "creates related_to edges between applied notes only, in APPLY mode" do
      report = migrator(apply: true).call

      edges = account.ai_knowledge_graph_edges.includes(:source_node, :target_node)
      expect(edges.map { |e| [ e.source_node.name, e.target_node.name, e.relation_type ] })
        .to eq([ [ "memory:src-a", "memory:plain-note", "related_to" ] ])
      expect(report).to have_attributes(edges_created: 1, edges_existing: 0)
    end

    it "never links to a skipped note, so an edge cannot reveal one" do
      migrator(apply: true).call

      expect(account.ai_knowledge_graph_nodes.pluck(:name)).not_to include("memory:ident-note", "memory:nonexistent")
    end

    it "creates no edges on a dry run" do
      expect { migrator.call }.not_to change(Ai::KnowledgeGraphEdge, :count)
    end

    it "is idempotent: a re-run creates no second edge or node" do
      migrator(apply: true).call

      report = nil
      expect { report = migrator(apply: true).call }
        .not_to change { [ Ai::KnowledgeGraphEdge.count, Ai::KnowledgeGraphNode.count ] }
      expect(report).to have_attributes(edges_created: 0, edges_existing: 1)
    end

    it "uses GraphService#create_edge" do
      graph = Ai::KnowledgeGraph::GraphService.new(account)
      allow(graph).to receive(:create_edge).and_call_original

      migrator(apply: true, graph_service: graph).call

      expect(graph).to have_received(:create_edge).with(hash_including(relation_type: "related_to")).once
    end
  end

  describe "slug / filename triage (M1)" do
    # name and description are innocuous: ONLY the filename can match.
    def write_named_only(slug)
      write_memory(slug, name: "Innocuous", description: "Plain description")
    end

    it "skips a note whose FILENAME alone matches identifiers, private names or a sensitive pattern" do
      write_named_only("host-#{identifier_marker}-notes")
      write_named_only("#{private_marker}-internals")
      write_named_only("breakglass-runbook")

      report = migrator(apply: true, include_sensitive: false).call
      by = entries(report)

      expect(by.values.select { |e| (e.sets - %i[oversize]).any? }.map(&:action).uniq).to eq(%i[skipped])
      expect(report.by_set(:identifiers)).to include(a_string_matching(/\Anote#\h{8}\z/))
      expect(Ai::SharedKnowledge.where(account: account).pluck(:title)).not_to include(
        a_string_including(identifier_marker), a_string_including(private_marker), a_string_including("breakglass")
      )
    end

    it "sends a filename-only sensitive match through the INCLUDE_SENSITIVE gate" do
      write_named_only("breakglass-runbook")

      expect(entries(migrator(apply: true).call).values.find { |e| e.sets == %i[sensitive] && e.ref.start_with?("note#") }.action)
        .to eq(:skipped)
      report = migrator(apply: true, include_sensitive: true).call
      expect(entry_for("breakglass-runbook")).to be_present
      expect(entries(report).fetch("breakglass-runbook").action).to eq(:created)
    end

    it "never echoes a matching slug in the report lines or the manifest; the reference is stable" do
      write_named_only("host-#{identifier_marker}-notes")

      first = migrator.call
      second = migrator.call
      surfaces = first.lines.join("\n") + File.read(first.manifest_path)

      expect(surfaces).not_to include(identifier_marker)
      expect(first.by_set(:identifiers)).to include(second.by_set(:identifiers).find { |r| r.start_with?("note#") })
      expect(JSON.parse(File.read(first.manifest_path))["entries"].keys).to include(*first.by_set(:identifiers))
    end

    it "keeps the real slug for a clean note" do
      expect(entries(migrator.call).fetch("plain-note").ref).to eq("plain-note")
    end
  end

  describe "private-name list fails closed (M2)" do
    it "refuses APPLY when no private names can be derived, unless explicitly allowed" do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob).with(Rails.root.parent.join("extensions", "private", "*")).and_return([])
      blind = described_class.new(dir: memory_dir, account: account, apply: true, identifiers_path: identifiers_file,
                                  manifest_dir: manifest_dir)

      expect { blind.call }.to raise_error(described_class::Error, /no private-extension names could be derived/)
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)

      allowed = described_class.new(dir: memory_dir, account: account, apply: true, identifiers_path: identifiers_file,
                                    manifest_dir: manifest_dir, require_private_list: false)
      expect(allowed.call.mode).to eq(:apply)
    end

    it "says the check is disabled, never 0, when the list is empty (dry run)" do
      report = migrator(private_names: []).call

      expect(report.lines.join("\n")).to include("(c) private names: check disabled", "private-extension names loaded: 0")
      expect(report.lines).not_to include(a_string_matching(/\(c\) private names: 0/))
    end

    it "says the identifiers check is disabled when the list is empty" do
      File.write(identifiers_file, "# nothing\n")

      expect(migrator.call.lines.join("\n")).to include("(a) identifiers: check disabled")
    end
  end

  describe "grep word anchors in the identifiers list (M3)" do
    it "translates \\< and \\> to word boundaries so the line still matches" do
      File.write(identifiers_file, "\\<ZQWORD-[0-9]+\\>\n[[:<:]]ZQOTHER[[:>:]]\n")
      write_memory("anchored", body: "see zqword-77 now")
      write_memory("bracketed", body: "the zqother thing")
      write_memory("embedded", body: "xzqword-77y is not a word")

      report = migrator.call

      expect(report.by_set(:identifiers)).to contain_exactly("anchored", "bracketed")
    end

    it "leaves an escaped backslash before < alone" do
      File.write(identifiers_file, "ZQ\\\\<Y\n")
      write_memory("escaped", body: "ZQ\\<Y")

      expect(migrator.call.by_set(:identifiers)).to eq(%w[escaped])
    end
  end

  describe "symlinks" do
    it "does not apply a symlinked note and counts it in the report" do
      write_memory("outside", dir: scratch_dir)
      File.symlink(File.join(scratch_dir, "outside.md"), File.join(memory_dir, "linked.md"))

      report = migrator(apply: true).call

      expect(report.symlinks_skipped).to eq(1)
      expect(report.lines.first).to include("symlinks_skipped=1")
      expect(entry_for("linked")).to be_nil
    end
  end

  describe "a failure mid-APPLY" do
    it "writes a partial manifest of what was already written, then re-raises" do
      write_memory("src-a", body: "Related: [[plain-note]].")
      graph = Ai::KnowledgeGraph::GraphService.new(account)
      allow(graph).to receive(:create_edge).and_raise(Ai::KnowledgeGraph::GraphServiceError, "boom")

      expect { migrator(apply: true, graph_service: graph).call }.to raise_error(Ai::KnowledgeGraph::GraphServiceError)

      manifest = JSON.parse(File.read(File.join(manifest_dir, described_class::MANIFEST_FILE)))
      expect(manifest).to include("partial" => true, "error_class" => "Ai::KnowledgeGraph::GraphServiceError")
      expect(manifest["entries"]["plain-note"]).to include("status" => "created", "knowledge_id" => entry_for("plain-note").id)
      expect(manifest["entries"]["ident-note"]["status"]).to eq("skipped")
    end
  end
end
