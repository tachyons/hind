module Wrapper
  class Parent
    def greet
      "Parent"
    end
  end

  class Child < Parent
    def greet
      super + "Child"
    end
  end
end

c = Wrapper::Child.new
c.greet
