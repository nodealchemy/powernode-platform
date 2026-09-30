# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/ai_guidance.rake :migrate_auto_memory — the thin wrapper over
# Ai::Guidance::AutoMemoryMigrator (whose triage/apply behaviour is covered in
# auto_memory_migrator_spec.rb). Verifies only the rake seam: the dir argument,
# the APPLY / ACCOUNT_ID / INCLUDE_SENSITIVE / IDENTIFIERS_FILE / MANIFEST_DIR
# env vars, and that the printed output never echoes matched text.
RSpec.describe "ai:migrate_auto_memory" do
  include_context "auto memory fixtures"

  let!(:account) { create(:account) }
  let(:env_keys) { %w[APPLY ACCOUNT_ID INCLUDE_SENSITIVE IDENTIFIERS_FILE MANIFEST_DIR ALLOW_NO_IDENTIFIERS ALLOW_NO_PRIVATE_LIST] }

  # Runs the task with the given env; returns [stdout, aborted?].
  def run_task(*args, env: {})
    previous = env_keys.to_h { |k| [ k, ENV[k] ] }
    env_keys.each { |k| ENV.delete(k) }
    ENV["IDENTIFIERS_FILE"] = identifiers_file
    ENV["MANIFEST_DIR"] = manifest_dir
    # Deterministic wherever extensions/private is absent; overridable per example.
    ENV["ALLOW_NO_PRIVATE_LIST"] = "1"
    env.each { |k, v| ENV[k] = v }
    previous_application = Rake.application
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/ai_guidance", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
    out = StringIO.new
    original = $stdout
    $stdout = out
    aborted = false
    begin
      Rake::Task["ai:migrate_auto_memory"].invoke(*args)
    rescue SystemExit
      aborted = true
    ensure
      $stdout = original
    end
    [ out.string, aborted ]
  ensure
    Rake.application = previous_application
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  before do
    write_memory("plain-note")
    write_memory("ident-note", body: "Host #{identifier_marker}.")
    write_memory("sensitive-note", body: "The #{sensitive_marker} account.")
  end

  it "is a dry run by default: prints the triage, writes nothing to the database" do
    out = nil
    expect { out, = run_task(memory_dir) }.not_to change(Ai::SharedKnowledge, :count)

    expect(out).to include("mode=dry_run", "(a) identifiers: 1 -> ident-note", "(b) sensitive: 1 -> sensitive-note")
    expect(out).to include("dry run")
    expect(File.exist?(File.join(manifest_dir, Ai::Guidance::AutoMemoryMigrator::DRY_RUN_MANIFEST_FILE))).to be(true)
  end

  it "never echoes matched text" do
    out, = run_task(memory_dir)

    [ identifier_marker, sensitive_marker ].each { |marker| expect(out).not_to include(marker) }
  end

  it "requires the dir argument" do
    out, aborted = run_task

    expect(aborted).to be(true)
    expect(out).not_to include("mode=")
  end

  it "requires ACCOUNT_ID for APPLY" do
    _out, aborted = run_task(memory_dir, env: { "APPLY" => "1" })

    expect(aborted).to be(true)
    expect(Ai::SharedKnowledge.count).to eq(0)
  end

  it "applies only under APPLY=1, and set (b) only with INCLUDE_SENSITIVE=1" do
    run_task(memory_dir, env: { "APPLY" => "1", "ACCOUNT_ID" => account.id })
    expect(Ai::SharedKnowledge.where(account: account).pluck(:title)).to eq(%w[plain-note])

    run_task(memory_dir, env: { "APPLY" => "1", "ACCOUNT_ID" => account.id, "INCLUDE_SENSITIVE" => "1" })
    expect(Ai::SharedKnowledge.where(account: account).pluck(:title)).to contain_exactly("plain-note", "sensitive-note")
  end

  it "aborts an APPLY whose identifiers list is empty, unless ALLOW_NO_IDENTIFIERS=1" do
    File.write(identifiers_file, "# nothing\n")

    _out, aborted = run_task(memory_dir, env: { "APPLY" => "1", "ACCOUNT_ID" => account.id })
    expect(aborted).to be(true)
    expect(Ai::SharedKnowledge.count).to eq(0)

    run_task(memory_dir, env: { "APPLY" => "1", "ACCOUNT_ID" => account.id, "ALLOW_NO_IDENTIFIERS" => "1" })
    # Set (a) cannot fire with no list, so ident-note applies; (b) is still gated.
    expect(Ai::SharedKnowledge.where(account: account).pluck(:title)).to contain_exactly("plain-note", "ident-note")
  end

  it "aborts an APPLY with no derivable private-extension names, unless ALLOW_NO_PRIVATE_LIST=1" do
    allow(Dir).to receive(:glob).and_call_original
    allow(Dir).to receive(:glob).with(Rails.root.parent.join("extensions", "private", "*")).and_return([])

    _out, aborted = run_task(memory_dir, env: { "APPLY" => "1", "ACCOUNT_ID" => account.id, "ALLOW_NO_PRIVATE_LIST" => "0" })
    expect(aborted).to be(true)
    expect(Ai::SharedKnowledge.count).to eq(0)

    out, aborted = run_task(memory_dir, env: { "APPLY" => "1", "ACCOUNT_ID" => account.id })
    expect(aborted).to be(false)
    expect(out).to include("(c) private names: check disabled")
  end
end
