# frozen_string_literal: true

require 'prism'
require 'json'
require 'uri'

module Hind
  module LSIF
    class Generator
      LSIF_VERSION = '0.4.3'

      attr_reader :global_state, :document_id, :metadata

      def initialize(metadata = {}, global_state = nil)
        @vertex_id = metadata[:vertex_id] || 1
        @metadata = {
          language: 'ruby',
          projectRoot: Dir.pwd
        }.merge(metadata)

        @global_state = global_state || GlobalState.new
        @document_ids = {}
        @lsif_data = []

        initialize_project if metadata[:initial]
      end

      def generate(code, file_metadata = {})
        @metadata = @metadata.merge(file_metadata)
        setup_document

        ast = Parser.new(code).parse
        visitor = Visitor.new(self)
        visitor.visit(ast)

        finalize_document
        update_cross_file_references

        @lsif_data
      end

      def create_range(start_location, end_location)
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

        file_path = File.join(@metadata[:projectRoot], @metadata[:uri])
        @global_state.add_range(file_path, range_id)
        range_id
      end

      def emit_vertex(label, data = nil)
        vertex = Vertex.new(@vertex_id, label, data)
        @lsif_data << vertex.to_json
        @vertex_id += 1
        @vertex_id - 1
      end

      def emit_edge(label, out_v, in_v, property = nil)
        return unless out_v && valid_in_v?(in_v)

        edge = Edge.new(@vertex_id, label, out_v, in_v, property, edge_document(label))
        @lsif_data << edge.to_json
        @vertex_id += 1
        @vertex_id - 1
      end

      def add_to_global_state(qualified_name, result_set_id, range_id)
        file_path = File.join(@metadata[:projectRoot], @metadata[:uri])
        @global_state.result_sets[qualified_name] = result_set_id
        @global_state.add_definition(qualified_name, file_path, range_id)
      end

      private

      def initialize_project
        emit_vertex('metaData', {
          version: LSIF_VERSION,
          projectRoot: path_to_uri(@metadata[:projectRoot]),
          positionEncoding: 'utf-16',
          toolInfo: {
            name: 'hind',
            version: VERSION
          }
        })

        @global_state.project_id = emit_vertex('project', { kind: 'ruby' })
      end

      def setup_document
        file_path = File.join(@metadata[:projectRoot], @metadata[:uri])

        @document_id = emit_vertex('document', {
          uri: path_to_uri(file_path),
          languageId: 'ruby'
        })
        @document_ids[file_path] = @document_id

        emit_edge('contains', @global_state.project_id, [@document_id]) if @global_state.project_id
      end

      def finalize_document
        file_path = File.join(@metadata[:projectRoot], @metadata[:uri])
        ranges = @global_state.ranges[file_path]

        if ranges&.any?
          emit_edge('contains', @document_id, ranges)
        end
      end

      def update_cross_file_references
        @global_state.references.each do |qualified_name, references|
          definition = @global_state.definitions[qualified_name]
          next unless definition

          result_set_id = @global_state.result_sets[qualified_name]
          next unless result_set_id

          ref_result_id = emit_vertex('referenceResult')
          emit_edge('textDocument/references', result_set_id, ref_result_id)

          # Collect all reference range IDs
          all_refs = references.map { |ref| ref[:range_id] }
          all_refs << definition[:range_id]

          # Group references by document
          reference_documents = references.group_by { |ref| ref[:file] }
          reference_documents.each_key do |file_path|
            document_id = @document_ids[file_path]
            next unless document_id

            emit_edge('item', ref_result_id, all_refs, 'references')
          end

          # Handle definition document if not already included
          def_document_id = @document_ids[definition[:file]]
          if def_document_id && references.none? { |ref| ref[:file] == definition[:file] }
            emit_edge('item', ref_result_id, all_refs, 'references')
          end
        end
      end

      def valid_in_v?(in_v)
        return false unless in_v
        return in_v.any? if in_v.is_a?(Array)
        true
      end

      def edge_document(label)
        label == 'item' ? @document_id : nil
      end

      def path_to_uri(path)
        normalized_path = path.gsub('\\', '/')
        normalized_path = normalized_path.sub(%r{^file://}, '')
        absolute_path = File.expand_path(normalized_path)
        "file://#{absolute_path}"
      end

      def make_hover_content(text)
        {
          contents: [{
            language: 'ruby',
            value: strip_code_block(text)
          }]
        }
      end

      def strip_code_block(text)
        # Strip any existing code block markers and normalize
        text.gsub(/```.*\n?/, '').strip
      end
    end
  end
end
