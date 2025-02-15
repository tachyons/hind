# frozen_string_literal: true

require 'prism'
require 'json'
require 'uri'
require 'pathname'

require_relative 'visitors/declaration_visitor'
require_relative 'visitors/reference_visitor'

module Hind
  module LSIF
    class Generator
      LSIF_VERSION = '0.4.3'

      attr_reader :metadata, :global_state, :document_id, :current_uri

      def initialize(metadata = {})
        @vertex_id = metadata[:vertex_id] || 1
        @metadata = {
          language: 'ruby',
          projectRoot: File.expand_path(metadata[:projectRoot] || Dir.pwd)
        }.merge(metadata)

        @global_state = GlobalState.new
        @document_ids = {}
        @current_document_id = nil
        @lsif_data = []
        @current_uri = nil
        @last_vertex_id = @vertex_id

        initialize_project if metadata[:initial]
      end

      def collect_declarations(files)
        files.each do |path, content|
          @current_uri = path
          @document_id = nil
          @current_document_id = nil

          begin
            ast = Parser.new(content).parse
            setup_document
            visitor = DeclarationVisitor.new(self, path)
            visitor.visit(ast)
            finalize_document_state
          rescue => e
            warn "Warning: Failed to collect declarations from '#{path}': #{e.message}"
          end
        end

        # Store the last used vertex ID and reset reference index
        @last_vertex_id = @vertex_id
        @last_reference_index = @lsif_data.length

        {
          declarations: @global_state.declarations,
          lsif_data: @lsif_data
        }
      end

      def process_file(params)
        @current_uri = params[:uri]
        content = params[:content]

        # Restore vertex ID from last declaration pass
        @vertex_id = @last_vertex_id

        @document_id = nil
        @current_document_id = nil

        setup_document
        ast = Parser.new(content).parse

        visitor = ReferenceVisitor.new(self, @current_uri)
        visitor.visit(ast)

        finalize_document_state

        # Update last vertex ID
        @last_vertex_id = @vertex_id

        # Return only the new LSIF data since last call
        result = @lsif_data[@last_reference_index..]
        @last_reference_index = @lsif_data.length
        result
      end

      def get_initial_data
        @initial_data
      end

      def register_declaration(declaration)
        return unless @current_uri && declaration[:node]

        qualified_name = declaration[:name]

        setup_document if @document_id.nil?
        current_doc_id = @document_id

        range_id = if declaration[:type] == :constant_write
          create_range(declaration[:node].name_loc)
        elsif declaration[:type] == :module
          create_range(declaration[:node].module_keyword_loc)
        elsif declaration[:type] == :class
          create_range(declaration[:node].constant_path.location)
        else
          create_range(declaration[:node].location)
        end
        return unless range_id

        result_set_id = emit_vertex('resultSet')
        emit_edge('next', range_id, result_set_id)

        def_result_id = emit_vertex('definitionResult')
        emit_edge('textDocument/definition', result_set_id, def_result_id)

        emit_edge('item', def_result_id, [range_id], 'definitions', current_doc_id)

        hover_content = generate_hover_content(declaration)
        hover_id = emit_vertex('hoverResult', {
          contents: [{
            language: 'ruby',
            value: hover_content
          }]
        })
        emit_edge('textDocument/hover', result_set_id, hover_id)

        @global_state.add_declaration(qualified_name, {
          type: declaration[:type],
          scope: declaration[:scope],
          file: @current_uri,
          range_id: range_id,
          result_set_id: result_set_id,
          document_id: current_doc_id
        }.merge(declaration))

        result_set_id
      end

      def register_reference(reference)
        return unless @current_uri && reference[:node]
        return unless @global_state.has_declaration?(reference[:name])

        setup_document if @document_id.nil?
        current_doc_id = @document_id

        range_id = create_range(reference[:node].location)
        return unless range_id

        declaration = @global_state.declarations[reference[:name]]
        return unless declaration[:result_set_id]

        @global_state.add_reference(reference[:name], @current_uri, range_id, current_doc_id)
        emit_edge('next', range_id, declaration[:result_set_id])
      end

      private

      def initialize_project
        emit_vertex('metaData', {
          version: LSIF_VERSION,
          projectRoot: path_to_uri(@metadata[:projectRoot]),
          positionEncoding: 'utf-16',
          toolInfo: {
            name: 'hind',
            version: Hind::VERSION
          }
        })

        @global_state.project_id = emit_vertex('project', {kind: 'ruby'})
      end

      def setup_document
        return if @document_id
        return unless @current_uri

        file_path = File.join(@metadata[:projectRoot], @current_uri)

        @document_id = emit_vertex('document', {
          uri: path_to_uri(file_path),
          languageId: 'ruby'
        })

        @document_ids[@current_uri] = @document_id
        @current_document_id = @document_id

        emit_edge('contains', @global_state.project_id, [@document_id]) if @global_state.project_id
      end

      def finalize_document_state
        return unless @current_uri && @document_id

        ranges = @global_state.get_ranges_for_file(@current_uri)
        if ranges&.any?
          emit_edge('contains', @document_id, ranges, nil, @document_id)
        end
      end

      def create_range(location)
        return nil unless @current_uri && location

        range_id = emit_vertex('range', {
          start: {
            line: location.start_line - 1, # Convert from 1-based to 0-based numbering
            character: location.start_column
          },
          end: {
            line: location.end_line - 1,
            character: location.end_column
          }
        })

        @global_state.add_range(@current_uri, range_id)
        range_id
      end

      def emit_vertex(label, data = nil)
        vertex = {
          id: @vertex_id,
          type: 'vertex',
          label: label
        }

        if data
          if %w[hoverResult definitionResult referenceResult].include?(label)
            vertex[:result] = format_hover_data(data)
          else
            vertex.merge!(data)
          end
        end

        @lsif_data << vertex
        @vertex_id += 1
        @vertex_id - 1
      end

      def emit_edge(label, out_v, in_v, property = nil, doc_id = nil)
        return unless out_v && valid_in_v?(in_v)

        edge = {
          id: @vertex_id,
          type: 'edge',
          label: label,
          outV: out_v
        }

        if in_v.is_a?(Array)
          edge[:inVs] = in_v
        else
          edge[:inV] = in_v
        end

        if label == 'item'
          edge[:document] = doc_id || @current_document_id
          edge[:property] = property if property
        end

        @lsif_data << edge
        @vertex_id += 1
        @vertex_id - 1
      end

      def generate_hover_content(declaration)
        case declaration[:type]
        when :class
          hover = ["class #{declaration[:name]}"]
          hover << " < #{declaration[:superclass]}" if declaration[:superclass]
          hover.join
        when :module
          "module #{declaration[:name]}"
        when :constant
          value_info = declaration[:node].value.respond_to?(:content) ? " = #{declaration[:node].value.content}" : ''
          "#{declaration[:name]}#{value_info}"
        else
          declaration[:name].to_s
        end
      end

      def format_hover_data(data)
        return data unless data[:contents]

        data[:contents] = data[:contents].map do |content|
          content[:value] = strip_code_block(content[:value])
          content
        end
        data
      end

      def strip_code_block(text)
        text.gsub(/```.*\n?/, '').strip
      end

      def valid_in_v?(in_v)
        return false unless in_v
        return in_v.any? if in_v.is_a?(Array)
        true
      end

      def path_to_uri(path)
        return nil unless path
        normalized_path = path.tr('\\', '/')
        normalized_path = normalized_path.sub(%r{^file://}, '')
        absolute_path = File.expand_path(normalized_path)
        "file://#{absolute_path}"
      end
    end
  end
end
