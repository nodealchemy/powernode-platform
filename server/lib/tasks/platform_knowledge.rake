# frozen_string_literal: true

namespace :knowledge do
  desc "Populate all knowledge stores (RAG, shared knowledge, knowledge graph)"
  task populate: :environment do
    account = resolve_knowledge_account
    validate_knowledge_provider!(account)

    puts "Populating all knowledge stores for: #{account.name} (#{account.id})"
    puts "=" * 60

    service = Ai::KnowledgePopulation::PopulatorService.new(account: account)
    stats = service.populate_all!

    print_knowledge_stats(stats)
  end

  desc "Populate RAG knowledge base only"
  task rag: :environment do
    account = resolve_knowledge_account
    validate_knowledge_provider!(account)

    puts "Populating RAG knowledge base..."
    service = Ai::KnowledgePopulation::PopulatorService.new(account: account)
    service.populate_rag!
    print_knowledge_stats(service.stats)
  end

  desc "Populate knowledge graph only"
  task graph: :environment do
    account = resolve_knowledge_account
    validate_knowledge_provider!(account)

    puts "Populating knowledge graph..."
    service = Ai::KnowledgePopulation::PopulatorService.new(account: account)
    service.populate_graph!
    print_knowledge_stats(service.stats)
  end

  desc "Populate shared knowledge entries only"
  task shared: :environment do
    account = resolve_knowledge_account
    validate_knowledge_provider!(account)

    puts "Populating shared knowledge entries..."
    service = Ai::KnowledgePopulation::PopulatorService.new(account: account)
    service.populate_shared!
    print_knowledge_stats(service.stats)
  end

  desc "Show knowledge population status"
  task status: :environment do
    account = resolve_knowledge_account

    kb_name = Ai::KnowledgePopulation::PopulatorService::KB_NAME
    kb = account.ai_knowledge_bases.find_by(name: kb_name)
    graph_stats = Ai::KnowledgeGraph::GraphService.new(account).statistics
    sk_stats = Ai::Memory::SharedKnowledgeService.new(account: account).stats

    puts "\n#{'=' * 50}"
    puts "  Knowledge Population Status"
    puts "#{'=' * 50}"

    puts "\nRAG Knowledge Base:"
    if kb
      puts "  Name:       #{kb.name}"
      puts "  Documents:  #{kb.document_count}"
      puts "  Chunks:     #{kb.chunk_count}"
      puts "  Tokens:     #{kb.total_tokens}"
      puts "  Status:     #{kb.status}"
    else
      puts "  (not created yet)"
    end

    puts "\nKnowledge Graph:"
    puts "  Nodes:      #{graph_stats[:node_count]}"
    puts "  Edges:      #{graph_stats[:edge_count]}"
    puts "  By type:    #{graph_stats[:by_node_type]}"
    puts "  Density:    #{graph_stats[:density]}"

    puts "\nShared Knowledge:"
    if sk_stats[:success]
      s = sk_stats[:stats]
      puts "  Total:      #{s[:total]}"
      puts "  By type:    #{s[:by_content_type]}"
      puts "  Avg quality: #{s[:avg_quality_score]}"
      puts "  Embeddings: #{s[:with_embeddings]} (#{s[:embedding_coverage]}%)"
    end

    puts ""
  end
end

# ================================================================
# HELPERS (defined at top level, scoped to this file via naming)
# ================================================================

def resolve_knowledge_account
  if ENV["ACCOUNT_ID"].present?
    Account.find(ENV["ACCOUNT_ID"])
  else
    account = Account.joins(:ai_providers)
                     .where(ai_providers: { is_active: true })
                     .first
    abort "ERROR: No account with active AI provider found. Set ACCOUNT_ID=<uuid>." unless account
    account
  end
end

def validate_knowledge_provider!(account)
  return if account.ai_providers.active.exists?

  abort "ERROR: Account #{account.id} has no active AI provider. Configure one first."
end

def print_knowledge_stats(stats)
  puts "\n#{'=' * 50}"
  puts "  Population Results"
  puts "#{'=' * 50}"

  if stats[:rag].present?
    puts "\nRAG Documents:"
    puts "  Created:  #{stats[:rag][:created]}"
    puts "  Skipped:  #{stats[:rag][:skipped]}"
    puts "  Failed:   #{stats[:rag][:failed]}" if stats[:rag][:failed].to_i.positive?
    puts "  Total:    #{stats[:rag][:total]}"
  end

  if stats[:shared].present?
    puts "\nShared Knowledge:"
    puts "  Created:  #{stats[:shared][:created]}"
    puts "  Skipped:  #{stats[:shared][:skipped]}"
    puts "  Total:    #{stats[:shared][:total]}"
  end

  if stats[:graph].present?
    puts "\nKnowledge Graph:"
    puts "  Nodes created:  #{stats[:graph][:nodes_created]}"
    puts "  Nodes skipped:  #{stats[:graph][:nodes_skipped]}"
    puts "  Edges created:  #{stats[:graph][:edges_created]}"
    puts "  Edges skipped:  #{stats[:graph][:edges_skipped]}"
  end

  puts ""
end
