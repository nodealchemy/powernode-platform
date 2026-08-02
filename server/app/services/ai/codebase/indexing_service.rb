# frozen_string_literal: true

module Ai
  module Codebase
    class IndexingService
      BATCH_SIZE = 100
      MAX_FILES = 20000

      # Texts per embedding request. Bounded by TWO independent ceilings:
      #   - WorkerEmbeddingClient::TIMEOUT is 30s while the worker's own HTTParty
      #     call waits 60s, so the server hangs up first — a batch must finish
      #     well inside 30s or the work is done and then thrown away.
      #   - OpenAI allows 300k tokens/request; normalize_text truncates each text
      #     to 8000 chars (~2k tokens), so 100 worst-case texts ≈ 200k. 200 could
      #     breach it.
      EMBED_BATCH_SIZE = 100

      # Patterns to skip (gitignore-style)
      SKIP_PATTERNS = %w[
        node_modules/ vendor/ .git/ .bundle/ tmp/ log/ coverage/
        dist/ build/ .next/ __pycache__/ .pytest_cache/
        .DS_Store Thumbs.db *.min.js *.min.css *.map
        *.lock package-lock.json yarn.lock
      ].freeze

      SKIP_DIRS = %w[
        node_modules vendor .git .bundle tmp log coverage
        dist build .next __pycache__ .pytest_cache .cache
        .idea .vscode .devcontainer
      ].freeze

      attr_reader :account, :knowledge_base, :base_path, :stats

      def initialize(account:, knowledge_base:, base_path:)
        @account = account
        @knowledge_base = knowledge_base
        @base_path = File.expand_path(base_path)
        @parser = AstParserService.new
        @graph_service = Ai::KnowledgeGraph::GraphService.new(account)
        @stats = { files_processed: 0, nodes_created: 0, nodes_updated: 0, edges_created: 0, files_skipped: 0, errors: 0 }
      end

      # Run full or incremental indexing.
      # @param path [String|nil] Subdirectory to index (relative to base_path)
      # @param incremental [Boolean] Only re-index changed files
      # @return [Hash] Statistics about the indexing run
      def index(path: nil, incremental: true)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        target_path = path ? File.join(base_path, path) : base_path

        unless File.directory?(target_path)
          return { success: false, error: "Path does not exist: #{target_path}" }
        end

        knowledge_base.start_indexing!

        files = collect_files(target_path)
        Rails.logger.info "[CodebaseIndexing] Found #{files.size} files to process in #{target_path}"

        if files.size > MAX_FILES
          Rails.logger.warn "[CodebaseIndexing] Truncating to #{MAX_FILES} files (found #{files.size})"
          files = files.first(MAX_FILES)
        end

        # Index files in batches
        files.each_slice(BATCH_SIZE) do |batch|
          process_batch(batch, incremental: incremental)
        end

        # Generate embeddings for nodes missing them
        generate_embeddings

        knowledge_base.complete_indexing!

        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time).round(2)
        stats.merge(success: true, duration_seconds: elapsed)
      rescue => e
        knowledge_base.mark_error!(e.message)
        Rails.logger.error "[CodebaseIndexing] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
        stats.merge(success: false, error: e.message)
      end

      private

      # Collect all parseable files, respecting skip patterns.
      def collect_files(root_path)
        files = []
        gitignore = load_gitignore(root_path)

        walk_directory(root_path, files, gitignore)
        files.sort
      end

      def walk_directory(dir, files, gitignore)
        Dir.each_child(dir) do |entry|
          next if entry.start_with?(".")
          next if SKIP_DIRS.include?(entry)

          full_path = File.join(dir, entry)
          relative = relative_to_base(full_path)

          if File.directory?(full_path)
            next if gitignore_match?(relative + "/", gitignore)
            walk_directory(full_path, files, gitignore)
          elsif File.file?(full_path) && @parser.supported?(full_path)
            next if gitignore_match?(relative, gitignore)
            files << full_path
          end
        end
      rescue Errno::EACCES, Errno::ENOENT => e
        Rails.logger.debug "[CodebaseIndexing] Skipping inaccessible: #{e.message}"
      end

      def load_gitignore(root_path)
        gitignore_path = File.join(root_path, ".gitignore")
        return [] unless File.exist?(gitignore_path)

        File.readlines(gitignore_path)
            .map(&:strip)
            .reject { |line| line.empty? || line.start_with?("#") }
      rescue => e
        Rails.logger.debug "[CodebaseIndexing] Could not read .gitignore: #{e.message}"
        []
      end

      def gitignore_match?(relative_path, patterns)
        (SKIP_PATTERNS + patterns).any? do |pattern|
          File.fnmatch?(pattern, relative_path, File::FNM_PATHNAME | File::FNM_DOTMATCH) ||
            File.fnmatch?("**/#{pattern}", relative_path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
        end
      end

      # Process a batch of files.
      def process_batch(file_paths, incremental:)
        file_paths.each do |file_path|
          process_file(file_path, incremental: incremental)
        end
      end

      def process_file(file_path, incremental:)
        relative = relative_to_base(file_path)
        mtime = File.mtime(file_path).iso8601

        # Check if file needs re-indexing
        if incremental
          existing = find_file_node(relative)
          if existing && existing.metadata&.dig("file_mtime") == mtime
            @stats[:files_skipped] += 1
            return
          end
        end

        # Parse the file
        result = @parser.parse(file_path)
        return if result[:symbols].empty? && result[:language].nil?

        # Use relative paths in qualified names
        result[:symbols].each do |sym|
          sym[:qualified_name] = sym[:qualified_name].sub(file_path, relative)
        end

        ActiveRecord::Base.transaction do
          # Upsert file node
          file_node = upsert_node(
            name: relative,
            entity_type: "file",
            description: "#{result[:language]} file: #{relative}",
            properties: {
              "simple_name" => File.basename(file_path),
              "language" => result[:language].to_s,
              "extension" => File.extname(file_path),
              "symbol_count" => result[:symbols].size
            },
            metadata: { "file_mtime" => mtime, "file_size" => File.size(file_path) }
          )

          # Create/update symbol nodes and edges
          result[:symbols].each do |sym|
            symbol_node = upsert_node(
              name: sym[:qualified_name],
              entity_type: kind_to_entity_type(sym[:kind]),
              description: build_description(sym, relative),
              properties: {
                "simple_name" => sym[:name],
                "kind" => sym[:kind].to_s,
                "visibility" => sym[:visibility].to_s,
                "line_start" => sym[:line_start],
                "line_end" => sym[:line_end],
                "params" => sym[:params],
                "return_type" => sym[:return_type],
                "superclass" => sym[:superclass],
                "file_path" => relative
              }
            )

            # File → contains → symbol
            upsert_edge(file_node, symbol_node, "contains")

            # Class/module → defines → method
            if sym[:parent].present?
              parent_qualified = result[:symbols].find { |s| s[:name] == sym[:parent] && [:class, :module].include?(s[:kind]) }
              if parent_qualified
                parent_node = find_node_by_name(parent_qualified[:qualified_name])
                upsert_edge(parent_node, symbol_node, "defines") if parent_node
              end
            end

            # Inheritance edges
            if sym[:superclass].present?
              superclass_node = find_node_by_name_fuzzy(sym[:superclass])
              upsert_edge(symbol_node, superclass_node, "inherits") if superclass_node
            end
          end

          # Detect imports and create edges
          detect_imports(file_path, result[:language], file_node)
        end

        @stats[:files_processed] += 1
      rescue => e
        @stats[:errors] += 1
        Rails.logger.warn "[CodebaseIndexing] Error processing #{file_path}: #{e.message}"
      end

      # Detect import/require statements and create edges.
      def detect_imports(file_path, language, file_node)
        content = File.read(file_path, encoding: "utf-8")

        import_paths = case language
                       when :ruby
                         content.scan(/require(?:_relative)?\s+['"]([^'"]+)['"]/).flatten
                       when :typescript, :javascript
                         content.scan(/(?:import|require)\s*(?:\(?\s*['"]([^'"]+)['"]\s*\)?|.*?from\s+['"]([^'"]+)['"])/).flatten.compact
                       when :python
                         content.scan(/(?:from\s+(\S+)\s+import|import\s+(\S+))/).flatten.compact
                       else
                         []
                       end

        import_paths.each do |import_path|
          # Try to find the imported file in our index
          target_node = resolve_import_target(import_path, file_path, language)
          upsert_edge(file_node, target_node, "imports") if target_node
        end
      rescue => e
        Rails.logger.debug "[CodebaseIndexing] Import detection error for #{file_path}: #{e.message}"
      end

      def resolve_import_target(import_path, source_file, language)
        # Normalize the import path to a file path
        candidates = case language
                     when :ruby
                       # require_relative paths
                       if import_path.start_with?(".")
                         dir = File.dirname(source_file)
                         [File.expand_path("#{import_path}.rb", dir)]
                       else
                         # Absolute require — search in common locations
                         %w[app/models app/services app/controllers lib].map do |prefix|
                           File.join(base_path, prefix, "#{import_path}.rb")
                         end
                       end
                     when :typescript, :javascript
                       return nil if import_path.start_with?("@") && !import_path.start_with?("@/")
                       return nil unless import_path.start_with?(".")

                       dir = File.dirname(source_file)
                       base = File.expand_path(import_path, dir)
                       %W[#{base}.ts #{base}.tsx #{base}.js #{base}.jsx #{base}/index.ts #{base}/index.tsx #{base}/index.js]
                     when :python
                       [File.join(base_path, import_path.tr(".", "/") + ".py")]
                     else
                       []
                     end

        candidates&.each do |candidate|
          relative = relative_to_base(candidate)
          node = find_file_node(relative)
          return node if node
        end

        nil
      end

      # ─── Node/Edge CRUD ────────────────────────────────────────────

      def upsert_node(name:, entity_type:, description:, properties: {}, metadata: {})
        existing = knowledge_base.knowledge_graph_nodes
                                 .where(account: account, name: name, node_type: "code_entity", status: "active")
                                 .first

        if existing
          # The embedding is generated from "name description". name is the match
          # key here, so a changed description means the stored vector no longer
          # describes this entity. Clearing it re-queues the node for
          # generate_embeddings; leaving it (the old behaviour) meant a re-index
          # refreshed the text but kept the ORIGINAL vector forever, so semantic
          # search drifted further from the code on every run and no amount of
          # re-indexing could ever correct it.
          attrs = {
            entity_type: entity_type,
            description: description,
            properties: existing.properties.merge(properties),
            metadata: existing.metadata.merge(metadata),
            last_seen_at: Time.current,
            confidence: 1.0
          }
          attrs[:embedding] = nil if existing.description != description

          existing.update!(**attrs)
          existing.record_mention!
          @stats[:nodes_updated] += 1
          existing
        else
          node = knowledge_base.knowledge_graph_nodes.create!(
            account: account,
            name: name,
            node_type: "code_entity",
            entity_type: entity_type,
            description: description,
            properties: properties,
            metadata: metadata,
            status: "active",
            confidence: 1.0,
            mention_count: 1,
            last_seen_at: Time.current
          )
          @stats[:nodes_created] += 1
          node
        end
      end

      def upsert_edge(source_node, target_node, relation_type)
        return unless source_node && target_node

        existing = Ai::KnowledgeGraphEdge.where(
          account: account,
          source_node: source_node,
          target_node: target_node,
          relation_type: relation_type,
          status: "active"
        ).first

        return existing if existing

        edge = Ai::KnowledgeGraphEdge.create!(
          account: account,
          source_node: source_node,
          target_node: target_node,
          relation_type: relation_type,
          weight: 1.0,
          confidence: 1.0,
          status: "active"
        )
        @stats[:edges_created] += 1
        edge
      rescue ActiveRecord::RecordNotUnique
        # Edge already exists (race condition)
        nil
      end

      def find_file_node(relative_path)
        knowledge_base.knowledge_graph_nodes
                       .where(account: account, name: relative_path, node_type: "code_entity", entity_type: "file", status: "active")
                       .first
      end

      def find_node_by_name(qualified_name)
        knowledge_base.knowledge_graph_nodes
                       .where(account: account, name: qualified_name, node_type: "code_entity", status: "active")
                       .first
      end

      def find_node_by_name_fuzzy(simple_name)
        knowledge_base.knowledge_graph_nodes
                       .where(account: account, node_type: "code_entity", status: "active")
                       .where("name LIKE ?", "%::#{simple_name}")
                       .first
      end

      # ─── Embedding Generation ──────────────────────────────────────

      # One embedding request per EMBED_BATCH_SIZE nodes rather than one per node.
      # The per-node loop this replaces cost a full rails -> worker -> OpenAI
      # round-trip each time (~27 nodes/min measured on ops-hub 2026-08-02, i.e.
      # ~50h for a full re-vector). generate_batch collapses that into a single
      # provider call whose results are index-ordered by the worker.
      #
      # Failures are still tolerated so one bad batch cannot abort the run — but
      # they are COUNTED and surfaced in stats. Previously every failure was a
      # bare warn and complete_indexing! still ran, so a knowledge base could
      # reach status "completed" while 0% embedded and nothing said otherwise.
      def generate_embeddings
        pending = knowledge_base.knowledge_graph_nodes
                                .where(node_type: "code_entity", status: "active", embedding: nil)
                                .where.not(description: [nil, ""])

        total = pending.count
        @stats[:nodes_embedded] = 0
        @stats[:embedding_failures] = 0
        return if total.zero?

        Rails.logger.info "[CodebaseIndexing] Generating embeddings for #{total} nodes " \
                          "(batches of #{EMBED_BATCH_SIZE})"

        embedding_service = Ai::Memory::EmbeddingService.new(account: account)

        # Safe despite mutating the scope's own filter: find_in_batches pages on
        # id > last_seen, so rows that stop matching are already behind the cursor.
        pending.find_in_batches(batch_size: EMBED_BATCH_SIZE) do |nodes|
          vectors = embedding_service.generate_batch(nodes.map { |n| "#{n.name} #{n.description}" })

          nodes.each_with_index do |node, i|
            vector = vectors[i]
            if vector.blank?
              @stats[:embedding_failures] += 1
              next
            end
            node.set_embedding!(vector)
            @stats[:nodes_embedded] += 1
          end
        rescue => e
          @stats[:embedding_failures] += nodes.size
          Rails.logger.warn "[CodebaseIndexing] Embedding batch of #{nodes.size} failed: #{e.message}"
        end

        if @stats[:embedding_failures].positive?
          Rails.logger.error "[CodebaseIndexing] Embedded #{@stats[:nodes_embedded]}/#{total} nodes — " \
                             "#{@stats[:embedding_failures]} FAILED; semantic search will be incomplete"
        else
          Rails.logger.info "[CodebaseIndexing] Embedded #{@stats[:nodes_embedded]}/#{total} nodes"
        end
      rescue => e
        # Observed on ops-hub 2026-08-02: this swallowed an abort ~245 nodes into
        # a 7,599-node phase. index() then called complete_indexing! anyway, so
        # the knowledge base reported "active" while 92% of it had no vector and
        # nothing above warn level ever said so. Re-running the index resumes,
        # since the phase only ever selects embedding: nil.
        Rails.logger.error "[CodebaseIndexing] Embedding generation aborted after " \
                           "#{@stats[:nodes_embedded]} nodes: #{e.class}: #{e.message} — " \
                           "index will still be marked complete; re-run to finish embedding"
      end

      # ─── Helpers ───────────────────────────────────────────────────

      def relative_to_base(path)
        Pathname.new(path).relative_path_from(Pathname.new(base_path)).to_s
      rescue ArgumentError
        path
      end

      def kind_to_entity_type(kind)
        case kind
        when :class then "class"
        when :module then "module"
        when :method then "method"
        when :function then "function"
        when :constant then "constant"
        when :interface then "interface"
        when :type_definition then "type_definition"
        when :variable then "variable"
        else "function"
        end
      end

      def build_description(sym, relative_path)
        parts = ["#{sym[:kind]} `#{sym[:name]}`"]
        parts << "in #{relative_path}"
        parts << "#{sym[:visibility]}" if sym[:visibility] && sym[:visibility] != :public
        parts << "params: #{sym[:params]}" if sym[:params]
        parts << "returns: #{sym[:return_type]}" if sym[:return_type]
        parts << "extends #{sym[:superclass]}" if sym[:superclass]
        parts.join(" — ")
      end
    end
  end
end
