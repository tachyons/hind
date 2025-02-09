# lib/hind/lsif/visitor.rb
# frozen_string_literal: true

module Hind
  module LSIF
    class Visitor
      def initialize(generator)
        @generator = generator
        @current_scope = []
      end

      def visit(node)
        return unless node

        method_name = "visit_#{node.class.name.split("::").last.downcase}"
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
        # Handle method definitions
        method_name = node.name.to_s
        qualified_name = current_scope_name.empty? ? method_name : "#{current_scope_name}##{method_name}"

        range_id = @generator.create_range(node.location, node.location)
        result_set_id = @generator.emit_vertex('resultSet')
        @generator.emit_edge('next', range_id, result_set_id)

        def_result_id = @generator.emit_vertex('definitionResult')
        @generator.emit_edge('textDocument/definition', result_set_id, def_result_id)
        @generator.emit_edge('item', def_result_id, [range_id], 'definitions')

        # Generate method signature for hover
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

      def visit_classnode(node)
        @current_scope.push(node.constant_path.slice)
        class_name = current_scope_name

        range_id = @generator.create_range(node.location, node.location)
        result_set_id = @generator.emit_vertex('resultSet')
        @generator.emit_edge('next', range_id, result_set_id)

        def_result_id = @generator.emit_vertex('definitionResult')
        @generator.emit_edge('textDocument/definition', result_set_id, def_result_id)
        @generator.emit_edge('item', def_result_id, [range_id], 'definitions')

        # Generate hover with inheritance info
        hover = []
        class_def = "class #{class_name}"
        class_def += " < #{node.superclass.slice}" if node.superclass

        hover << if node.superclass
          "#{class_def}\n\nInherits from: #{node.superclass.slice}"
        else
          class_def
        end

        hover_id = @generator.emit_vertex('hoverResult', {
          contents: [{
            language: 'ruby',
            value: hover.join("\n")
          }]
        })
        @generator.emit_edge('textDocument/hover', result_set_id, hover_id)

        @generator.add_to_global_state(class_name, result_set_id, range_id)

        # Handle inheritance
        visit_inheritance(node.superclass) if node.superclass

        visit_children(node)
        @current_scope.pop
      end

      def visit_modulenode(node)
        @current_scope.push(node.constant_path.slice)
        module_name = current_scope_name

        range_id = @generator.create_range(node.location, node.location)
        result_set_id = @generator.emit_vertex('resultSet')
        @generator.emit_edge('next', range_id, result_set_id)

        def_result_id = @generator.emit_vertex('definitionResult')
        @generator.emit_edge('textDocument/definition', result_set_id, def_result_id)
        @generator.emit_edge('item', def_result_id, [range_id], 'definitions')

        hover_id = @generator.emit_vertex('hoverResult', {
          contents: [{
            language: 'ruby',
            value: "module #{module_name}"
          }]
        })
        @generator.emit_edge('textDocument/hover', result_set_id, hover_id)

        @generator.add_to_global_state(module_name, result_set_id, range_id)

        visit_children(node)
        @current_scope.pop
      end

      def visit_callnode(node)
        return unless node.name && node.location

        method_name = node.name.to_s
        qualified_names = []

        # Try with current scope first
        qualified_names << "#{current_scope_name}##{method_name}" unless current_scope_name.empty?

        # Try with receiver's type if available
        if node.receiver
          case node.receiver
          when Prism::ConstantReadNode
            qualified_names << "#{node.receiver.name}##{method_name}"
          when Prism::CallNode
            # Handle method chaining
            qualified_names << "#{node.receiver.name}##{method_name}" if node.receiver.name
          when Prism::InstanceVariableReadNode
            # Handle instance variable calls
            qualified_names << "#{current_scope_name}##{method_name}" if current_scope_name
          end
        end

        # Try as a standalone method
        qualified_names << method_name

        # Add references for matching qualified names
        qualified_names.each do |qualified_name|
          next unless @generator.global_state.result_sets[qualified_name]

          range_id = @generator.create_range(node.location, node.location)
          @generator.global_state.add_reference(qualified_name, @generator.metadata[:uri], range_id)
          @generator.emit_edge('next', range_id, @generator.global_state.result_sets[qualified_name])
          break # Stop after finding first match
        end

        visit_children(node)
      end

      def visit_constantreadnode(node)
        return unless node.name

        constant_name = node.name.to_s
        qualified_name = @current_scope.empty? ? constant_name : "#{current_scope_name}::#{constant_name}"

        return unless @generator.global_state.result_sets[qualified_name]

        range_id = @generator.create_range(node.location, node.location)
        @generator.global_state.add_reference(qualified_name, @generator.metadata[:uri], range_id)
        @generator.emit_edge('next', range_id, @generator.global_state.result_sets[qualified_name])
      end

      def visit_constantwritenode(node)
        return unless node.name

        constant_name = node.name.to_s
        qualified_name = @current_scope.empty? ? constant_name : "#{current_scope_name}::#{constant_name}"

        range_id = @generator.create_range(node.location, node.location)
        result_set_id = @generator.emit_vertex('resultSet')
        @generator.emit_edge('next', range_id, result_set_id)

        def_result_id = @generator.emit_vertex('definitionResult')
        @generator.emit_edge('textDocument/definition', result_set_id, def_result_id)
        @generator.emit_edge('item', def_result_id, [range_id], 'definitions')

        hover_id = @generator.emit_vertex('hoverResult', {
          contents: [{
            language: 'ruby',
            value: "#{qualified_name} = ..."
          }]
        })
        @generator.emit_edge('textDocument/hover', result_set_id, hover_id)

        @generator.add_to_global_state(qualified_name, result_set_id, range_id)

        visit_children(node)
      end

      def visit_instancevariablereadnode(node)
        return unless node.name && current_scope_name

        var_name = node.name.to_s
        qualified_name = "#{current_scope_name}##{var_name}"

        return unless @generator.global_state.result_sets[qualified_name]

        range_id = @generator.create_range(node.location, node.location)
        @generator.global_state.add_reference(qualified_name, @generator.metadata[:uri], range_id)
        @generator.emit_edge('next', range_id, @generator.global_state.result_sets[qualified_name])
      end

      def visit_instancevariablewritenode(node)
        return unless node.name && current_scope_name

        var_name = node.name.to_s
        qualified_name = "#{current_scope_name}##{var_name}"

        range_id = @generator.create_range(node.location, node.location)
        result_set_id = @generator.emit_vertex('resultSet')
        @generator.emit_edge('next', range_id, result_set_id)

        def_result_id = @generator.emit_vertex('definitionResult')
        @generator.emit_edge('textDocument/definition', result_set_id, def_result_id)
        @generator.emit_edge('item', def_result_id, [range_id], 'definitions')

        hover_id = @generator.emit_vertex('hoverResult', {
          contents: [{
            language: 'ruby',
            value: "Instance variable #{var_name} in #{current_scope_name}"
          }]
        })
        @generator.emit_edge('textDocument/hover', result_set_id, hover_id)

        @generator.add_to_global_state(qualified_name, result_set_id, range_id)

        visit_children(node)
      end

      private

      def current_scope_name
        @current_scope.join('::')
      end

      def visit_inheritance(node)
        case node
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          range_id = @generator.create_range(node.location, node.location)
          qualified_name = case node
          when Prism::ConstantReadNode
            node.name.to_s
          when Prism::ConstantPathNode
            node.slice
          end

          return unless @generator.global_state.result_sets[qualified_name]

          @generator.global_state.add_reference(qualified_name, @generator.metadata[:uri], range_id)
          @generator.emit_edge('next', range_id, @generator.global_state.result_sets[qualified_name])
        end
      end
    end
  end
end
