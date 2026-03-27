# frozen_string_literal: true

module Ai
  module Codebase
    class FeatureHubService
      WIKILINK_PATTERN = /\[\[([^\]]+)\]\]/

      def initialize(base_path:)
        @base_path = File.expand_path(base_path)
      end

      # Scan for markdown files and extract wikilink-based navigation graph.
      # @param path [String] Subdirectory to scan (relative to base_path)
      # @return [Hash] Hubs with links and orphan detection
      def scan(path: "docs")
        target = File.join(@base_path, path)
        return { success: false, error: "Path does not exist: #{target}" } unless File.directory?(target)

        md_files = collect_markdown_files(target)
        all_targets = Set.new

        hubs = md_files.map do |file_path|
          relative = relative_path(file_path)
          content = File.read(file_path, encoding: "utf-8")

          # Extract title from first heading
          title = content.match(/\A#\s+(.+)/)&.captures&.first || File.basename(file_path, ".*")

          # Extract wikilinks
          links = content.scan(WIKILINK_PATTERN).flatten.uniq
          all_targets.merge(links)

          link_details = links.map do |target_name|
            resolved = resolve_wikilink(target_name, File.dirname(file_path))
            { target: target_name, exists: resolved.present?, resolved_path: resolved }
          end

          {
            file: relative,
            title: title.strip,
            links: link_details,
            link_count: links.size
          }
        end

        # Find orphans — markdown files not linked from any hub
        linked_files = hubs.flat_map { |h| h[:links].select { |l| l[:exists] }.map { |l| l[:resolved_path] } }.to_set
        all_md_relatives = md_files.map { |f| relative_path(f) }.to_set
        orphans = (all_md_relatives - linked_files).to_a.sort

        {
          success: true,
          hubs: hubs.select { |h| h[:link_count] > 0 }.sort_by { |h| -h[:link_count] },
          all_files: hubs.sort_by { |h| h[:file] },
          orphans: orphans,
          total_files: md_files.size,
          total_links: hubs.sum { |h| h[:link_count] }
        }
      end

      private

      def collect_markdown_files(dir)
        files = []
        Dir.glob(File.join(dir, "**", "*.md")).each do |f|
          next if f.include?("node_modules") || f.include?(".git")
          files << f
        end
        files.sort
      end

      def resolve_wikilink(target_name, context_dir)
        # Try several resolution strategies
        candidates = [
          File.join(context_dir, "#{target_name}.md"),
          File.join(context_dir, target_name),
          File.join(@base_path, "#{target_name}.md"),
          File.join(@base_path, target_name),
          File.join(@base_path, "docs", "#{target_name}.md")
        ]

        # Also try converting to path (e.g., "Platform Architecture" → "PLATFORM_ARCHITECTURE.md")
        slugified = target_name.gsub(/\s+/, "_").upcase
        candidates << File.join(context_dir, "#{slugified}.md")
        candidates << File.join(@base_path, "docs", "#{slugified}.md")

        found = candidates.find { |c| File.exist?(c) }
        found ? relative_path(found) : nil
      end

      def relative_path(path)
        Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(@base_path)).to_s
      rescue ArgumentError
        path
      end
    end
  end
end
