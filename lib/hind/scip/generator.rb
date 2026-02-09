require_relative 'scip_pb'
require_relative 'global_state'

module Hind
  module SCIP
    class Generator
      attr_reader :project_root, :documents

      def initialize(project_root)
        @project_root = project_root
        @documents = []
        @package_info = detect_package_info
      end

      def execute(files)
        GlobalState.instance.reset

        # Pass 1: Collect all definitions
        files.each do |file|
          collect_definitions(file)
        end

        # Pass 2: Process files and references
        files.each do |file|
          process_file(file)
        end

        Index.new(
          metadata: Metadata.new(
            version: ProtocolVersion::UnspecifiedProtocolVersion,
            tool_info: ToolInfo.new(
              name: 'hind',
              version: Hind::VERSION,
              arguments: []
            ),
            project_root: "file://#{File.expand_path(@project_root)}",
            text_document_encoding: TextEncoding::UTF8
          ),
          documents: @documents
        )
      end

      private

      def detect_package_info
        gemspec = Dir.glob(File.join(@project_root, '*.gemspec')).first
        if gemspec
          begin
            content = File.read(gemspec)
            name = content[/spec\.name\s*=\s*['"]([^'"]+)['"]/, 1]
            version = content[/spec\.version\s*=\s*['"]([^'"]+)['"]/, 1]

            # If version is a constant like Hind::VERSION, we might not find it easily via regex
            # Let's try to find it via VERSION = '...'
            if version.nil?
              version_file = Dir.glob(File.join(@project_root, 'lib/**/version.rb')).first
              if version_file
                version = File.read(version_file)[/VERSION\s*=\s*['"]([^'"]+)['"]/, 1]
              end
            end

            return {name: name, version: version || '0.1.0'} if name
          rescue
            # Fallback
          end
        end
        {name: 'hind', version: Hind::VERSION}
      end

      def collect_definitions(relative_path)
        absolute_path = File.join(@project_root, relative_path)
        return unless File.exist?(absolute_path)

        source = File.read(absolute_path)
        result = Prism.parse(source)

        visitor = ScipVisitor.new(relative_path, {mode: :index, package_info: @package_info})
        result.value.accept(visitor)
      end

      def process_file(relative_path)
        absolute_path = File.join(@project_root, relative_path)
        return unless File.exist?(absolute_path)

        source = File.read(absolute_path)
        result = Prism.parse(source)

        occurrences = []
        symbols = []

        visitor = ScipVisitor.new(relative_path, {mode: :emit, package_info: @package_info})
        result.value.accept(visitor)
        occurrences.concat(visitor.occurrences)
        symbols.concat(visitor.symbols)

        @documents << Document.new(
          relative_path: relative_path,
          occurrences: occurrences,
          symbols: symbols
        )
      end

      class ScipVisitor < Prism::Visitor
        attr_reader :occurrences, :symbols

        def initialize(file_path, options = {})
          @file_path = file_path
          @mode = options[:mode] || :emit # :index or :emit
          package_info = options[:package_info] || {}
          @occurrences = []
          @symbols = []
          @current_scope = []
          @package_prefix = "scip-ruby rubygems #{package_info[:name] || "hind"} #{package_info[:version] || "0.1.0"} "
        end

        def visit_class_node(node)
          name = scip_name(node.constant_path.slice)
          @current_scope.push(name)
          symbol = "#{@package_prefix}#{@current_scope.join("#")}#"

          if @mode == :index
            GlobalState.instance.add_symbol(current_scope_name, symbol)
          else
            # Definition role = 1
            range = [
              node.constant_path.location.start_line - 1,
              node.constant_path.location.start_column,
              node.constant_path.location.end_column
            ]

            @occurrences << Occurrence.new(
              range: range,
              symbol: symbol,
              symbol_roles: 1,
              syntax_kind: SyntaxKind::Identifier
            )

            unless GlobalState.instance.emitted?(symbol)
              @symbols << SymbolInformation.new(
                symbol: symbol,
                documentation: ["class #{node.constant_path.slice}"],
                kind: SymbolInformation::Kind::Class
              )
              GlobalState.instance.mark_emitted(symbol)
            end
          end

          super
          @current_scope.pop
        end

        def visit_module_node(node)
          name = scip_name(node.constant_path.slice)
          @current_scope.push(name)
          symbol = "#{@package_prefix}#{@current_scope.join("#")}#"

          if @mode == :index
            GlobalState.instance.add_symbol(current_scope_name, symbol)
          else
            range = [
              node.constant_path.location.start_line - 1,
              node.constant_path.location.start_column,
              node.constant_path.location.end_column
            ]

            @occurrences << Occurrence.new(
              range: range,
              symbol: symbol,
              symbol_roles: 1,
              syntax_kind: SyntaxKind::Identifier
            )

            unless GlobalState.instance.emitted?(symbol)
              @symbols << SymbolInformation.new(
                symbol: symbol,
                documentation: ["module #{node.constant_path.slice}"],
                kind: SymbolInformation::Kind::Module
              )
              GlobalState.instance.mark_emitted(symbol)
            end
          end

          super
          @current_scope.pop
        end

        def visit_constant_write_node(node)
          name = scip_name(node.name.to_s)
          suffix = @current_scope.empty? ? '' : '#'
          symbol = "#{@package_prefix}#{@current_scope.join("#")}#{suffix}#{name}."

          if @mode == :index
            GlobalState.instance.add_symbol("#{current_scope_name}::#{node.name}", symbol)
          else
            range = [
              node.name_loc.start_line - 1,
              node.name_loc.start_column,
              node.name_loc.end_column
            ]

            @occurrences << Occurrence.new(
              range: range,
              symbol: symbol,
              symbol_roles: 1,
              syntax_kind: SyntaxKind::Identifier
            )

            unless GlobalState.instance.emitted?(symbol)
              @symbols << SymbolInformation.new(
                symbol: symbol,
                documentation: ["constant #{node.name}"],
                kind: SymbolInformation::Kind::Package # fallback
              )
              GlobalState.instance.mark_emitted(symbol)
            end
          end
          super
        end

        def visit_def_node(node)
          name = scip_name(node.name.to_s)
          suffix = @current_scope.empty? ? '' : '#'
          symbol = "#{@package_prefix}#{@current_scope.join("#")}#{suffix}#{name}."

          if @mode == :index
            # Register both qualified and simple name for speculative resolution
            GlobalState.instance.add_symbol("#{current_scope_name}##{node.name}", symbol)
            GlobalState.instance.add_symbol("##{node.name}", symbol)
          else
            range = [
              node.name_loc.start_line - 1,
              node.name_loc.start_column,
              node.name_loc.end_column
            ]

            @occurrences << Occurrence.new(
              range: range,
              symbol: symbol,
              symbol_roles: 1,
              syntax_kind: SyntaxKind::Identifier
            )

            unless GlobalState.instance.emitted?(symbol)
              @symbols << SymbolInformation.new(
                symbol: symbol,
                documentation: ["def #{node.name}"],
                kind: SymbolInformation::Kind::Method
              )
              GlobalState.instance.mark_emitted(symbol)
            end
          end
          super
        end

        def visit_constant_read_node(node)
          return if @mode == :index

          # Try to resolve constant
          symbol = GlobalState.instance.find_symbol(node.name.to_s, current_scope_name)
          if symbol
            range = [
              node.location.start_line - 1,
              node.location.start_column,
              node.location.end_column
            ]

            @occurrences << Occurrence.new(
              range: range,
              symbol: symbol,
              symbol_roles: 0, # Reference
              syntax_kind: SyntaxKind::Identifier
            )
          end
          super
        end

        def visit_constant_path_node(node)
          # Ensure we visit parts for better indexing
          super
        end

        def visit_call_node(node)
          return if @mode == :index

          # Skip common methods
          return super if %w[new puts p print].include?(node.name.to_s)

          # Speculative resolution
          symbol = GlobalState.instance.find_symbol("#{current_scope_name}##{node.name}", '') ||
            GlobalState.instance.find_symbol("##{node.name}", '')

          if symbol
            loc = node.message_loc || node.location
            range = [
              loc.start_line - 1,
              loc.start_column,
              loc.end_column
            ]

            @occurrences << Occurrence.new(
              range: range,
              symbol: symbol,
              symbol_roles: 0,
              syntax_kind: SyntaxKind::Identifier
            )
          end
          super
        end

        private

        def scip_name(name)
          # Escape names with special characters using backticks
          # Allowed: alphanumeric, -, +, $, _
          if /^[a-zA-Z0-9\-\+\$_]+$/.match?(name)
            name
          else
            "`#{name}`"
          end
        end

        def current_scope_name
          # This returns Ruby-style name for GlobalState mapping
          # We don't want escaped names here to keep mapping simple
          # Wait, I should probably store unescaped names in scope
          # Let's adjust visit_* to store unescaped and scip_name for symbol construction
          @current_scope.join('::').delete('`')
        end
      end
    end
  end
end
