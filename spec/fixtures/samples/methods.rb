class Person
  attr_accessor :name, :age
  attr_reader :id

  def initialize(id, name, age)
    @id = id
    @name = name
    @age = age
  end

  def celebrate_birthday
    self.age += 1
    puts "Happy birthday #{name}!"
  end
end

p = Person.new(1, "Alice", 30)
p.celebrate_birthday
puts p.name
p.name = "Bob"
