# frozen_string_literal: true

module Ai
  module Guidance
    # One parsed auto-memory note: a markdown file with a YAML frontmatter block
    # (name, description, metadata.type, optional originSessionId) and a body that
    # may link other notes as [[slug]]. Pure parsing — no database, no network.
    #
    # .load_dir is deliberately NON-recursive: MEMORY.md (the index) and every
    # subdirectory (archive/, apo-sprint-staging/, dated archive-* folders) are
    # out of scope, symlinks are never followed (a link could reach an archived
    # or out-of-directory file), and a note without frontmatter cannot be keyed
    # or typed, so it is reported by slug and left alone.
    class AutoMemoryFile
      INDEX_FILE = "MEMORY.md"
      FRONTMATTER = /\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)(.*)\z/m
      LINK = /\[\[([^\]|#\n]+?)(?:[|#][^\]\n]*)?\]\]/

      Loaded = Struct.new(:files, :without_frontmatter, :symlinks, keyword_init: true)

      attr_reader :slug, :filename, :raw, :name, :description, :body, :memory_type, :origin_session_id

      def self.load_dir(dir)
        loaded = Loaded.new(files: [], without_frontmatter: [], symlinks: [])
        dir = Pathname.new(dir)
        return loaded unless dir.directory?

        # base: keeps glob metacharacters in the directory path itself inert.
        Dir.glob("*.md", base: dir.to_s).sort.each do |name|
          next if name == INDEX_FILE

          path = dir.join(name).to_s
          if File.symlink?(path)
            loaded.symlinks << name
            next
          end
          next unless File.file?(path)

          parsed = parse(path)
          if parsed
            loaded.files << parsed
          else
            loaded.without_frontmatter << File.basename(path, ".md")
          end
        end
        loaded
      end

      # Returns nil for a file without a usable frontmatter mapping.
      def self.parse(path)
        raw = File.read(path)
        match = FRONTMATTER.match(raw)
        return nil unless match

        # Date/Time are plain data: an unquoted `created: 2026-09-30` must not drop the note.
        front = YAML.safe_load(match[1], permitted_classes: [ Date, Time ], aliases: false)
        return nil unless front.is_a?(Hash)

        new(path: path, raw: raw, front: front, body: match[2])
      rescue Psych::Exception, ArgumentError # ArgumentError: not valid UTF-8
        nil
      end

      def initialize(path:, raw:, front:, body:)
        @filename = File.basename(path)
        @slug = File.basename(path, ".md")
        @raw = raw
        @body = body.to_s.strip
        @name = front["name"].to_s.strip.presence
        @description = front["description"].to_s.strip.presence
        metadata = front["metadata"].is_a?(Hash) ? front["metadata"] : {}
        @memory_type = normalize_type(metadata["type"] || front["type"])
        @origin_session_id = (front["originSessionId"] || front["origin_session_id"] ||
                              metadata["originSessionId"] || metadata["origin_session_id"]).to_s.strip.presence
      end

      def title
        (name || slug.tr("-", " ")).truncate(500)
      end

      # The description leads (recall surfaces the first line), then the body.
      def content
        [ description, body ].compact_blank.join("\n\n")
      end

      # Other notes this one links as [[slug]], in first-seen order, never itself.
      def links
        content.scan(LINK).flatten.map(&:strip).reject { |l| l.empty? || l == slug }.uniq
      end

      private

      def normalize_type(value)
        value.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "").presence
      end
    end
  end
end
