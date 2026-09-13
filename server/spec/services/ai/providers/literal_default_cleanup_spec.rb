# frozen_string_literal: true

require "rails_helper"
require "rake"

# Campaign 01a08c9b, E3b — clearing the literal default_models the platform
# itself shipped. Both arms of the deploy path (≤ AUTO_LIMIT clears and
# audits; above it is a no-op with a warning; it never raises) and the
# operator task's CONFIRM guard. The literals are read from the class under
# test, never spelled here.
RSpec.describe Ai::Providers::LiteralDefaultCleanup do
  let(:account) { create(:account) }
  let(:log_io) { StringIO.new }
  let(:logger) { Logger.new(log_io) }

  def literal_for(type) = described_class::SHIPPED_DEFAULTS.fetch(type).first

  # A provider as a pre-E3b write left it: `default_model` set in
  # configuration_schema, with a synced catalog that may or may not list it.
  def provider_with(default_model:, catalog: [ "catalog-model-1" ], type: "openai", owner: account)
    create(:ai_provider, account: owner, provider_type: type).tap do |p|
      p.update_columns(
        configuration_schema: { "models" => [], "default_model" => default_model },
        supported_models: catalog.map { |id| { "id" => id, "name" => id } }
      )
    end
  end

  def default_of(provider) = Ai::Provider.find(provider.id).configuration_schema["default_model"]
  def cleanup_audits = AuditLog.where(action: described_class::AUDIT_ACTION).select { |a| a.metadata["change"] == described_class::CHANGE }

  describe ".matching_rows" do
    it "matches a shipped literal absent from the catalog, and nothing else — every arm" do
      stale = provider_with(default_model: literal_for("openai"))
      still_listed = provider_with(default_model: literal_for("openai"), catalog: [ literal_for("openai") ])
      operator_choice = provider_with(default_model: "operator-picked-model")
      other_types_literal = provider_with(default_model: literal_for("openai"), type: "anthropic")
      string_catalog = create(:ai_provider, account: account, provider_type: "openai").tap do |p|
        p.update_columns(configuration_schema: { "default_model" => literal_for("openai") },
                         supported_models: [ literal_for("openai") ])
      end

      ids = described_class.matching_rows.map(&:first)

      expect(ids).to eq([ stale.id ])
      expect(ids).not_to include(still_listed.id, operator_choice.id, other_types_literal.id, string_catalog.id)
    end
  end

  describe ".auto_clear (the migration)" do
    it "clears and audits when AUTO_LIMIT rows or fewer match" do
      stale = provider_with(default_model: literal_for("openai"))
      kept = provider_with(default_model: "operator-picked-model")

      outcome = described_class.auto_clear(logger: logger)

      expect(outcome.status).to eq(:cleared)
      expect(outcome.provider_ids).to eq([ stale.id ])
      expect(Ai::Provider.find(stale.id).configuration_schema).to have_key("default_model")
      expect(default_of(stale)).to be_nil
      expect(default_of(kept)).to eq("operator-picked-model")

      audit = cleanup_audits.sole
      expect(audit.account_id).to eq(account.id)
      expect(audit.metadata["cleared"]).to eq(stale.id => literal_for("openai"))
    end

    # A never-synced provider is out of scope. Its catalog is empty, so "absent
    # from the synced catalog" is vacuous there, and clearing its shipped default
    # would turn a working provider into a refusal at deploy time. Both arms in
    # one run: the never-synced rows keep their default and still resolve it; the
    # synced row beside them is cleared and audited.
    it "leaves a never-synced provider on its shipped default untouched, and still clears a synced one" do
      never_synced = provider_with(default_model: literal_for("openai"), catalog: [])
      not_an_array = provider_with(default_model: literal_for("openai")).tap { |p| p.update_columns(supported_models: {}) }
      synced = provider_with(default_model: literal_for("openai"))

      expect(described_class.matching_rows.map(&:first)).to eq([ synced.id ])

      outcome = described_class.auto_clear(logger: logger)

      expect(outcome.provider_ids).to eq([ synced.id ])
      expect(default_of(never_synced)).to eq(literal_for("openai"))
      expect(Ai::Provider.find(never_synced.id).default_model).to eq(literal_for("openai"))
      expect(default_of(not_an_array)).to eq(literal_for("openai"))
      expect(default_of(synced)).to be_nil
      expect(cleanup_audits.sole.metadata["cleared"]).to eq(synced.id => literal_for("openai"))
    end

    it "writes one audit row per affected account" do
      other_account = create(:account)
      provider_with(default_model: literal_for("openai"))
      provider_with(default_model: literal_for("anthropic"), type: "anthropic", owner: other_account)

      described_class.auto_clear(logger: logger)

      expect(cleanup_audits.map(&:account_id)).to match_array([ account.id, other_account.id ])
    end

    it "changes NOTHING above AUTO_LIMIT, and says how to proceed" do
      stale = Array.new(described_class::AUTO_LIMIT + 1) { provider_with(default_model: literal_for("openai")) }

      outcome = described_class.auto_clear(logger: logger)

      expect(outcome.status).to eq(:skipped)
      expect(stale.map { |p| default_of(p) }.uniq).to eq([ literal_for("openai") ])
      expect(cleanup_audits).to be_empty
      expect(log_io.string).to include("#{stale.size} providers", described_class::RAKE_TASK, "CONFIRM=#{stale.size}")
    end

    it "never raises — a failure is a warning and a no-op" do
      stale = provider_with(default_model: literal_for("openai"))
      allow(described_class).to receive(:matching_rows).and_raise(ActiveRecord::StatementInvalid, "boom")

      outcome = nil
      expect { outcome = described_class.auto_clear(logger: logger) }.not_to raise_error
      expect(outcome.status).to eq(:error)
      expect(log_io.string).to include("did not run", "boom")
      expect(default_of(stale)).to eq(literal_for("openai"))
    end

    it "clears nothing when the audit write fails — the two are one transaction" do
      stale = provider_with(default_model: literal_for("openai"))
      allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect(described_class.auto_clear(logger: logger).status).to eq(:error)
      expect(default_of(stale)).to eq(literal_for("openai"))
    end
  end

  describe ".operator_run (the rake task's CONFIRM guard)" do
    let(:io) { StringIO.new }
    let!(:stale) { Array.new(6) { provider_with(default_model: literal_for("openai")) } }

    def unchanged? = stale.all? { |p| default_of(p) == literal_for("openai") }

    it "prints the count and the first 3 and last 1 ids, and changes nothing without CONFIRM" do
      outcome = described_class.operator_run(confirm: nil, io: io)
      ids = stale.map(&:id).sort

      expect(outcome.status).to eq(:unconfirmed)
      expect(io.string).to include("6 provider(s)", ids[0], ids[1], ids[2], ids.last, "CONFIRM=6")
      expect(io.string).not_to include(ids[3])
      expect(unchanged?).to be true
    end

    it "refuses a CONFIRM that is not the current count, or not a number" do
      [ "5", "7", "six", "6 ", "" ].each do |bad|
        expect(described_class.operator_run(confirm: bad, io: io).status).to eq(bad.strip.empty? ? :unconfirmed : :mismatch)
      end
      expect(unchanged?).to be true
      expect(cleanup_audits).to be_empty
    end

    it "clears on the exact current count, even above AUTO_LIMIT" do
      outcome = described_class.operator_run(confirm: "6", io: io)

      expect(outcome.status).to eq(:cleared)
      expect(stale.map { |p| default_of(p) }.uniq).to eq([ nil ])
      expect(cleanup_audits.sole.metadata["cleared"].keys).to match_array(stale.map(&:id))
    end

    it "is wired to the rake task" do
      Rails.application.load_tasks unless Rake::Task.task_defined?(described_class::RAKE_TASK)
      task = Rake::Task[described_class::RAKE_TASK]
      task.reenable
      original = ENV["CONFIRM"]
      ENV["CONFIRM"] = "6"
      expect { task.invoke }.to output(/Cleared 6/).to_stdout
      expect(stale.map { |p| default_of(p) }.uniq).to eq([ nil ])
    ensure
      ENV["CONFIRM"] = original
    end
  end
end
