# frozen_string_literal: true

module Hind
  module LSIF
    class GlobalState
      attr_accessor :project_id
      attr_reader :declarations, :references, :result_sets, :ranges

      def initialize
        @declarations = {}    # {qualified_name => {type:, node:, scope:, file:, range_id:, result_set_id:}}
        @references = {}      # {qualified_name => [{file:, range_id:, type:}, ...]}
        @result_sets = {}     # {qualified_name => result_set_id}
        @ranges = {}          # {file_path => [range_ids]}
        @project_id = nil
      end

      def add_declaration(qualified_name, data)
        @declarations[qualified_name] = data
        @result_sets[qualified_name] = data[:result_set_id] if data[:result_set_id]
      end

      def add_reference(qualified_name, file_path, range_id, document_id)
        @references[qualified_name] ||= []
        @references[qualified_name] << {
          file: file_path,
          range_id: range_id,
          document_id: document_id
        }
      end

      def add_range(file_path, range_id)
        @ranges[file_path] ||= []
        @ranges[file_path] << range_id
      end

      def has_declaration?(qualified_name)
        @declarations.key?(qualified_name)
      end

      def get_declaration(qualified_name)
        @declarations[qualified_name]
      end

      def get_references(qualified_name)
        @references[qualified_name] || []
      end

      def get_result_set(qualified_name)
        @result_sets[qualified_name]
      end

      def get_ranges_for_file(file_path)
        @ranges[file_path] || []
      end

      def find_constant_declaration(name, current_scope)
        return name if has_declaration?(name)

        if current_scope && !current_scope.empty?
          qualified_name = "#{current_scope}::#{name}"
          return qualified_name if has_declaration?(qualified_name)

          scope_parts = current_scope.split('::')
          while scope_parts.any?
            scope_parts.pop
            qualified_name = scope_parts.empty? ? name : "#{scope_parts.join("::")}::#{name}"
            return qualified_name if has_declaration?(qualified_name)
          end
        end

        has_declaration?(name) ? name : nil
      end

      def debug_info
        {
          declarations_count: @declarations.size,
          references_count: @references.values.sum(&:size),
          result_sets_count: @result_sets.size,
          ranges_count: @ranges.values.sum(&:size),
          declaration_types: declaration_types_count
        }
      end

      private

      def declaration_types_count
        @declarations.values.each_with_object(Hash.new(0)) do |decl, counts|
          counts[decl[:type]] += 1
        end
      end
    end
  end
end
