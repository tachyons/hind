# frozen_string_literal: true

module Hind
  module LSIF
    class Edge
      attr_reader :id, :label, :out_v, :in_v, :property, :document

      def initialize(id, label, out_v, in_v, property = nil, document = nil)
        @id = id
        @label = label
        @out_v = out_v
        @in_v = in_v
        @property = property
        @document = document
      end

      def to_json(*_args)
        json = {
          id: @id,
          type: 'edge',
          label: @label,
          outV: @out_v
        }

        if @in_v.is_a?(Array)
          json[:inVs] = @in_v
        else
          json[:inV] = @in_v
        end

        json[:property] = @property if @property
        json[:document] = @document if @document

        json
      end
    end
  end
end
