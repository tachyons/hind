# frozen_string_literal: true
module MultiFile
  class B
    def use_a
      a = A.new
      a.foo
      puts CONSTANT_A
    end
  end
end
