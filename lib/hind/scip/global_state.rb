# frozen_string_literal: true

require 'singleton'
require 'set'

module Hind
  module SCIP
    class GlobalState
      include Singleton

      def initialize
        reset
      end

      def reset
        @symbols = {} # {qualified_name => symbol_string}
        @ancestors = {} # {qualified_name => [symbol_strings]}
        @emitted_symbols = Set.new
      end

      def add_ancestor(qualified_name, mixed_in_symbol)
        @ancestors[qualified_name] ||= []
        @ancestors[qualified_name] << mixed_in_symbol
      end

      def mark_emitted(symbol)
        @emitted_symbols.add(symbol)
      end

      def emitted?(symbol)
        @emitted_symbols.include?(symbol)
      end

      def add_symbol(name, symbol)
        @symbols[name] = symbol
      end

      def get_symbol(name)
        @symbols[name]
      end

      def has_symbol?(name)
        @symbols.key?(name)
      end

      def find_symbol(name, current_scope)
        # Handle both constants (::) and methods (#)
        is_method = name.start_with?('#')
        sep = is_method ? '' : '::'

        # 1. Lexical Scope search
        qualified_name = current_scope.empty? ? name : "#{current_scope}#{sep}#{name}"
        qualified_name = name if current_scope.empty? && is_method
        return @symbols[qualified_name] if @symbols.key?(qualified_name)

        # 2. Ancestor chain search for current scope
        if !current_scope.empty?
          found = resolve_in_ancestors(name, current_scope, seen: Set.new)
          return found if found
        end

        # 3. Parent Lexical Scopes
        scope_parts = current_scope.split('::')
        while scope_parts.size > 0
          scope_parts.pop
          prefix = scope_parts.join('::')

          qualified_name = prefix.empty? ? name : "#{prefix}#{sep}#{name}"
          qualified_name = name if prefix.empty? && is_method
          return @symbols[qualified_name] if @symbols.key?(qualified_name)

          # Search ancestors of the parent scope too
          if !prefix.empty?
            found = resolve_in_ancestors(name, prefix, seen: Set.new)
            return found if found
          end
        end

        nil
      end

      private

      def resolve_in_ancestors(name, scope, seen:)
        return nil if seen.include?(scope)
        seen.add(scope)

        is_method = name.start_with?('#')
        sep = is_method ? '' : '::'

        ancestors = @ancestors[scope] || []
        ancestors.each do |mixed_in|
          # 1. Try to see if mixed_in has the declaration
          qualified = "#{mixed_in}#{sep}#{name}"
          return @symbols[qualified] if @symbols.key?(qualified)

          # 2. Recurse into mixed_in's ancestors
          found = resolve_in_ancestors(name, mixed_in, seen: seen)
          return found if found
        end

        nil
      end
    end
  end
end
