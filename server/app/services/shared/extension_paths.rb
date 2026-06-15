# frozen_string_literal: true

module Shared
  # Single source of truth for "where do extensions live on disk" across the
  # Rails app (admin UI, feature gating, doc sync).
  #
  # Extensions live flat under extensions/<slug>. Private/custom extensions
  # (added locally by maintainers; the whole extensions/private/ tree is
  # gitignored) live one level deeper under extensions/private/<slug>.
  # "private" is a grouping directory, never an extension slug — the slug is
  # always the leaf directory name.
  #
  # NOTE: the Gemfile's extensions_loader_helper.rb and the Vite / Flipper /
  # worker boot scanners implement this same two-location rule independently,
  # because they run before the Rails app (and thus this constant) is loaded.
  module ExtensionPaths
    EXTENSIONS_ROOT = Rails.root.join("..", "extensions")
    PRIVATE_DIRNAME = "private"

    module_function

    # All extension directories across both locations, as Pathnames.
    # Skips the "private" grouping directory itself.
    def extension_dirs
      return [] unless EXTENSIONS_ROOT.directory?

      flat = EXTENSIONS_ROOT.children.select(&:directory?).reject do |child|
        child.basename.to_s == PRIVATE_DIRNAME
      end

      private_root = EXTENSIONS_ROOT.join(PRIVATE_DIRNAME)
      nested = private_root.directory? ? private_root.children.select(&:directory?) : []

      flat + nested
    end

    # Directory for a given slug, searched flat-first then private.
    # Returns a Pathname or nil if no such extension directory exists.
    def dir_for(slug)
      return nil if slug.blank? || slug.to_s == PRIVATE_DIRNAME

      flat = EXTENSIONS_ROOT.join(slug.to_s)
      return flat if flat.directory?

      nested = EXTENSIONS_ROOT.join(PRIVATE_DIRNAME, slug.to_s)
      return nested if nested.directory?

      nil
    end

    # Manifest path (extension.json) for a slug, or nil if the dir is absent.
    # The returned path may not itself exist — callers should check.
    def manifest_for(slug)
      dir_for(slug)&.join("extension.json")
    end

    # Does this slug have an extension.json on disk in either location?
    def manifest_present?(slug)
      manifest = manifest_for(slug)
      !manifest.nil? && manifest.exist?
    end
  end
end
