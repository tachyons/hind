module Mixin
  def mixin_method
    'mixin'
  end
end

class Base
  include Mixin
end

b = Base.new
b.mixin_method
