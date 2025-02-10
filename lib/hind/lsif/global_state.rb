# lib/hind/lsif/global_state.rb
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

        # Method visibility tracking
        @visibility_stack = [] # Stack of method visibility states per scope
        @current_visibility = :public
      end

      def add_declaration(qualified_name, data)
        @declarations[qualified_name] = data
        @result_sets[qualified_name] = data[:result_set_id] if data[:result_set_id]
      end

      def add_reference(qualified_name, file_path, range_id, type = :reference)
        @references[qualified_name] ||= []
        @references[qualified_name] << {
          file: file_path,
          range_id: range_id,
          type: type
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

      def push_visibility_scope(visibility = :public)
        @visibility_stack.push(@current_visibility)
        @current_visibility = visibility
      end

      def pop_visibility_scope
        @current_visibility = @visibility_stack.pop || :public
      end

      def current_visibility
        @current_visibility
      end

      def get_declaration_in_scope(name, scope)
        # Try exact scope first
        qualified_name = scope.empty? ? name : "#{scope}::#{name}"
        return qualified_name if has_declaration?(qualified_name)

        # Try parent scopes
        scope_parts = scope.split('::')
        while scope_parts.any?
          scope_parts.pop
          qualified_name = scope_parts.empty? ? name : "#{scope_parts.join('::')}::#{name}"
          return qualified_name if has_declaration?(qualified_name)
        end

        # Try top level
        has_declaration?(name) ? name : nil
      end

      def get_method_declaration(method_name, scope, instance_method = true)
        separator = instance_method ? '#' : '.'
        qualified_name = scope.empty? ? method_name : "#{scope}#{separator}#{method_name}"

        return qualified_name if has_declaration?(qualified_name)

        # For instance methods, try to find in superclass chain
        if instance_method && !scope.empty?
          current_scope = scope
          while (class_data = @declarations[current_scope])
            break unless class_data[:type] == :class && class_data[:superclass]

            superclass = class_data[:superclass]
            superclass_method = "#{superclass}#{separator}#{method_name}"
            return superclass_method if has_declaration?(superclass_method)

            current_scope = superclass
          end
        end

        nil
      end

      def find_constant_declaration(name, current_scope)
        return name if has_declaration?(name)

        # Try with current scope
        if current_scope && !current_scope.empty?
          qualified_name = "#{current_scope}::#{name}"
          return qualified_name if has_declaration?(qualified_name)

          # Try parent scopes
          scope_parts = current_scope.split('::')
          while scope_parts.any?
            scope_parts.pop
            qualified_name = scope_parts.empty? ? name : "#{scope_parts.join('::')}::#{name}"
            return qualified_name if has_declaration?(qualified_name)
          end
        end

        # Try top level
        has_declaration?(name) ? name : nil
      end

      def get_instance_variable_scope(var_name, current_scope)
        return nil unless current_scope
        "#{current_scope}##{var_name}"
      end

      def get_class_variable_scope(var_name, current_scope)
        return nil unless current_scope
        "#{current_scope}::#{var_name}"
      end

      def debug_info
        {
          declarations_count: @declarations.size,
          references_count: @references.values.sum(&:size),
          result_sets_count: @result_sets.size,
          ranges_count: @ranges.values.sum(&:size),
          declaration_types: declaration_types_count,
          reference_types: reference_types_count
        }
      end

      private

      def declaration_types_count
        @declarations.values.each_with_object(Hash.new(0)) do |decl, counts|
          counts[decl[:type]] += 1
        end
      end

      def reference_types_count
        @references.values.flatten.each_with_object(Hash.new(0)) do |ref, counts|
          counts[ref[:type]] += 1
        end
      end
    end
  end
end
