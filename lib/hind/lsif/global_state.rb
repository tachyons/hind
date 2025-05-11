# frozen_string_literal: true
require 'singleton'

module Hind
  module LSIF
    class GlobalState
      include Singleton

      attr_accessor :project_id
      attr_reader :classes, :modules, :constants, :ranges, :references, :result_sets

      def initialize
        reset
      end

      def reset
        @classes = {}     # {qualified_name => {node:, scope:, file:, range_id:, result_set_id:, superclass:}}
        @modules = {}     # {qualified_name => {node:, scope:, file:, range_id:, result_set_id:}}
        @constants = {}   # {qualified_name => {node:, scope:, file:, range_id:, result_set_id:, value:}}
        @references = {}  # {qualified_name => [{file:, range_id:, document_id:}, ...]}
        @ranges = {}      # {file_path => [range_ids]}
        @result_sets = {} # {qualified_name => result_set_id}
        @project_id = nil
      end

      def add_class(qualified_name, data)
        @classes[qualified_name] = data
        @result_sets[qualified_name] = data[:result_set_id] if data[:result_set_id]
      end

      def add_module(qualified_name, data)
        @modules[qualified_name] = data
        @result_sets[qualified_name] = data[:result_set_id] if data[:result_set_id]
      end

      def add_constant(qualified_name, data)
        @constants[qualified_name] = data
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
        @classes.key?(qualified_name) ||
        @modules.key?(qualified_name) ||
        @constants.key?(qualified_name)
      end

      def get_declaration(qualified_name)
        @classes[qualified_name] || @modules[qualified_name] || @constants[qualified_name]
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
        # First check if the name exists exactly as provided
        return name if has_declaration?(name)

        return nil unless current_scope && !current_scope.empty?

        # Try with the full current scope
        qualified_name = "#{current_scope}::#{name}"
        return qualified_name if has_declaration?(qualified_name)

        # Try with parent scopes by progressively removing the innermost scope
        scope_parts = current_scope.split('::')
        while scope_parts.size > 0
          scope_parts.pop
          current_scope = scope_parts.join('::')

          # For empty scope, just check the name directly
          qualified_name = current_scope.empty? ? name : "#{current_scope}::#{name}"
          return qualified_name if has_declaration?(qualified_name)
        end

        # Not found in any scope
        nil
      end

      def debug_info
        {
          classes_count: @classes.size,
          modules_count: @modules.size,
          constants_count: @constants.size,
          references_count: @references.values.sum(&:size),
          result_sets_count: @result_sets.size,
          ranges_count: @ranges.values.sum(&:size)
        }
      end
    end
  end
end
