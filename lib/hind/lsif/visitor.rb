module Hind
  module LSIF
    class Visitor
      def initialize(generator)
        @generator = generator
        @current_scope = []
      end

      def visit(node)
        return unless node

        method_name = "visit_#{node.class.name.split('::').last.downcase}"
        if respond_to?(method_name)
          send(method_name, node)
        else
          visit_children(node)
        end
      end

      def visit_children(node)
        node.child_nodes.each { |child| visit(child) if child }
      end

      def visit_defnode(node)
        method_name = node.name.to_s
        qualified_name = current_scope_name.empty? ? method_name : "#{current_scope_name}##{method_name}"

        range_id = @generator.create_range(node.location, node.location)
        result_set_id = @generator.emit_vertex('resultSet')
        @generator.emit_edge('next', range_id, result_set_id)

        def_result_id = @generator.emit_vertex('definitionResult')
        @generator.emit_edge('textDocument/definition', result_set_id, def_result_id)
        @generator.emit_edge('item', def_result_id, [range_id], 'definitions')

        # Add hover information
        sig = []
        sig << "def #{qualified_name}"
        sig << "(#{node.parameters.slice})" if node.parameters

        hover_id = @generator.emit_vertex('hoverResult', {
          contents: [{
            language: 'ruby',
            value: sig.join
          }]
        })
        @generator.emit_edge('textDocument/hover', result_set_id, hover_id)

        @generator.add_to_global_state(qualified_name, result_set_id, range_id)

        visit_children(node)
      end

      # Additional visitor methods...

      private

      def current_scope_name
        @current_scope.join('::')
      end
    end
  end
end
