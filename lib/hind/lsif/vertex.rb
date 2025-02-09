module Hind
  module LSIF
    class Vertex
      attr_reader :id, :label, :data

      def initialize(id, label, data = nil)
        @id = id
        @label = label
        @data = data
      end

      def to_json
        json = {
          id: @id,
          type: 'vertex',
          label: @label
        }

        if @data
          if %w[hoverResult definitionResult referenceResult].include?(@label)
            json[:result] = @data
          else
            json.merge!(@data)
          end
        end

        json
      end
    end
  end
end
