module Loggable
  def log(msg)
    puts "[LOG] #{msg}"
  end
end

module Authenticatable
  def login
    log("Logging in")
  end
end

class Base
  include Loggable
end

class User < Base
  include Authenticatable

  def perform_action
    log("Action started")
    login
    log("Action finished")
  end
end

u = User.new
u.perform_action
