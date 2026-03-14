# frozen_string_literal: true

module Ai
  module CodeReview
    class DiffAnalyzerService
      CHANGE_TYPES = %w[new_code modification deletion refactor rename].freeze

      # Analyze a unified diff string
      def analyze(diff_text)
        return empty_analysis if diff_text.blank?

        files = extract_changed_files(diff_text)
        total_additions = 0
        total_deletions = 0
        change_types = Hash.new(0)

        files.each do |file|
          hunks = extract_hunks(file[:diff])
          file[:hunks] = hunks
          classifications = classify_changes(hunks)

          file[:classifications] = classifications
          file[:additions] = hunks.sum { |h| h[:added_lines].size }
          file[:deletions] = hunks.sum { |h| h[:removed_lines].size }

          total_additions += file[:additions]
          total_deletions += file[:deletions]

          classifications.each { |c| change_types[c] += 1 }
        end

        {
          changed_files: files,
          total_additions: total_additions,
          total_deletions: total_deletions,
          files_count: files.size,
          change_types: change_types
        }
      end

      # Extract list of changed files from diff
      def extract_changed_files(diff_text)
        files = []
        current_file = nil
        current_diff_lines = []

        diff_text.each_line do |line|
          if line.start_with?("diff --git")
            if current_file
              files << finalize_file(current_file, current_diff_lines)
            end

            paths = parse_diff_header(line)
            current_file = {
              file_path: paths[:new_path] || paths[:old_path],
              old_path: paths[:old_path],
              new_path: paths[:new_path],
              change_type: determine_file_change_type(paths)
            }
            current_diff_lines = []
          elsif line.start_with?("new file mode")
            current_file[:change_type] = "added" if current_file
          elsif line.start_with?("deleted file mode")
            current_file[:change_type] = "deleted" if current_file
          elsif line.start_with?("rename from")
            current_file[:change_type] = "renamed" if current_file
          else
            current_diff_lines << line
          end
        end

        files << finalize_file(current_file, current_diff_lines) if current_file
        files
      end

      # Extract individual change hunks with line numbers
      def extract_hunks(file_diff)
        hunks = []
        current_hunk = nil

        file_diff.each_line do |line|
          if line.start_with?("@@")
            hunks << current_hunk if current_hunk
            header = parse_hunk_header(line)
            current_hunk = {
              old_start: header[:old_start],
              old_count: header[:old_count],
              new_start: header[:new_start],
              new_count: header[:new_count],
              added_lines: [],
              removed_lines: [],
              context_lines: []
            }
            next
          end

          next unless current_hunk

          case line[0]
          when "+"
            current_hunk[:added_lines] << {
              content: line[1..].chomp,
              line_number: current_hunk[:new_start] + current_hunk[:added_lines].size
            }
          when "-"
            current_hunk[:removed_lines] << {
              content: line[1..].chomp,
              line_number: current_hunk[:old_start] + current_hunk[:removed_lines].size
            }
          when " "
            current_hunk[:context_lines] << line[1..].chomp
          end
        end

        hunks << current_hunk if current_hunk
        hunks
      end

      # Categorize changes in hunks
      def classify_changes(hunks)
        classifications = []

        hunks.each do |hunk|
          added = hunk[:added_lines].size
          removed = hunk[:removed_lines].size

          if removed.zero? && added > 0
            classifications << "new_code"
          elsif added.zero? && removed > 0
            classifications << "deletion"
          elsif added > 0 && removed > 0
            # Check if it looks like a refactor (similar line count, structural changes)
            ratio = [added, removed].min.to_f / [added, removed].max
            if ratio > 0.7
              classifications << "refactor"
            else
              classifications << "modification"
            end
          end
        end

        classifications.uniq
      end

      private

      def empty_analysis
        {
          changed_files: [],
          total_additions: 0,
          total_deletions: 0,
          files_count: 0,
          change_types: {}
        }
      end

      def parse_diff_header(line)
        match = line.match(%r{diff --git a/(.+?) b/(.+)})
        return { old_path: nil, new_path: nil } unless match

        { old_path: match[1], new_path: match[2] }
      end

      def parse_hunk_header(line)
        match = line.match(/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
        return { old_start: 0, old_count: 0, new_start: 0, new_count: 0 } unless match

        {
          old_start: match[1].to_i,
          old_count: (match[2] || "1").to_i,
          new_start: match[3].to_i,
          new_count: (match[4] || "1").to_i
        }
      end

      def determine_file_change_type(paths)
        return "added" if paths[:old_path] == "/dev/null"
        return "deleted" if paths[:new_path] == "/dev/null"
        return "renamed" if paths[:old_path] != paths[:new_path]

        "modified"
      end

      def finalize_file(file_data, diff_lines)
        file_data[:diff] = diff_lines.join
        file_data
      end
    end
  end
end
