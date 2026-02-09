# frozen_string_literal: true

module Hind
  module LSIF
    class DeclarationVisitor < Prism::Visitor
      attr_reader :current_scope

      def initialize(generator, file_path)
        @generator = generator
        @file_path = file_path
        @current_scope = []
      end

      def visit_class_node(node)
        @current_scope.push(node.constant_path.slice)
        class_name = current_scope_name
        @generator.register_class_declaration({
          type: :class,
          name: class_name,
          node: node,
          scope: @current_scope[0..-2].join('::'),
          superclass: node.superclass&.slice
        })
        super
        @current_scope.pop
      end

      def visit_module_node(node)
        @current_scope.push(node.constant_path.slice)
        module_name = current_scope_name
        @generator.register_module_declaration({
          type: :module,
          name: module_name,
          node: node,
          scope: @current_scope[0..-2].join('::')
        })
        super
        @current_scope.pop
      end

      def visit_constant_write_node(node)
        return unless node.name
        constant_name = node.name.to_s
        qualified_name = @current_scope.empty? ? constant_name : "#{current_scope_name}::#{constant_name}"
        @generator.register_constant_declaration({
          type: :constant,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })
        super
      end

      private

      def current_scope_name
        @current_scope.join('::')
      end
    end
  end
end
