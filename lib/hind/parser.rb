module Hind
  class Parser
    def initialize(code)
      @code = code
    end

    def parse
      result = Prism.parse(@code)
      raise "Parse error: #{result.errors}" unless result.success?
      result.value
    end
  end
end
