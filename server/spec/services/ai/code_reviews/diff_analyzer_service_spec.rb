# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CodeReviews::DiffAnalyzerService, type: :service do
  subject(:analyzer) { described_class.new }

  describe '#analyze' do
    it 'returns empty analysis for blank diff' do
      result = analyzer.analyze("")

      expect(result[:changed_files]).to eq([])
      expect(result[:total_additions]).to eq(0)
      expect(result[:total_deletions]).to eq(0)
      expect(result[:files_count]).to eq(0)
    end

    it 'returns empty analysis for nil diff' do
      result = analyzer.analyze(nil)
      expect(result[:changed_files]).to eq([])
    end

    it 'analyzes a single-file diff with additions' do
      diff = "diff --git a/app/models/user.rb b/app/models/user.rb\n@@ -10,6 +10,8 @@ class User\n existing\n+new line 1\n+new line 2\n"
      result = analyzer.analyze(diff)

      expect(result[:files_count]).to eq(1)
      expect(result[:total_additions]).to eq(2)
      expect(result[:total_deletions]).to eq(0)
    end

    it 'analyzes multi-file diff' do
      diff = "diff --git a/file1.rb b/file1.rb\n@@ -1,3 +1,4 @@\n+added line\ndiff --git a/file2.rb b/file2.rb\n@@ -1,3 +1,4 @@\n+another line\n"
      result = analyzer.analyze(diff)
      expect(result[:files_count]).to eq(2)
    end
  end

  describe '#extract_changed_files' do
    it 'extracts file paths' do
      diff = "diff --git a/foo.rb b/foo.rb\n"
      files = analyzer.extract_changed_files(diff)
      expect(files.size).to eq(1)
      expect(files.first[:file_path]).to eq("foo.rb")
    end

    it 'identifies new files' do
      diff = "diff --git a/new.rb b/new.rb\nnew file mode 100644\n"
      files = analyzer.extract_changed_files(diff)
      expect(files.first[:change_type]).to eq("added")
    end

    it 'identifies deleted files' do
      diff = "diff --git a/old.rb b/old.rb\ndeleted file mode 100644\n"
      files = analyzer.extract_changed_files(diff)
      expect(files.first[:change_type]).to eq("deleted")
    end

    it 'identifies renamed files' do
      diff = "diff --git a/old.rb b/new.rb\nrename from old.rb\n"
      files = analyzer.extract_changed_files(diff)
      expect(files.first[:change_type]).to eq("renamed")
    end
  end

  describe '#extract_hunks' do
    it 'parses hunk headers and collects lines' do
      hunk_text = "@@ -10,6 +10,8 @@\n+added\n-removed\n context\n"
      hunks = analyzer.extract_hunks(hunk_text)

      expect(hunks.size).to eq(1)
      expect(hunks.first[:old_start]).to eq(10)
      expect(hunks.first[:added_lines].size).to eq(1)
      expect(hunks.first[:removed_lines].size).to eq(1)
    end

    it 'handles multiple hunks' do
      text = "@@ -1,3 +1,4 @@\n+a\n@@ -20,3 +21,4 @@\n+b\n"
      hunks = analyzer.extract_hunks(text)
      expect(hunks.size).to eq(2)
    end
  end

  describe '#classify_changes' do
    it 'classifies pure additions as new_code' do
      hunks = [{ added_lines: [{ content: "x" }], removed_lines: [] }]
      expect(analyzer.classify_changes(hunks)).to include("new_code")
    end

    it 'classifies pure deletions' do
      hunks = [{ added_lines: [], removed_lines: [{ content: "x" }] }]
      expect(analyzer.classify_changes(hunks)).to include("deletion")
    end

    it 'classifies balanced changes as refactor' do
      hunks = [{ added_lines: Array.new(10) { { content: "x" } }, removed_lines: Array.new(10) { { content: "y" } } }]
      expect(analyzer.classify_changes(hunks)).to include("refactor")
    end

    it 'classifies unbalanced changes as modification' do
      hunks = [{ added_lines: Array.new(10) { { content: "x" } }, removed_lines: Array.new(2) { { content: "y" } } }]
      expect(analyzer.classify_changes(hunks)).to include("modification")
    end
  end
end
