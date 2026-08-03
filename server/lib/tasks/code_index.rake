# frozen_string_literal: true

namespace :code_index do
  desc "Generate query-shaped LLM summaries for indexed code symbols (see " \
       "Ai::Codebase::SymbolSummaryService). DRY RUN BY DEFAULT — counts and prices the " \
       "work without calling the LLM; pass RUN=1 to actually spend. " \
       "Env: KB=<knowledge_base id|name> BASE_PATH=<checkout> [ACCOUNT=<id>] [LIMIT=<n>] " \
       "[MODEL=<id>] [PACE=<seconds>] [TYPES=class,method,...] [RUN=1]"
  task summarize: :environment do
    kb_ref    = ENV["KB"].presence
    base_path = ENV["BASE_PATH"].presence
    abort "KB is required (knowledge base id or name)" if kb_ref.blank?

    account =
      if ENV["ACCOUNT"].present?
        Account.find(ENV["ACCOUNT"])
      elsif Account.count == 1
        Account.first
      else
        abort "ACCOUNT is required (#{Account.count} accounts exist)"
      end

    kb = account.ai_knowledge_bases.where(id: kb_ref).first ||
         account.ai_knowledge_bases.where(name: kb_ref).first
    abort "Knowledge base not found for account #{account.id}: #{kb_ref}" if kb.nil?

    # A missing/incorrect checkout is not fatal — the summariser falls back to
    # signature+doc — but it silently produces far weaker summaries for the ~61% of
    # symbols with no doc comment, which are exactly the ones this exists to fix.
    if base_path.blank?
      warn "[code_index:summarize] WARNING: no BASE_PATH — summarising from signatures only, " \
           "no method bodies. Undocumented symbols will get weak summaries."
    elsif !File.directory?(base_path)
      abort "BASE_PATH is not a directory: #{base_path}"
    end

    types = ENV["TYPES"].presence&.split(",")&.map(&:strip) ||
            Ai::Codebase::SymbolSummaryService::SUMMARIZABLE_TYPES
    limit = ENV["LIMIT"].presence&.to_i
    pace  = ENV["PACE"].presence&.to_f || 0.0
    run   = ENV["RUN"] == "1"

    service = Ai::Codebase::SymbolSummaryService.new(
      account: account, knowledge_base: kb, base_path: base_path, model: ENV["MODEL"].presence
    )

    stats = service.summarize!(limit: limit, entity_types: types, dry_run: !run, pace: pace)

    puts "[code_index:summarize] account=#{account.id} kb=#{kb.id} (#{kb.name})"
    puts "[code_index:summarize] types=#{types.join(',')}"
    puts "[code_index:summarize] pending without a summary: #{stats[:pending_total]}"
    puts "[code_index:summarize] this run would cover:      #{stats[:candidates]}"

    unless run
      puts "[code_index:summarize] estimated LLM calls:       #{stats[:estimated_calls]} " \
           "(batches of #{Ai::Codebase::SymbolSummaryService::SUMMARY_BATCH})"
      puts "[code_index:summarize] DRY RUN — nothing was called and nothing was written."
      puts "[code_index:summarize] Re-run with RUN=1 to spend. Consider LIMIT= for a pilot first."
      next
    end

    puts "[code_index:summarize] model=#{stats[:model]} batches=#{stats[:batches]}"
    puts "[code_index:summarize] summarized=#{stats[:summarized]} failures=#{stats[:failures]} " \
         "no_body=#{stats[:skipped_no_body]}"
    puts "[code_index:summarize] status=#{stats[:status]}" if stats[:status]
    puts "[code_index:summarize] Summarised nodes had their vector CLEARED — re-run the index " \
         "embed phase to put the new text into search, then verify count(embedding) = count(id)."
  end

  desc "Export symbols still needing a summary as JSONL, for a FLAT-RATE CLI producer " \
       "(subagents) to summarise off-platform. Env: KB=<id|name> FILE=<out.jsonl> " \
       "[ACCOUNT=<id>] [LIMIT=<n>] [TYPES=class,method,...]"
  task export_pending: :environment do
    kb_ref = ENV["KB"].presence
    file   = ENV["FILE"].presence
    abort "KB is required" if kb_ref.blank?
    abort "FILE is required (output .jsonl path)" if file.blank?

    account = resolve_account
    kb = resolve_kb(account, kb_ref)
    types = ENV["TYPES"].presence&.split(",")&.map(&:strip) ||
            Ai::Codebase::SymbolSummaryService::SUMMARIZABLE_TYPES

    scope = kb.knowledge_graph_nodes
              .where(account: account, node_type: "code_entity", status: "active")
              .where(entity_type: types)
              .where("properties->>'llm_summary' IS NULL OR properties->>'llm_summary' = ''")
    scope = scope.limit(ENV["LIMIT"].to_i) if ENV["LIMIT"].present?

    count = 0
    File.open(file, "w") do |io|
      scope.find_each do |node|
        p = node.properties || {}
        io.puts({
          name: node.name, kind: p["kind"] || node.entity_type, parent: p["parent"],
          file_path: p["file_path"], line_start: p["line_start"], line_end: p["line_end"],
          params: p["params"], doc: p["doc"]
        }.compact.to_json)
        count += 1
      end
    end

    puts "[code_index:export_pending] wrote #{count} symbol(s) to #{file}"
    puts "[code_index:export_pending] Producer must return JSONL of {\"name\":..,\"summary\":..} " \
         "and it must come from the SAME checkout the index was built from, or names will not match."
  end

  desc "Import summaries produced off-platform (flat-rate CLI subagents) into the code index. " \
       "DRY RUN BY DEFAULT — pass RUN=1 to write. " \
       "Env: KB=<id|name> FILE=<in.jsonl> [ACCOUNT=<id>] [SOURCE=<label>] [RUN=1]"
  task import_summaries: :environment do
    kb_ref = ENV["KB"].presence
    file   = ENV["FILE"].presence
    abort "KB is required" if kb_ref.blank?
    abort "FILE not found: #{file}" if file.blank? || !File.file?(file)

    account = resolve_account
    kb = resolve_kb(account, kb_ref)
    source = ENV["SOURCE"].presence || "cli-subagent"
    run    = ENV["RUN"] == "1"

    records = File.readlines(file).filter_map do |line|
      line = line.strip
      next if line.empty?

      JSON.parse(line) rescue nil
    end

    service = Ai::Codebase::SymbolSummaryService.new(account: account, knowledge_base: kb)
    stats = service.import!(records, source: source, dry_run: !run)

    puts "[code_index:import_summaries] account=#{account.id} kb=#{kb.id} source=#{source}"
    puts "[code_index:import_summaries] records parsed: #{records.size}"
    unless run
      puts "[code_index:import_summaries] DRY RUN — nothing written. Re-run with RUN=1."
      next
    end

    puts "[code_index:import_summaries] applied=#{stats[:summarized]} " \
         "malformed=#{stats[:failures]} name_not_in_index=#{stats.fetch(:missing, 0)}"
    puts "[code_index:import_summaries] Imported nodes had their vector CLEARED — run the embed " \
         "phase, then verify count(embedding) = count(id)."
  end

  def resolve_account
    return Account.find(ENV["ACCOUNT"]) if ENV["ACCOUNT"].present?
    return Account.first if Account.count == 1

    abort "ACCOUNT is required (#{Account.count} accounts exist)"
  end

  def resolve_kb(account, kb_ref)
    kb = account.ai_knowledge_bases.where(id: kb_ref).first ||
         account.ai_knowledge_bases.where(name: kb_ref).first
    abort "Knowledge base not found for account #{account.id}: #{kb_ref}" if kb.nil?
    kb
  end
end
