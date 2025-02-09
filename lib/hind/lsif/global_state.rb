module Hind
  module LSIF
    class GlobalState
      attr_reader :result_sets, :definitions, :references, :ranges
      attr_accessor :project_id

      def initialize
        @result_sets = {}  # {qualified_name => result_set_id}
        @definitions = {}  # {qualified_name => {file: file_path, range_id: id}}
        @references = {}   # {qualified_name => [{file: file_path, range_id: id}]}
        @ranges = {}       # {file_path => [range_ids]}
        @project_id = nil  # Store project ID for reuse across files
      end

      def add_range(file_path, range_id)
        @ranges[file_path] ||= []
        @ranges[file_path] << range_id
      end

      def add_definition(qualified_name, file_path, range_id)
        @definitions[qualified_name] = { file: file_path, range_id: range_id }
      end

      def add_reference(qualified_name, file_path, range_id)
        @references[qualified_name] ||= []
        @references[qualified_name] << { file: file_path, range_id: range_id }
      end
    end
  end
end
