#!/bin/bash
# Stop hook — re-indexes changed source files collected by this session's marker.
# Each session operates on its own batch file — no cross-session interference.
# Backgrounds the actual re-index to stay within the hook timeout.

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
BATCH_FILE="/tmp/powernode_reindex_${SESSION_ID}.txt"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"

[[ ! -s "$BATCH_FILE" ]] && exit 0

# Consume batch: move to processing file, clear for next response
PROCESSING="/tmp/powernode_reindex_${SESSION_ID}_processing.txt"
mv "$BATCH_FILE" "$PROCESSING"

FILE_COUNT=$(wc -l < "$PROCESSING")
FILE_LIST=$(cat "$PROCESSING")

# Background the re-index — hook returns immediately
(
  cd "$PROJECT_DIR/server" || exit 1

  bundle exec rails runner "
    account = Account.first
    kb = Ai::KnowledgeBase.find_by(name: 'Codebase: powernode-platform')
    exit unless kb

    base_path = '$PROJECT_DIR'
    service = Ai::Codebase::IndexingService.new(account: account, knowledge_base: kb, base_path: base_path)
    embedding_svc = Ai::Memory::EmbeddingService.new(account: account)

    files = <<~FILES.strip.split(\"\\n\").reject(&:empty?)
$FILE_LIST
    FILES

    reindexed = 0
    files.each do |relative_path|
      full_path = File.join(base_path, relative_path)
      next unless File.exist?(full_path)
      next unless Ai::Codebase::AstParserService.new.supported?(full_path)

      begin
        service.send(:process_file, full_path, incremental: false)
        reindexed += 1

        # Regenerate embedding for the file node
        rel = Pathname.new(full_path).relative_path_from(Pathname.new(base_path)).to_s
        node = kb.knowledge_graph_nodes.find_by(name: rel, node_type: 'code_entity', entity_type: 'file', status: 'active')
        if node&.description.present?
          emb = embedding_svc.generate(\"#{node.name} #{node.description}\")
          node.set_embedding!(emb) if emb
        end
      rescue => e
        Rails.logger.warn \"[CodebaseReindex] #{relative_path}: #{e.message}\"
      end
    end

    Rails.logger.info \"[CodebaseReindex] Session $SESSION_ID: re-indexed #{reindexed}/#{files.size} files\"
  " 2>/dev/null

  rm -f "$PROCESSING"
) &

echo "⟳ Re-indexing $FILE_COUNT changed file(s) in background" >&2
exit 0
