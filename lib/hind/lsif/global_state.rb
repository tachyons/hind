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
        @classes = {}     # {qualified_name => {definitions: [{node:, scope:, file:, range_id:, result_set_id:, superclass:}]}}
        @modules = {}     # {qualified_name => {definitions: [{node:, scope:, file:, range_id:, result_set_id:}]}}
        @constants = {}   # {qualified_name => {node:, scope:, file:, range_id:, result_set_id:, value:}}
        @references = {}  # {qualified_name => [{file:, range_id:, document_id:}, ...]}
        @ranges = {}      # {file_path => [range_ids]}
        @result_sets = {} # {qualified_name => result_set_id}
        @project_id = nil
      end

      def add_class(qualified_name, data)
        # Initialize if this is the first time we're seeing this class
        if !@classes.key?(qualified_name)
          @classes[qualified_name] = { definitions: [] }
        end

        # Add this definition to the list
        @classes[qualified_name][:definitions] << data

        # Update the result set ID (we'll use the one from the primary definition)
        primary_def = determine_primary_class_definition(qualified_name)
        @result_sets[qualified_name] = primary_def[:result_set_id] if primary_def && primary_def[:result_set_id]
      end

      def add_module(qualified_name, data)
        # Initialize if this is the first time we're seeing this module
        if !@modules.key?(qualified_name)
          @modules[qualified_name] = { definitions: [] }
        end

        # Add this definition to the list
        @modules[qualified_name][:definitions] << data

        # Update the result set ID (we'll use the one from the primary definition)
        primary_def = determine_primary_module_definition(qualified_name)
        @result_sets[qualified_name] = primary_def[:result_set_id] if primary_def && primary_def[:result_set_id]
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
        if @classes.key?(qualified_name)
          determine_primary_class_definition(qualified_name)
        elsif @modules.key?(qualified_name)
          determine_primary_module_definition(qualified_name)
        else
          @constants[qualified_name]
        end
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
          ranges_count: @ranges.values.sum(&:size),
          open_classes_count: @classes.count { |_, data| data[:definitions].size > 1 },
          open_modules_count: @modules.count { |_, data| data[:definitions].size > 1 }
        }
      end

      # Returns all definitions for a class
      def get_class_definitions(qualified_name)
        return [] unless @classes.key?(qualified_name)
        @classes[qualified_name][:definitions]
      end

      # Returns all definitions for a module
      def get_module_definitions(qualified_name)
        return [] unless @modules.key?(qualified_name)
        @modules[qualified_name][:definitions]
      end

      private

      # Determines the "primary" definition of a class
      def determine_primary_class_definition(qualified_name)
        return nil unless @classes.key?(qualified_name)

        definitions = @classes[qualified_name][:definitions]
        return nil if definitions.empty?

        # Priority rules for determining the primary definition:
        # 1. If there's a definition with a superclass, use that
        # 2. If there's a definition in a file with the same name as the class, use that
        # 3. If there's a definition in a file named after the module path, use that
        # 4. Fall back to the first definition

        # Rule 1: Check for definitions with a superclass
        with_superclass = definitions.select { |d| d[:superclass] }
        return with_superclass.first if with_superclass.any?

        # Rule 2 & 3: Check for definitions in files named after the class/module path
        class_name = qualified_name.split('::').last
        module_path = qualified_name.split('::')[0..-2].join('/')

        # Check for a file matching the full path
        full_path_match = definitions.find do |d|
          file_path = d[:file]
          basename = File.basename(file_path, File.extname(file_path))
          dirname = File.dirname(file_path)

          # Check if filename matches class name (case-insensitive and underscore/camelcase)
          filename_match = basename.downcase == class_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

          # Check if directory structure matches module path
          path_match = dirname.end_with?(module_path)

          filename_match && path_match
        end

        return full_path_match if full_path_match

        # Rule 4: Fall back to the first definition
        definitions.first
      end

      # Determines the "primary" definition of a module
      def determine_primary_module_definition(qualified_name)
        return nil unless @modules.key?(qualified_name)

        definitions = @modules[qualified_name][:definitions]
        return nil if definitions.empty?

        # Priority rules for determining the primary definition:
        # 1. If there's a definition in a file named directly after the module, use that
        # 2. If there's a definition in a file at the root of the module's path, use that
        # 3. Fall back to the first definition

        module_name = qualified_name.split('::').last
        parent_path = qualified_name.split('::')[0..-2].join('/')

        # Rule 1: Check for a file named directly after the module
        direct_match = definitions.find do |d|
          file_path = d[:file]
          basename = File.basename(file_path, File.extname(file_path))

          # Check if filename matches module name (case-insensitive and underscore/camelcase)
          basename.downcase == module_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end

        return direct_match if direct_match

        # Rule 2: Check for a definition at the root of the module's path
        root_match = definitions.find do |d|
          file_path = d[:file]
          parts = file_path.split('/')

          # Check if the file is at the module's path root
          parts.size == qualified_name.split('::').size &&
          parts.map(&:downcase).join('/') == qualified_name.gsub('::', '/').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end

        return root_match if root_match

        # Rule 3: Fall back to the first definition
        definitions.first
      end
    end
  end
end
