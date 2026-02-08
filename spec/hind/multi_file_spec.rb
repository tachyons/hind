# frozen_string_literal: true

require 'spec_helper'
require 'hind/lsif/generator'
require 'json'
require 'fileutils'

RSpec.describe 'Multi-file LSIF Generation' do
  let(:project_root) { File.expand_path('../fixtures/multi_file', __dir__) }
  let(:generator) { Hind::LSIF::Generator.new(projectRoot: project_root, initial: true) }
  
  before do
    FileUtils.mkdir_p(project_root)
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  it 'resolves references across files' do
    # File 1: Definition
    File.write(File.join(project_root, 'def.rb'), <<~RUBY)
      class MySharedClass
        def self.foo; end
      end
    RUBY

    # File 2: Reference
    File.write(File.join(project_root, 'ref.rb'), <<~RUBY)
      MySharedClass.foo
    RUBY

    # Execute on both files
    output = generator.execute(['def.rb', 'ref.rb'], {})
    
    # 1. Find definition range ID
    def_range = output.find { |e| e[:label] == 'range' && e[:start][:line] == 0 && e[:start][:character] == 6 } # "MySharedClass"
    expect(def_range).not_to be_nil
    
    # 2. Find result set for definition
    # next edge from range -> resultSet
    next_edge = output.find { |e| e[:label] == 'next' && e[:outV] == def_range[:id] }
    expect(next_edge).not_to be_nil
    result_set_id = next_edge[:inV]

    # 3. Find reference range in ref.rb
    # MySharedClass starts at line 0, char 0 in ref.rb
    # But wait, looking at ref.rb content: "MySharedClass.foo"
    # Prism might give location for constant read.
    ref_range = output.find do |e| 
        # Check if this range belongs to the document for ref.rb (we might need to check contains edge, but let's check basic props first)
        # We can't easily check which document a range belongs to from just the range vertex.
        # But we can check the line/char.
        e[:label] == 'range' && e[:start][:line] == 0 && e[:start][:character] == 0 
    end
    expect(ref_range).not_to be_nil
    
    # 4. Reference should point to SAME result set (or have a next edge to it)
    # The current implementation adds a 'next' edge from reference range to declaration's result set.
    ref_next_edge = output.find { |e| e[:label] == 'next' && e[:outV] == ref_range[:id] }
    expect(ref_next_edge).not_to be_nil
    expect(ref_next_edge[:inV]).to eq(result_set_id)
  end
end
