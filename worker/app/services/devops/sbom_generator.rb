# frozen_string_literal: true

require "json"

module Devops
  # Worker-side best-effort SBOM (Software Bill of Materials) generator over a
  # checked-out repo, composed into the land security-scan job (G4 worker depth)
  # ALONGSIDE the secret scanner, Brakeman SAST, and the dependency-CVE scanner
  # (Loop Engineering Parity FU6). It reads the standard dependency lockfiles in
  # the workspace and emits a CycloneDX 1.5 JSON inventory of the resolved
  # components (name / version / package-url).
  #
  # ADDITIVE METADATA, NOT A GATE: the SBOM is dependency INVENTORY, not a finding.
  # Unlike the secret scan and the diff (which fail the land CLOSED when they can't
  # complete) this NEVER blocks or fails the land — generation is wrapped so any
  # error degrades to an empty-but-valid CycloneDX document instead of raising.
  #
  # PORTABLE by design: it parses the lockfiles already present in the checkout in
  # PURE RUBY — no external SBOM tool (syft/cdxgen) and no new runtime gem — so the
  # worker stays a clean no-op when a manifest is absent and never grows a heavy
  # dependency, exactly like the GENERIC dependency-CVE scanner sibling.
  #
  # Crypto/secret-safe by construction: ONLY a component's name and resolved
  # version (→ purl) are read. Fields that can carry credentials — package-lock
  # `resolved`/`integrity` URLs, Gemfile.lock `remote:`, requirements `--index-url`
  # / VCS `git+https://token@…` refs, poetry `[package.source]` — are NEVER read or
  # emitted. The document carries inventory identity, never lockfile values.
  module SbomGenerator
    FORMAT = "CycloneDX"
    SPEC_VERSION = "1.5"
    GENERATOR_NAME = "powernode-land-sbom"
    GENERATOR_VERSION = "1.0"

    # Bound the document so a pathological monorepo can't produce an unbounded
    # SBOM. Truncation is FLAGGED in the result (never silent).
    MAX_COMPONENTS = 5000

    # Skip a pathologically large lockfile rather than read it into memory (a
    # crafted multi-million-entry manifest would otherwise drive parse-time memory
    # regardless of MAX_COMPONENTS). Best-effort: an oversized manifest yields no
    # components for that ecosystem.
    MAX_MANIFEST_BYTES = 25 * 1024 * 1024

    # A component is inventoried ONLY when its name AND version are simple
    # ecosystem identifiers. This is the secret-safety chokepoint: a git/url
    # dependency (npm v1 stores the resolved URL in `version`; a yarn/npm git
    # descriptor embeds it in the NAME) carries an embedded `user:pass@…` / token,
    # so anything that is not a plain `name` / `@scope/name` and a plain version is
    # SKIPPED rather than risk emitting a credential into the SBOM.
    SAFE_NAME = /\A(?:@[A-Za-z0-9][A-Za-z0-9._\-]*\/)?[A-Za-z0-9][A-Za-z0-9._\-]*\z/
    SAFE_VERSION = /\A[A-Za-z0-9][A-Za-z0-9._+!\-]*\z/

    # Each source: the lockfile to read (relative to the checkout root), the purl
    # ecosystem `type`, and the parser that turns its content into [[name, version], …].
    # Running a parser whose manifest is absent simply yields nothing (the reader
    # returns nil), mirroring how the dependency-CVE scanner skips an absent tool.
    SOURCES = [
      { file: "Gemfile.lock",      type: "gem",  parser: :parse_gemfile_lock },
      { file: "package-lock.json", type: "npm",  parser: :parse_package_lock },
      { file: "yarn.lock",         type: "npm",  parser: :parse_yarn_lock },
      { file: "requirements.txt",  type: "pypi", parser: :parse_requirements_txt },
      { file: "poetry.lock",       type: "pypi", parser: :parse_poetry_lock }
    ].freeze

    module_function

    # Build a CycloneDX 1.5 JSON SBOM over the dependency manifests in `workspace`.
    #
    # BEST-EFFORT / NEVER RAISES: an absent, unreadable, or garbled manifest yields
    # no components for that ecosystem; a catastrophic failure degrades to an
    # empty-but-valid document (`generated: false`). `reader` is a callable
    # `->(relative_path) { String | nil }` (defaults to a File-backed reader rooted
    # at the workspace) so the generator is decoupled from the filesystem and
    # trivially testable with canned manifest content — mirroring the dependency
    # scanner's injected `runner`.
    #
    # Returns a result hash:
    #   { format:, spec_version:, generated:, component_count:, truncated:, document: }
    # where `document` is the CycloneDX JSON-ready Hash.
    def generate(workspace, reader: nil, component_name: nil)
      read = reader || default_reader(workspace)
      components, truncated = collect_components(read)
      document = build_document(components, component_name)
      {
        format: FORMAT,
        spec_version: SPEC_VERSION,
        generated: true,
        component_count: components.size,
        truncated: truncated,
        document: document
      }
    rescue StandardError => e
      degraded(e)
    end

    # A File-backed reader rooted at the workspace. Returns file content or nil
    # (absent / unreadable) — never raises, so a missing checkout dir is a clean
    # empty SBOM rather than a failure.
    def default_reader(workspace)
      root = workspace.to_s
      lambda do |relative|
        path = File.join(root, relative)
        next nil unless File.file?(path)
        next nil if File.size(path) > MAX_MANIFEST_BYTES

        File.read(path)
      rescue StandardError
        nil
      end
    end

    # Read + parse every source, deduping components by purl (a package pinned in
    # more than one manifest, or listed twice in one, collapses to a single entry).
    # The MAX_COMPONENTS cap is enforced DURING collection (not after) so a wide
    # manifest can't accumulate an unbounded `seen` map; once the cap is hit we stop
    # and flag truncation. Returns [components, truncated].
    def collect_components(read)
      seen = {}
      truncated = false
      SOURCES.each do |source|
        break if truncated

        content = safe_read(read, source[:file])
        next if content.nil? || content.strip.empty?

        safe_parse(source[:parser], content).each do |name, version|
          component = build_component(source[:type], name.to_s.strip, version.to_s.strip)
          next if component.nil? || seen.key?(component["bom-ref"])

          if seen.size >= MAX_COMPONENTS
            truncated = true
            break
          end
          seen[component["bom-ref"]] = component
        end
      end
      [ seen.values, truncated ]
    end

    def safe_read(read, file)
      read.call(file)
    rescue StandardError
      nil
    end

    # Per-source isolation: a parser blowing up on one malformed manifest must not
    # sink the rest of the SBOM. Best-effort — never propagates.
    def safe_parse(parser, content)
      Array(send(parser, content))
    rescue StandardError
      []
    end

    # SECRET-SAFETY CHOKEPOINT: every parsed (name, version) flows through here.
    # A component is built ONLY when its name is a plain `name` / `@scope/name` and
    # its version (if any) is a plain version string. A credential-bearing git/url
    # dependency — npm v1's URL-in-`version`, a yarn/npm git descriptor's URL-in-name
    # — fails these patterns and is SKIPPED, so a token can never reach the SBOM.
    def build_component(type, name, version)
      return nil if name.empty? || !SAFE_NAME.match?(name)
      return nil unless version.empty? || SAFE_VERSION.match?(version)

      purl = build_purl(type, name, version)
      component = { "type" => "library", "name" => name, "purl" => purl, "bom-ref" => purl }
      component["version"] = version unless version.empty?
      component
    end

    # ---- CycloneDX document assembly -----------------------------------------

    def build_document(components, component_name)
      metadata = {
        "tools" => [
          { "vendor" => "Powernode", "name" => GENERATOR_NAME, "version" => GENERATOR_VERSION }
        ]
      }
      root = component_name.to_s.strip
      unless root.empty?
        metadata["component"] = { "type" => "application", "name" => root, "bom-ref" => "root:#{root}" }
      end

      {
        "bomFormat" => FORMAT,
        "specVersion" => SPEC_VERSION,
        "version" => 1,
        "metadata" => metadata,
        "components" => components
      }
    end

    def degraded(error)
      {
        format: FORMAT,
        spec_version: SPEC_VERSION,
        generated: false,
        component_count: 0,
        truncated: false,
        error: error.class.name, # class only — never the message (may carry a path/token)
        document: build_document([], nil)
      }
    end

    # ---- package-url (purl) --------------------------------------------------

    def build_purl(type, name, version)
      base = "pkg:#{type}/#{purl_name(name)}"
      version.empty? ? base : "#{base}@#{purl_encode(version)}"
    end

    # Keep path separators (npm scoped names are "@scope/pkg"); percent-encode each
    # segment so a leading "@" or other reserved char can't break the purl.
    def purl_name(name)
      name.split("/").map { |segment| purl_encode(segment) }.join("/")
    end

    # Percent-encode per-BYTE (not per-codepoint) so a multibyte char is encoded as
    # its UTF-8 bytes, per the purl/URI spec. (Valid npm/gem/pypi identifiers are
    # ASCII, so this is mostly belt-and-suspenders, but the encoding must be correct.)
    def purl_encode(string)
      string.to_s.gsub(/[^A-Za-z0-9._~%\-]/) { |char| char.bytes.map { |b| format("%%%02X", b) }.join }
    end

    # ---- lockfile parsers (name + version ONLY) ------------------------------

    # Gemfile.lock: top-level specs are indented EXACTLY 4 spaces ("name (version)")
    # inside a `specs:` block (GEM / GIT / PATH sources); their dependencies are
    # indented 6 spaces and are intentionally excluded. The `remote:` URL is never
    # read.
    def parse_gemfile_lock(content)
      pairs = []
      in_specs = false
      content.each_line do |raw|
        line = raw.chomp
        if line =~ /^\s+specs:\s*$/
          in_specs = true
          next
        end
        in_specs = false if line =~ /^\S/ # a new top-level section header ends specs

        next unless in_specs

        match = line.match(/^    ([A-Za-z0-9._\-]+) \(([^()]+)\)$/)
        pairs << [ match[1], match[2] ] if match
      end
      pairs
    end

    # npm package-lock: prefer the v2/v3 "packages" map (keyed by install path),
    # falling back to the v1 nested "dependencies" tree. `resolved`/`integrity` are
    # never read.
    def parse_package_lock(content)
      data = JSON.parse(content)
      packages = data["packages"]
      return npm_from_packages(packages) if packages.is_a?(Hash)

      npm_from_dependencies(data["dependencies"]) if data["dependencies"].is_a?(Hash)
    end

    def npm_from_packages(packages)
      packages.filter_map do |path, info|
        next if path.to_s.empty? # "" is the root project itself, not a dependency

        info ||= {}
        name = (info["name"].presence || npm_name_from_path(path)).to_s
        version = info["version"].to_s
        next if name.empty? || version.empty?

        [ name, version ]
      end
    end

    # "node_modules/@scope/pkg" → "@scope/pkg"; nested "…/node_modules/b" → "b".
    def npm_name_from_path(path)
      marker = "node_modules/"
      index = path.rindex(marker)
      index ? path[(index + marker.length)..] : path
    end

    # ITERATIVE (explicit stack, not recursion) over the v1 nested-dependency tree:
    # an untrusted lockfile can nest arbitrarily, and a deep recursion would raise
    # SystemStackError — which is NOT a StandardError and would escape every rescue.
    # An explicit stack keeps this best-effort and unconditionally non-raising.
    def npm_from_dependencies(deps)
      pairs = []
      stack = [ deps ]
      until stack.empty?
        node = stack.pop
        next unless node.is_a?(Hash)

        node.each do |name, info|
          info ||= {}
          pairs << [ name, info["version"] ] if info["version"]
          nested = info["dependencies"]
          stack.push(nested) if nested.is_a?(Hash)
        end
      end
      pairs
    end

    # yarn.lock (classic v1 AND Berry v2+): a dependency block opens with one or
    # more quoted/bare "name@range" specifiers on a non-indented line ending in ":",
    # followed by an indented version line — classic `version "x"` OR Berry
    # `version: x`. The `resolved`/`resolution` URL is never read. The Berry
    # `__metadata` block is rejected downstream by SAFE_NAME (not a package name).
    def parse_yarn_lock(content)
      pairs = []
      current = nil
      content.each_line do |raw|
        line = raw.rstrip
        next if line.empty? || line.lstrip.start_with?("#")

        if line.start_with?(" ", "\t")
          next unless current

          version = line.strip[/\Aversion\s*:?\s*"?([^"]+)"?\z/, 1]
          if version
            pairs << [ current, version ]
            current = nil
          end
        elsif line.end_with?(":")
          current = yarn_pkg_name(line)
        end
      end
      pairs
    end

    def yarn_pkg_name(header)
      first = header.sub(/:\s*$/, "").split(",").first.to_s.strip.gsub(/\A"|"\z/, "")
      at = first.rindex("@") # scoped names start with "@"; the LAST "@" precedes the range
      at && at.positive? ? first[0...at] : first
    end

    # requirements.txt: ONLY exact "name==version" pins (optionally with extras) are
    # inventoried. Option lines (-r, --index-url, -e), URL/VCS refs (may carry
    # credentials), comments, and non-pinned ranges are skipped.
    def parse_requirements_txt(content)
      pairs = []
      content.each_line do |raw|
        line = raw.split("#", 2).first.to_s.strip
        next if line.empty? || line.start_with?("-") || line.include?("://")

        # Exact-equality pins only: `==` (common) or `===` (PEP 440 arbitrary equality).
        match = line.match(/\A([A-Za-z0-9][A-Za-z0-9._\-]*)\s*(?:\[[^\]]*\])?\s*===?\s*([A-Za-z0-9][A-Za-z0-9._+!\-]*)/)
        pairs << [ match[1], match[2] ] if match
      end
      pairs
    end

    # poetry.lock: each component is a `[[package]]` block with `name`/`version`
    # keys; nested tables ([package.dependencies], [package.source], …) end the
    # current block so dependency constraints and source URLs are never inventoried.
    def parse_poetry_lock(content)
      pairs = []
      name = nil
      version = nil
      flush = lambda do
        pairs << [ name, version ] if name && version
        name = nil
        version = nil
      end

      content.each_line do |raw|
        line = raw.strip
        if line == "[[package]]"
          flush.call
        elsif line.start_with?("[")
          flush.call # any other table header closes the current package
        elsif (match = line.match(/\Aname\s*=\s*"([^"]+)"/))
          name = match[1]
        elsif (match = line.match(/\Aversion\s*=\s*"([^"]+)"/))
          version = match[1]
        end
      end
      flush.call
      pairs
    end
  end
end
