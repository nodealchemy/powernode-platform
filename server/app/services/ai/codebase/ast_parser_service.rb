# frozen_string_literal: true

module Ai
  module Codebase
    class AstParserService
      # Normalized symbol structure returned by all parsers:
      # {
      #   name: String,          # Simple name (e.g., "full_name")
      #   qualified_name: String, # Qualified name (e.g., "User#full_name")
      #   kind: Symbol,          # :class, :module, :method, :function, :constant, :interface, :type_definition, :variable
      #   visibility: Symbol,    # :public, :private, :protected (Ruby), :export, :default (JS/TS)
      #   line_start: Integer,
      #   line_end: Integer,
      #   params: String|nil,    # Parameter signature (e.g., "(name, age:)")
      #   return_type: String|nil,
      #   parent: String|nil,    # Parent class/module name
      #   superclass: String|nil, # For classes: the superclass
      #   decorators: Array,     # Python decorators, TS decorators
      #   properties: Hash       # Additional metadata
      # }

      SUPPORTED_EXTENSIONS = {
        ruby: %w[.rb .rake .gemspec],
        typescript: %w[.ts .tsx],
        javascript: %w[.js .jsx .mjs .cjs],
        python: %w[.py]
      }.freeze

      def initialize
        @extension_map = SUPPORTED_EXTENSIONS.each_with_object({}) do |(lang, exts), map|
          exts.each { |ext| map[ext] = lang }
        end
      end

      # Parse a file and return normalized symbols.
      # @param file_path [String] Absolute path to the file
      # @param content [String|nil] File content (reads from disk if nil)
      # @return [Hash] { language:, file_path:, symbols: [...] }
      def parse(file_path, content: nil)
        ext = File.extname(file_path).downcase
        language = @extension_map[ext]

        return { language: nil, file_path: file_path, symbols: [] } unless language

        content ||= File.read(file_path, encoding: "utf-8")
        symbols = case language
                  when :ruby then parse_ruby(content, file_path)
                  when :typescript, :javascript then parse_typescript(content, file_path, language)
                  when :python then parse_python(content, file_path)
                  else []
                  end

        { language: language, file_path: file_path, symbols: symbols }
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        { language: language, file_path: file_path, symbols: [] }
      end

      # Detect language from file extension.
      def detect_language(file_path)
        @extension_map[File.extname(file_path).downcase]
      end

      # Check if a file is parseable.
      def supported?(file_path)
        @extension_map.key?(File.extname(file_path).downcase)
      end

      private

      # ─── Ruby Parser (Prism) ──────────────────────────────────────────

      def parse_ruby(content, file_path)
        result = Prism.parse(content)
        symbols = []
        extract_ruby_nodes(result.value, symbols, file_path, nil, :public)
        symbols
      rescue => e
        Rails.logger.warn "[AstParserService] Prism parse error for #{file_path}: #{e.message}"
        parse_ruby_fallback(content, file_path)
      end

      def extract_ruby_nodes(node, symbols, file_path, parent_name, current_visibility)
        return unless node

        case node
        when Prism::ClassNode
          name = node.name.to_s
          qualified = parent_name ? "#{parent_name}::#{name}" : name
          superclass_name = extract_ruby_constant_name(node.superclass)

          symbols << {
            name: name,
            qualified_name: "#{relative_path(file_path)}::#{qualified}",
            kind: :class,
            visibility: :public,
            line_start: node.location.start_line,
            line_end: node.location.end_line,
            params: nil,
            return_type: nil,
            parent: parent_name,
            superclass: superclass_name,
            decorators: [],
            properties: {}
          }

          # Recurse into class body
          if node.body
            child_visibility = :public
            extract_ruby_body(node.body, symbols, file_path, qualified, child_visibility)
          end

        when Prism::ModuleNode
          name = node.name.to_s
          qualified = parent_name ? "#{parent_name}::#{name}" : name

          symbols << {
            name: name,
            qualified_name: "#{relative_path(file_path)}::#{qualified}",
            kind: :module,
            visibility: :public,
            line_start: node.location.start_line,
            line_end: node.location.end_line,
            params: nil,
            return_type: nil,
            parent: parent_name,
            superclass: nil,
            decorators: [],
            properties: {}
          }

          if node.body
            extract_ruby_body(node.body, symbols, file_path, qualified, :public)
          end

        when Prism::DefNode
          name = node.name.to_s
          separator = name.start_with?("self.") ? "." : "#"
          clean_name = name.delete_prefix("self.")
          qualified = parent_name ? "#{parent_name}#{separator}#{clean_name}" : clean_name
          params_str = extract_ruby_params(node.parameters)

          symbols << {
            name: clean_name,
            qualified_name: "#{relative_path(file_path)}::#{qualified}",
            kind: :method,
            visibility: current_visibility,
            line_start: node.location.start_line,
            line_end: node.location.end_line,
            params: params_str,
            return_type: nil,
            parent: parent_name,
            superclass: nil,
            decorators: [],
            properties: { instance_method: !name.start_with?("self.") }
          }

        when Prism::SingletonClassNode
          # class << self — methods inside are class methods
          if node.body
            extract_ruby_body(node.body, symbols, file_path, parent_name, current_visibility)
          end

        when Prism::ConstantWriteNode
          name = node.name.to_s
          qualified = parent_name ? "#{parent_name}::#{name}" : name

          symbols << {
            name: name,
            qualified_name: "#{relative_path(file_path)}::#{qualified}",
            kind: :constant,
            visibility: :public,
            line_start: node.location.start_line,
            line_end: node.location.start_line,
            params: nil,
            return_type: nil,
            parent: parent_name,
            superclass: nil,
            decorators: [],
            properties: {}
          }

        when Prism::ProgramNode
          extract_ruby_body(node.statements, symbols, file_path, parent_name, current_visibility) if node.statements
        end
      end

      def extract_ruby_body(body_node, symbols, file_path, parent_name, current_visibility)
        statements = case body_node
                     when Prism::StatementsNode then body_node.body
                     when Prism::BeginNode then body_node.statements&.body || []
                     else []
                     end

        statements.each do |stmt|
          # Track visibility changes
          if stmt.is_a?(Prism::CallNode) && %w[private protected public].include?(stmt.name.to_s) && stmt.arguments.nil?
            current_visibility = stmt.name.to_sym
            next
          end

          extract_ruby_nodes(stmt, symbols, file_path, parent_name, current_visibility)
        end
      end

      def extract_ruby_params(params_node)
        return nil unless params_node

        parts = []

        # Required parameters
        params_node.requireds&.each do |p|
          parts << p.name.to_s if p.respond_to?(:name)
        end

        # Optional parameters
        params_node.optionals&.each do |p|
          parts << "#{p.name}=" if p.respond_to?(:name)
        end

        # Rest parameter
        if params_node.rest && params_node.rest.respond_to?(:name) && params_node.rest.name
          parts << "*#{params_node.rest.name}"
        end

        # Keyword parameters
        params_node.keywords&.each do |p|
          if p.respond_to?(:name)
            suffix = p.is_a?(Prism::RequiredKeywordParameterNode) ? ":" : ": ..."
            parts << "#{p.name}#{suffix}"
          end
        end

        # Keyword rest
        if params_node.keyword_rest && params_node.keyword_rest.respond_to?(:name) && params_node.keyword_rest.name
          parts << "**#{params_node.keyword_rest.name}"
        end

        # Block parameter
        if params_node.block && params_node.block.respond_to?(:name) && params_node.block.name
          parts << "&#{params_node.block.name}"
        end

        parts.empty? ? nil : "(#{parts.join(', ')})"
      end

      def extract_ruby_constant_name(node)
        return nil unless node

        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          parts = []
          current = node
          while current.is_a?(Prism::ConstantPathNode)
            parts.unshift(current.name.to_s)
            current = current.parent
          end
          parts.unshift(current.name.to_s) if current.is_a?(Prism::ConstantReadNode)
          parts.join("::")
        else
          nil
        end
      end

      # Fallback regex parser for Ruby when Prism fails
      def parse_ruby_fallback(content, file_path)
        symbols = []
        lines = content.lines
        current_visibility = :public

        lines.each_with_index do |line, idx|
          line_num = idx + 1
          stripped = line.strip

          case stripped
          when /\A(private|protected|public)\s*$/
            current_visibility = Regexp.last_match(1).to_sym
          when /\Aclass\s+(\w+(?:::\w+)*)(?:\s*<\s*(\w+(?:::\w+)*))?\s*$/
            name = Regexp.last_match(1)
            superclass = Regexp.last_match(2)
            symbols << build_symbol(name, name, :class, :public, line_num, line_num, nil, nil, nil, superclass, file_path)
          when /\Amodule\s+(\w+(?:::\w+)*)\s*$/
            name = Regexp.last_match(1)
            symbols << build_symbol(name, name, :module, :public, line_num, line_num, nil, nil, nil, nil, file_path)
          when /\Adef\s+(self\.)?(\w+[?!=]?)(?:\((.*?)\))?\s*$/
            is_class_method = Regexp.last_match(1).present?
            name = Regexp.last_match(2)
            params = Regexp.last_match(3) ? "(#{Regexp.last_match(3)})" : nil
            symbols << build_symbol(name, name, :method, current_visibility, line_num, line_num, params, nil, nil, nil, file_path)
          end
        end

        symbols
      end

      # ─── TypeScript/JavaScript Parser (Regex) ─────────────────────────

      def parse_typescript(content, file_path, language)
        symbols = []
        lines = content.lines
        brace_depth = 0
        current_class = nil
        class_start_depth = nil

        lines.each_with_index do |line, idx|
          line_num = idx + 1
          stripped = line.strip

          # Track brace depth for class scope
          brace_depth += line.count("{") - line.count("}")

          # End of class scope
          if current_class && brace_depth <= class_start_depth.to_i
            current_class = nil
            class_start_depth = nil
          end

          # Export detection
          is_exported = stripped.start_with?("export ")
          visibility = is_exported ? :export : :default

          case stripped
          when /\A(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+(\w+(?:<[^>]*>)?))?(?:\s+implements\s+([\w,\s<>]+))?\s*\{/
            name = Regexp.last_match(1)
            superclass = Regexp.last_match(2)
            current_class = name
            class_start_depth = brace_depth - 1
            symbols << build_symbol(name, name, :class, visibility, line_num, line_num, nil, nil, nil, superclass, file_path)

          when /\A(?:export\s+)?interface\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+([\w,\s<>]+))?\s*\{/
            name = Regexp.last_match(1)
            symbols << build_symbol(name, name, :interface, visibility, line_num, line_num, nil, nil, nil, nil, file_path)

          when /\A(?:export\s+)?type\s+(\w+)(?:<[^>]*>)?\s*=/
            name = Regexp.last_match(1)
            symbols << build_symbol(name, name, :type_definition, visibility, line_num, line_num, nil, nil, nil, nil, file_path)

          when /\A(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*(?:<[^>]*>)?\((.*?)\)(?:\s*:\s*(\S+))?\s*\{/
            name = Regexp.last_match(1)
            params = "(#{Regexp.last_match(2)})"
            return_type = Regexp.last_match(3)
            symbols << build_symbol(name, name, :function, visibility, line_num, line_num, params, return_type, current_class, nil, file_path)

          when /\A(?:export\s+)?const\s+(\w+)(?:\s*:\s*(\S+))?\s*=\s*(?:\(|async\s*\()/
            # Arrow function assigned to const
            name = Regexp.last_match(1)
            return_type = Regexp.last_match(2)
            symbols << build_symbol(name, name, :function, visibility, line_num, line_num, nil, return_type, current_class, nil, file_path)

          when /\A(?:export\s+)?const\s+(\w+)(?:\s*:\s*(\S+))?\s*=/
            name = Regexp.last_match(1)
            # Only capture top-level constants (not inside classes)
            unless current_class
              symbols << build_symbol(name, name, :constant, visibility, line_num, line_num, nil, nil, nil, nil, file_path)
            end
          end

          # Class method detection (inside a class)
          next unless current_class

          case stripped
          when /\A(?:(?:public|private|protected|readonly|static|abstract|async)\s+)*(\w+)\s*(?:<[^>]*>)?\((.*?)\)(?:\s*:\s*(\S+))?\s*\{/
            name = Regexp.last_match(1)
            next if %w[if for while switch catch constructor].include?(name)

            params = "(#{Regexp.last_match(2)})"
            return_type = Regexp.last_match(3)
            method_visibility = stripped.match?(/\Aprivate\s/) ? :private : (stripped.match?(/\Aprotected\s/) ? :protected : :public)
            qualified = "#{current_class}##{name}"
            symbols << build_symbol(name, qualified, :method, method_visibility, line_num, line_num, params, return_type, current_class, nil, file_path)

          when /\Aconstructor\s*\((.*?)\)\s*\{/
            params = "(#{Regexp.last_match(1)})"
            qualified = "#{current_class}#constructor"
            symbols << build_symbol("constructor", qualified, :method, :public, line_num, line_num, params, nil, current_class, nil, file_path)
          end
        end

        symbols
      end

      # ─── Python Parser (Regex) ────────────────────────────────────────

      def parse_python(content, file_path)
        symbols = []
        lines = content.lines
        current_class = nil
        decorators = []

        lines.each_with_index do |line, idx|
          line_num = idx + 1
          stripped = line.strip
          indent = line[/\A\s*/].length

          # Reset class context at top-level
          current_class = nil if indent == 0 && !stripped.start_with?("@")

          if stripped.start_with?("@")
            decorators << stripped
            next
          end

          case stripped
          when /\Aclass\s+(\w+)(?:\((.*?)\))?\s*:/
            name = Regexp.last_match(1)
            superclass = Regexp.last_match(2)
            current_class = name if indent == 0
            symbols << build_symbol(name, name, :class, :public, line_num, line_num, nil, nil, nil, superclass, file_path, decorators: decorators.dup)
            decorators.clear

          when /\A(?:async\s+)?def\s+(\w+)\s*\((.*?)\)(?:\s*->\s*(\S+))?\s*:/
            name = Regexp.last_match(1)
            params = "(#{Regexp.last_match(2)})"
            return_type = Regexp.last_match(3)
            visibility = name.start_with?("_") ? :private : :public
            parent = indent > 0 ? current_class : nil
            qualified = parent ? "#{parent}##{name}" : name
            symbols << build_symbol(name, qualified, :method, visibility, line_num, line_num, params, return_type, parent, nil, file_path, decorators: decorators.dup)
            decorators.clear

          else
            decorators.clear unless stripped.empty?
          end
        end

        symbols
      end

      # ─── Helpers ──────────────────────────────────────────────────────

      def build_symbol(name, qualified_name, kind, visibility, line_start, line_end, params, return_type, parent, superclass, file_path, decorators: [])
        {
          name: name,
          qualified_name: "#{relative_path(file_path)}::#{qualified_name}",
          kind: kind,
          visibility: visibility,
          line_start: line_start,
          line_end: line_end,
          params: params,
          return_type: return_type,
          parent: parent,
          superclass: superclass,
          decorators: decorators,
          properties: {}
        }
      end

      def relative_path(file_path)
        # Store relative to the project root if possible
        file_path
      end

      # Make paths relative to a base directory.
      def relativize(file_path, base_path)
        Pathname.new(file_path).relative_path_from(Pathname.new(base_path)).to_s
      end
    end
  end
end
