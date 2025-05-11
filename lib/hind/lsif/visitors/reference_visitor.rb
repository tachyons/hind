# frozen_string_literal: true
module Hind
  module LSIF
    class ReferenceVisitor < Prism::Visitor
      attr_reader :current_scope

      def initialize(generator, file_path)
        @generator = generator
        @file_path = file_path
        @current_scope = []
      end

      def visit_constant_read_node(node)
        return unless node.name
        constant_name = node.name.to_s
        qualified_name = @current_scope.empty? ? constant_name : "#{current_scope_name}::#{constant_name}"

        # Try to find the correct declaration considering the scope
        found_name = GlobalState.instance.find_constant_declaration(constant_name, current_scope_name)

        if found_name
          @generator.register_reference({
            type: :constant,
            name: found_name,
            node: node,
            scope: current_scope_name
          })
        else
          # Register with the qualified name if not found - it might be defined later
          @generator.register_reference({
            type: :constant,
            name: qualified_name,
            node: node,
            scope: current_scope_name
          })
        end

        super
      end

      def visit_constant_path_node(node)
        qualified_name = node.slice
        @generator.register_reference({
          type: :constant,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })
        super
      end

      def visit_class_node(node)
        @current_scope.push(node.constant_path.slice)
        super
        @current_scope.pop
      end

      def visit_module_node(node)
        @current_scope.push(node.constant_path.slice)
        super
        @current_scope.pop
      end

      private

      def current_scope_name
        @current_scope.join('::')
      end
    end
  end
end
