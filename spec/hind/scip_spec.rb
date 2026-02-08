# frozen_string_literal: true

require 'spec_helper'
require 'hind/scip/generator'
require 'json'
require 'tempfile'

RSpec.describe Hind::SCIP::Generator do
  let(:project_root) { File.expand_path('../../fixtures', __dir__) }
  let(:generator) { described_class.new(project_root) }
  
  before do
    FileUtils.mkdir_p(project_root)
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  describe '#execute' do
    it 'generates valid SCIP index for a simple Ruby class' do
      file_path = File.join(project_root, 'simple.rb')
      File.write(file_path, <<~RUBY)
        class Simple
          def hello
            puts "Hello"
          end
        end
      RUBY

      index = generator.execute(['simple.rb'])
      
      # We expect the generator to return a SCIP::Index object
      expect(index).to be_a(Hind::SCIP::Index)
      expect(index.documents).to be_a(Google::Protobuf::RepeatedField)
      expect(index.documents.first.relative_path).to eq('simple.rb')
      
      occurrences = index.documents.first.occurrences
      expect(occurrences).to be_a(Google::Protobuf::RepeatedField)
      
      # Check for "Simple" class definition
      # symbol: "ruby simple Simple#" (approximate SCIP symbol format)
      has_class_def = occurrences.any? do |occ|
         occ.symbol.include?('Simple') && (occ.symbol_roles & 1) != 0 # Definition role
      end
      expect(has_class_def).to be true
    end
  end
end
