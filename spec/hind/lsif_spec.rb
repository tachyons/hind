# frozen_string_literal: true

require 'spec_helper'
require 'hind/lsif/generator'
require 'json'
require 'tempfile'

RSpec.describe Hind::LSIF::Generator do
  let(:project_root) { File.expand_path('../../fixtures', __dir__) }
  let(:generator) { described_class.new(projectRoot: project_root, initial: true) }

  before do
    FileUtils.mkdir_p(project_root)
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  describe '#execute' do
    it 'generates valid LSIF output for a simple Ruby class' do
      file_path = File.join(project_root, 'simple.rb')
      File.write(file_path, <<~RUBY)
        class Simple
          def hello
            puts "Hello"
          end
        end
      RUBY

      generator.execute(['simple.rb'], {})
      output = generator.instance_variable_get(:@lsif_data)

      # Check for essential LSIF vertices
      expect(output.any? { |e| e[:label] == 'metaData' }).to be true
      expect(output.any? { |e| e[:label] == 'project' }).to be true
      expect(output.any? { |e| e[:label] == 'document' }).to be true

      # Check for class definition
      # We verify that a range exists for "Simple"
      range = output.find do |e|
        e[:label] == 'range' &&
          e[:start][:line] == 0 &&
          e[:start][:character] == 6
      end
      expect(range).not_to be_nil
    end

    it 'generates valid LSIF output for module and constant' do
      file_path = File.join(project_root, 'mod.rb')
      File.write(file_path, <<~RUBY)
        module MyMod
          MY_CONST = 1
        end
      RUBY

      generator.execute(['mod.rb'], {})
      output = generator.instance_variable_get(:@lsif_data)

      # Check for module definition range
      mod_range = output.find do |e|
        e[:label] == 'range' &&
          e[:start][:line] == 0 &&
          e[:start][:character] == 7
      end
      expect(mod_range).not_to be_nil

      # Check for constant definition range
      const_range = output.find do |e|
        e[:label] == 'range' &&
          e[:start][:line] == 1 &&
          e[:start][:character] == 2
      end
      expect(const_range).not_to be_nil
    end

    it 'generates references' do
      file_path = File.join(project_root, 'ref.rb')
      File.write(file_path, <<~RUBY)
        class Params
        end
        
        p = Params.new
      RUBY

      generator.execute(['ref.rb'], {})
      output = generator.instance_variable_get(:@lsif_data)

      # Find definition of Params
      def_range = output.find { |e| e[:label] == 'range' && e[:start][:line] == 0 }
      expect(def_range).not_to be_nil

      # Find reference to Params
      ref_range = output.find { |e| e[:label] == 'range' && e[:start][:line] == 3 && e[:start][:character] == 4 }
      expect(ref_range).not_to be_nil

      # Check if reference is linked to definition via resultSet matching
      # This is a bit complex to query on flat list without graph reconstruction,
      # but we can check if we have referenceResult
      expect(output.any? { |e| e[:label] == 'referenceResult' }).to be true
    end
  end
end
