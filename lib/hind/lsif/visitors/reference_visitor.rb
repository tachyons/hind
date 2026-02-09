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
        # Skip creating a range for the whole path to avoid overlaps with parts.
        # Instead, just visit the components (parent and child).
        super
      end

      def visit_class_node(node)
        @current_scope.push(scip_name(node.constant_path.slice))
        super
        @current_scope.pop
      end

      def visit_module_node(node)
        @current_scope.push(scip_name(node.constant_path.slice))
        super
        @current_scope.pop
      end

      def visit_def_node(node)
        # We don't push def to current_scope because methods are usually inside classes/modules
        # and we use #method notation. Pushing 'method' to scope would result in A::B#method#submethod
        # which is not standard for Ruby normally unless we handle nested blocks.
        # But for now, let's just visit.
        super
      end

      def visit_call_node(node)
        # Speculative resolution for method calls
        method_name = node.name.to_s
        
        # Try both qualified and simple name
        # We search for #method_name
        found_name = GlobalState.instance.find_declaration("##{method_name}", current_scope_name)
        
        if found_name
          loc = node.message_loc || node.location
          @generator.register_reference({
            type: :method,
            name: found_name,
            node: node,
            location: loc # Use just the message/method name location for the reference range
          })
        end
        super
      end

      private

      def scip_name(name)
        # Basic unescaping to match what we store in GlobalState keys if needed
        # We store them unescaped in scope normally or with backticks if scip_name was used.
        # Let's be consistent.
        name.delete('`')
      end

      def current_scope_name
        @current_scope.join('::')
      end
    end
  end
end
