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
        @lsif_data = []
        @current_uri = nil

        initialize_project if metadata[:initial]
      end

      def collect_declarations(files)
        files.each do |path, content|
          @current_uri = path
          ast = Parser.new(content).parse
          visitor = DeclarationVisitor.new(self, path)
          visitor.visit(ast)
        end

        { declarations: @global_state.declarations }
      end

      def process_file(params)
        content = params[:content]
        @current_uri = params[:uri]

        setup_document
        ast = Parser.new(content).parse

        # Process declarations first to update any missing ones
        visitor = DeclarationVisitor.new(self, @current_uri)
        visitor.visit(ast)

        # Then process references
        visitor = ReferenceVisitor.new(self, @current_uri)
        visitor.visit(ast)

        finalize_document
        @lsif_data
      end

      def register_declaration(declaration)
        return unless @current_uri && declaration[:node]

        qualified_name = declaration[:name]
        range_id = create_range(declaration[:node].location, declaration[:node].location)
        return unless range_id

        result_set_id = emit_vertex('resultSet')
        emit_edge('next', range_id, result_set_id)

        def_result_id = emit_vertex('definitionResult')
        emit_edge('textDocument/definition', result_set_id, def_result_id)
        emit_edge('item', def_result_id, [range_id], 'definitions')

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
          result_set_id: result_set_id
        }.merge(declaration))
      end

      def register_reference(reference)
        return unless @current_uri && reference[:node]
        return unless @global_state.has_declaration?(reference[:name])

        range_id = create_range(reference[:node].location, reference[:node].location)
        return unless range_id

        declaration = @global_state.declarations[reference[:name]]
        @global_state.add_reference(reference[:name], @current_uri, range_id)
        emit_edge('next', range_id, declaration[:result_set_id])
      end

      def finalize_cross_references
        cross_ref_data = []

        @global_state.references.each do |qualified_name, references|
          declaration = @global_state.declarations[qualified_name]
          next unless declaration

          result_set_id = declaration[:result_set_id]
          next unless result_set_id

          ref_result_id = emit_vertex('referenceResult')
          emit_edge('textDocument/references', result_set_id, ref_result_id)

          # Collect all reference range IDs
          all_refs = references.map { |ref| ref[:range_id] }
          all_refs << declaration[:range_id] if declaration[:range_id]

          # Group references by document
          references.group_by { |ref| ref[:file] }.each do |file_path, file_refs|
            document_id = @document_ids[file_path]
            next unless document_id

            cross_ref_data << {
              id: @vertex_id,
              type: 'edge',
              label: 'item',
              outV: ref_result_id,
              inVs: all_refs,
              document: document_id,
              property: 'references'
            }
            @vertex_id += 1
          end

          # Handle document containing the definition
          def_file = declaration[:file]
          def_document_id = @document_ids[def_file]
          if def_document_id && references.none? { |ref| ref[:file] == def_file }
            cross_ref_data << {
              id: @vertex_id,
              type: 'edge',
              label: 'item',
              outV: ref_result_id,
              inVs: all_refs,
              document: def_document_id,
              property: 'references'
            }
            @vertex_id += 1
          end
        end

        cross_ref_data
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

        @global_state.project_id = emit_vertex('project', { kind: 'ruby' })
      end

      def setup_document
        return unless @current_uri

        file_path = File.join(@metadata[:projectRoot], @current_uri)

        @document_id = emit_vertex('document', {
          uri: path_to_uri(file_path),
          languageId: 'ruby'
        })
        @document_ids[@current_uri] = @document_id

        emit_edge('contains', @global_state.project_id, [@document_id]) if @global_state.project_id
      end

      def finalize_document
        return unless @current_uri

        ranges = @global_state.get_ranges_for_file(@current_uri)
        if ranges&.any?
          emit_edge('contains', @document_id, ranges)
        end
      end

      def create_range(start_location, end_location)
        return nil unless @current_uri && start_location && end_location

        range_id = emit_vertex('range', {
          start: {
            line: start_location.start_line - 1,
            character: start_location.start_column
          },
          end: {
            line: end_location.end_line - 1,
            character: end_location.end_column
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

      def emit_edge(label, out_v, in_v, property = nil)
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

        edge[:document] = @document_id if label == 'item'
        edge[:property] = property if property

        @lsif_data << edge
        @vertex_id += 1
        @vertex_id - 1
      end

      def generate_hover_content(declaration)
        case declaration[:type]
        when :method
          sig = []
          sig << "def #{declaration[:name]}"
          sig << "(#{declaration[:params]})" if declaration[:params]
          sig.join
        when :class
          hover = ["class #{declaration[:name]}"]
          hover << " < #{declaration[:superclass]}" if declaration[:superclass]
          hover.join
        when :module
          "module #{declaration[:name]}"
        when :constant
          "#{declaration[:name]} = ..."
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
        normalized_path = path.gsub('\\', '/')
        normalized_path = normalized_path.sub(%r{^file://}, '')
        absolute_path = File.expand_path(normalized_path)
        "file://#{absolute_path}"
      end
    end
  end
end
