# lib/hind/lsif/visitors/reference_visitor.rb
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

      # Method calls
      def visit_call_node(node)
        return unless node.name && node.location

        method_name = node.name.to_s
        qualified_names = generate_qualified_names_for_call(node)

        qualified_names.each do |qualified_name|
          @generator.register_reference({
            type: :method,
            name: qualified_name,
            node: node,
            scope: current_scope_name,
            call_type: :instance_method
          })
        end

        super
      end

      # Class/module references
      def visit_constant_read_node(node)
        return unless node.name

        constant_name = node.name.to_s
        qualified_name = @current_scope.empty? ? constant_name : "#{current_scope_name}::#{constant_name}"

        @generator.register_reference({
          type: :constant,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })

        super
      end

      # Constant path references (e.g., A::B::C)
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

      # Instance variable references
      def visit_instance_variable_read_node(node)
        return unless node.name && current_scope_name

        var_name = node.name.to_s
        qualified_name = "#{current_scope_name}##{var_name}"

        @generator.register_reference({
          type: :instance_variable,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })

        super
      end

      # Class variable references
      def visit_class_variable_read_node(node)
        return unless node.name && current_scope_name

        var_name = node.name.to_s
        qualified_name = "#{current_scope_name}::#{var_name}"

        @generator.register_reference({
          type: :class_variable,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })

        super
      end

      # Singleton method calls (class methods)
      def visit_constant_path_call_node(node)
        return unless node.name

        method_name = node.name.to_s
        receiver_name = node.receiver.slice
        qualified_name = "#{receiver_name}.#{method_name}"

        @generator.register_reference({
          type: :method,
          name: qualified_name,
          node: node,
          scope: current_scope_name,
          call_type: :class_method
        })

        super
      end

      # Super method calls
      def visit_super_node(node)
        return unless current_scope_name

        # Extract current method name from scope
        current_method = current_method_name
        return unless current_method

        # Try to find the superclass method
        if in_class_scope?
          superclass = find_superclass
          if superclass
            qualified_name = "#{superclass}##{current_method}"

            @generator.register_reference({
              type: :method,
              name: qualified_name,
              node: node,
              scope: current_scope_name,
              call_type: :super
            })
          end
        end

        super
      end

      # Track class/module scope
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

      def generate_qualified_names_for_call(node)
        qualified_names = []
        method_name = node.name.to_s

        # Try with current scope first
        qualified_names << "#{current_scope_name}##{method_name}" unless current_scope_name.empty?

        # Try with receiver's type if available
        if node.receiver
          case node.receiver
          when Prism::ConstantReadNode
            qualified_names << "#{node.receiver.name}##{method_name}"
          when Prism::ConstantPathNode
            qualified_names << "#{node.receiver.slice}##{method_name}"
          when Prism::CallNode
            # Method chaining - try both instance and class methods
            if node.receiver.name
              qualified_names << "#{node.receiver.name}##{method_name}"
              qualified_names << "#{node.receiver.name}.#{method_name}"
            end
          when Prism::InstanceVariableReadNode
            # Instance variable calls - try current class context
            qualified_names << "#{current_scope_name}##{method_name}" if current_scope_name
          end
        end

        # Try as a standalone method
        qualified_names << method_name

        # Add potential class method variant
        qualified_names << "#{current_scope_name}.#{method_name}" unless current_scope_name.empty?

        qualified_names.uniq
      end

      def current_method_name
        # Try to find the nearest method node in the AST
        # This is a simplified version - you might need to enhance this
        # based on your specific needs
        "current_method"
      end

      def in_class_scope?
        # Check if we're currently in a class definition
        !@current_scope.empty? && @generator.global_state.declarations[@current_scope.last]&.[](:type) == :class
      end

      def find_superclass
        return unless in_class_scope?

        current_class = @current_scope.last
        class_declaration = @generator.global_state.declarations[current_class]
        class_declaration&.[](:superclass)
      end
    end
  end
end
