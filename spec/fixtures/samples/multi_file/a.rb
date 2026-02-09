# frozen_string_literal: true

module MultiFile
  class A
    def foo
      puts 'A#foo'
    end
  end

  CONSTANT_A = 'A'
end
