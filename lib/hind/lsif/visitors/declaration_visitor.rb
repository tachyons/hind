# lib/hind/lsif/visitors/declaration_visitor.rb
# frozen_string_literal: true

module Hind
  module LSIF
    class DeclarationVisitor < Prism::Visitor
      attr_reader :current_scope

      def initialize(generator, file_path)
        @generator = generator
        @file_path = file_path
        @current_scope = []
        @current_visibility = :public
        @visibility_stack = []
        @in_singleton_class = false
      end

      def visit_class_node(node)
        @current_scope.push(node.constant_path.slice)
        class_name = current_scope_name

        # Register class declaration
        @generator.register_declaration({
          type: :class,
          name: class_name,
          node: node,
          scope: @current_scope[0..-2].join('::'),
          superclass: node.superclass&.slice
        })

        # Process the class body with proper scope and visibility
        push_visibility(:public)
        super
        pop_visibility
        @current_scope.pop
      end

      def visit_module_node(node)
        @current_scope.push(node.constant_path.slice)
        module_name = current_scope_name

        @generator.register_declaration({
          type: :module,
          name: module_name,
          node: node,
          scope: @current_scope[0..-2].join('::')
        })

        push_visibility(:public)
        super
        pop_visibility
        @current_scope.pop
      end

      def visit_def_node(node)
        method_name = node.name.to_s
        # Use '#' for instance methods
        qualified_name = @in_singleton_class ?
          "#{current_scope_name}.#{method_name}" :
          "#{current_scope_name}##{method_name}"

        @generator.register_declaration({
          type: :method,
          name: qualified_name,
          node: node,
          scope: current_scope_name,
          visibility: current_visibility,
          params: node.parameters&.slice,
          instance_method: !@in_singleton_class
        })

        super
      end

      def visit_constant_write_node(node)
        return unless node.name

        constant_name = node.name.to_s
        qualified_name = @current_scope.empty? ? constant_name : "#{current_scope_name}::#{constant_name}"

        @generator.register_declaration({
          type: :constant,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })

        super
      end

      def visit_singleton_class_node(node)
        if node.expression.is_a?(Prism::SelfNode)
          # class << self
          @in_singleton_class = true
          super
          @in_singleton_class = false
        else
          # Process regular singleton class
          super
        end
      end

      def visit_call_node(node)
        method_name = node.name.to_s
        case method_name
        when 'private', 'protected', 'public'
          handle_visibility_method(node)
        when 'attr_reader', 'attr_writer', 'attr_accessor'
          handle_attribute_method(node)
        end

        super
      end

      def visit_class_variable_write_node(node)
        return unless node.name

        var_name = node.name.to_s
        qualified_name = "#{current_scope_name}::#{var_name}"

        @generator.register_declaration({
          type: :class_variable,
          name: qualified_name,
          node: node,
          scope: current_scope_name
        })

        super
      end

      def visit_instance_variable_write_node(node)
        return unless node.name && current_scope_name

        var_name = node.name.to_s
        qualified_name = "#{current_scope_name}##{var_name}"

        @generator.register_declaration({
          type: :instance_variable,
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

      def current_visibility
        @current_visibility
      end

      def push_visibility(visibility)
        @visibility_stack.push(@current_visibility)
        @current_visibility = visibility
      end

      def pop_visibility
        @current_visibility = @visibility_stack.pop || :public
      end

      def handle_visibility_method(node)
        visibility = node.name.to_sym

        if node.arguments&.arguments&.empty?
          # Global visibility change
          @current_visibility = visibility
        elsif node.arguments
          # Per-method visibility change
          node.arguments.arguments.each do |arg|
            next unless arg.is_a?(Prism::SymbolNode) || arg.is_a?(Prism::StringNode)

            method_name = arg.value.to_s
            qualified_name = "#{current_scope_name}##{method_name}"

            if @generator.global_state.has_declaration?(qualified_name)
              @generator.global_state.get_declaration(qualified_name)[:visibility] = visibility
            end
          end
        end
      end

      def handle_attribute_method(node)
        return unless node.arguments

        attr_type = node.name.to_s
        node.arguments.arguments.each do |arg|
          next unless arg.respond_to?(:value)

          attr_name = arg.value.to_s
          register_attribute(attr_name, attr_type)
        end
      end

      def register_attribute(attr_name, attr_type)
        base_name = "#{current_scope_name}##{attr_name}"

        # Register reader method if applicable
        if %w[attr_reader attr_accessor].include?(attr_type)
          @generator.register_declaration({
            type: :method,
            name: base_name,
            node: nil, # Synthetic node
            scope: current_scope_name,
            visibility: current_visibility,
            synthetic: true,
            kind: :reader
          })
        end

        # Register writer method if applicable
        if %w[attr_writer attr_accessor].include?(attr_type)
          @generator.register_declaration({
            type: :method,
            name: "#{base_name}=",
            node: nil, # Synthetic node
            scope: current_scope_name,
            visibility: current_visibility,
            synthetic: true,
            kind: :writer
          })
        end

        # Register the instance variable
        @generator.register_declaration({
          type: :instance_variable,
          name: "@#{attr_name}",
          node: nil, # Synthetic node
          scope: current_scope_name,
          synthetic: true
        })
      end
    end
  end
end
