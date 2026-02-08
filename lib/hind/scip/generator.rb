require_relative 'scip_pb'
require_relative 'global_state'

module Hind
  module SCIP
    class Generator
      attr_reader :project_root, :documents

      def initialize(project_root)
        @project_root = project_root
        @documents = []
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

      def collect_definitions(relative_path)
        absolute_path = File.join(@project_root, relative_path)
        return unless File.exist?(absolute_path)

        source = File.read(absolute_path)
        result = Prism.parse(source)

        visitor = ScipVisitor.new(relative_path, { mode: :index, package_info: { name: 'hind', version: Hind::VERSION } })
        result.value.accept(visitor)
      end

      def process_file(relative_path)
        absolute_path = File.join(@project_root, relative_path)
        return unless File.exist?(absolute_path)

        source = File.read(absolute_path)
        result = Prism.parse(source)

        occurrences = []
        symbols = []
        
        visitor = ScipVisitor.new(relative_path, { mode: :emit, package_info: { name: 'hind', version: Hind::VERSION } })
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
          @package_prefix = "scip-ruby rubygems #{package_info[:name] || 'hind'} #{package_info[:version] || '0.1.0'} "
        end

        def visit_class_node(node)
          @current_scope.push(node.constant_path.slice)
          symbol = "#{@package_prefix}#{@current_scope.join('#')}#"
          
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

            @symbols << SymbolInformation.new(
              symbol: symbol,
              documentation: ["class #{node.constant_path.slice}"],
              kind: SymbolInformation::Kind::Class
            )
          end

          super
          @current_scope.pop
        end
        
        def visit_module_node(node)
          @current_scope.push(node.constant_path.slice)
          symbol = "#{@package_prefix}#{@current_scope.join('#')}#"
          
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

            @symbols << SymbolInformation.new(
              symbol: symbol,
              documentation: ["module #{node.constant_path.slice}"],
              kind: SymbolInformation::Kind::Module
            )
          end
          
          super
          @current_scope.pop
        end
        
        def visit_constant_write_node(node)
          symbol = "#{@package_prefix}#{@current_scope.join('#')}##{node.name}."
          
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
            
            @symbols << SymbolInformation.new(
              symbol: symbol,
              documentation: ["constant #{node.name}"],
              kind: SymbolInformation::Kind::Package # Or Kind::Constant if we had it, fallback to something
            )
          end
          super
        end

        def visit_def_node(node)
           symbol = "#{@package_prefix}#{@current_scope.join('#')}##{node.name}."
           
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

             @symbols << SymbolInformation.new(
               symbol: symbol,
               documentation: ["def #{node.name}"],
               kind: SymbolInformation::Kind::Method
             )
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
          symbol = GlobalState.instance.find_symbol("#{current_scope_name}##{node.name}", "") || 
                   GlobalState.instance.find_symbol("##{node.name}", "")

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

        def current_scope_name
          @current_scope.join('::')
        end
      end
    end
  end
end
