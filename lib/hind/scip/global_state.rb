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
        @emitted_symbols = Set.new
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
        # Reuse LSIF-like scope resolution logic
        return @symbols[name] if @symbols.key?(name)

        return nil unless current_scope && !current_scope.empty?

        qualified_name = "#{current_scope}::#{name}"
        return @symbols[qualified_name] if @symbols.key?(qualified_name)

        scope_parts = current_scope.split('::')
        while scope_parts.size > 0
          scope_parts.pop
          prefix = scope_parts.join('::')
          qualified_name = prefix.empty? ? name : "#{prefix}::#{name}"
          return @symbols[qualified_name] if @symbols.key?(qualified_name)
        end

        nil
      end
    end
  end
end
