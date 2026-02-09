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
        target_node = node.constant_path
        target_node = target_node.child while target_node.is_a?(Prism::ConstantPathNode)

        @generator.register_class_declaration({
          type: :class,
          name: class_name,
          node: node,
          range_location: target_node.location,
          scope: @current_scope[0..-2].join('::'),
          superclass: node.superclass&.slice
        })
        super
        @current_scope.pop
      end

      def visit_module_node(node)
        @current_scope.push(node.constant_path.slice)
        module_name = current_scope_name
        target_node = node.constant_path
        target_node = target_node.child while target_node.is_a?(Prism::ConstantPathNode)

        @generator.register_module_declaration({
          type: :module,
          name: module_name,
          node: node,
          range_location: target_node.location,
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

      def visit_def_node(node)
        method_name = node.name.to_s
        qualified_name = @current_scope.empty? ? "##{method_name}" : "#{current_scope_name}##{method_name}"
        
        @generator.register_method_declaration({
          type: :method,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })
        super
      end

      def visit_call_node(node)
        # Handle attr_accessor, attr_reader, attr_writer
        if node.receiver.nil? && %w[attr_reader attr_writer attr_accessor].include?(node.name.to_s)
          helpers = node.arguments&.arguments || []
          helpers.each do |arg|
            next unless arg.is_a?(Prism::SymbolNode)
            
            name = arg.value
            if %w[attr_reader attr_accessor].include?(node.name.to_s)
              # Getter
              qualified_name = @current_scope.empty? ? "##{name}" : "#{current_scope_name}##{name}"
              @generator.register_method_declaration({
                type: :method,
                name: qualified_name,
                node: arg, # Use symbol node as the 'def' site
                scope: current_scope_name
              })
            end

            if %w[attr_writer attr_accessor].include?(node.name.to_s)
              # Setter
              setter_name = "#{name}="
              qualified_name = @current_scope.empty? ? "##{setter_name}" : "#{current_scope_name}##{setter_name}"
              @generator.register_method_declaration({
                type: :method,
                name: qualified_name,
                node: arg,
                scope: current_scope_name
              })
            end
          end
        end
        super
      end

      private

      def current_scope_name
        @current_scope.join('::')
      end
    end
  end
end
