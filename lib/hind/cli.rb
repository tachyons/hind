# frozen_string_literal: true

require 'thor'
require 'json'
require 'pathname'
require 'fileutils'

module Hind
  class CLI < Thor
    class_option :verbose, type: :boolean, aliases: '-v', desc: 'Enable verbose output'
    class_option :config, type: :string, aliases: '-c', desc: 'Path to configuration file'

    desc 'lsif', 'Generate LSIF index'
    method_option :directory, type: :string, aliases: '-d', default: '.', desc: 'Root directory to process'
    method_option :output, type: :string, aliases: '-o', default: 'dump.lsif', desc: 'Output file path'
    method_option :glob, type: :string, aliases: '-g', default: '**/*.rb', desc: 'File pattern to match'
    method_option :force, type: :boolean, aliases: '-f', desc: 'Overwrite output file if it exists'
    method_option :exclude, type: :array, aliases: '-e', desc: 'Patterns to exclude'
    def lsif
      validate_directory(options[:directory])
      validate_output_file(options[:output], options[:force])

      files = find_files(options[:directory], options[:glob], options[:exclude])
      abort "No files found matching pattern '#{options[:glob]}'" if files.empty?

      say "Found #{files.length} files to process", :green if options[:verbose]

      begin
        generate_lsif(files, options)
        say "\nLSIF data has been written to: #{options[:output]}", :green if options[:verbose]
      rescue => e
        abort "Error generating LSIF: #{e.message}"
      end
    end

    desc 'scip', 'Generate SCIP index'
    method_option :directory, type: :string, aliases: '-d', default: '.', desc: 'Root directory to process'
    method_option :output, type: :string, aliases: '-o', default: 'index.scip', desc: 'Output file path'
    method_option :glob, type: :string, aliases: '-g', default: '**/*.rb', desc: 'File pattern to match'
    method_option :force, type: :boolean, aliases: '-f', desc: 'Overwrite output file if it exists'
    method_option :exclude, type: :array, aliases: '-e', desc: 'Patterns to exclude'
    def scip
      validate_directory(options[:directory])
      validate_output_file(options[:output], options[:force])

      files = find_files(options[:directory], options[:glob], options[:exclude])
      abort "No files found matching pattern '#{options[:glob]}'" if files.empty?

      say "Found #{files.length} files to process", :green if options[:verbose]

      begin
        generate_scip(files, options)
        say "\nSCIP data has been written to: #{options[:output]}", :green if options[:verbose]
      rescue => e
        abort "Error generating SCIP: #{e.message}"
      end
    end

    desc 'version', 'Show version'
    def version
      say "Hind version #{Hind::VERSION}"
    end

    private

    def validate_directory(directory)
      abort "Error: Directory '#{directory}' does not exist" unless Dir.exist?(directory)
    end

    def validate_output_file(output, force)
      abort "Error: Output file '#{output}' already exists. Use --force to overwrite." if File.exist?(output) && !force

      # Ensure output directory exists
      FileUtils.mkdir_p(File.dirname(output))
    end

    def find_files(directory, glob, exclude_patterns)
      pattern = File.join(directory, glob)
      files = Dir.glob(pattern)

      exclude_patterns&.each do |exclude|
        files.reject! { |f| File.fnmatch?(exclude, f) }
      end

      files
    end

    def generate_lsif(files, options)
      global_state = Hind::LSIF::GlobalState.new
      vertex_id = 1
      initial = true

      File.open(options[:output], 'w') do |output_file|
        files.each do |file|
          say "Processing file: #{file}", :cyan if options[:verbose]

          relative_path = Pathname.new(file).relative_path_from(Pathname.new(options[:directory])).to_s

          begin
            generator = Hind::LSIF::Generator.new(
              {
                uri: relative_path,
                vertex_id: vertex_id,
                initial: initial,
                projectRoot: options[:directory]
              },
              global_state
            )

            output = generator.generate(File.read(file))
            vertex_id = output.last[:id].to_i + 1
            output_file.puts(output.map(&:to_json).join("\n"))
            initial = false
          rescue => e
            warn "Warning: Failed to process file '#{file}': #{e.message}"
            next
          end
        end
      end
    end

    def generate_scip(files, options)
      raise NotImplementedError, 'SCIP generation not yet implemented'
      # Similar to generate_lsif but using SCIP generator
    end

    def load_config(config_path)
      return {} unless config_path && File.exist?(config_path)

      begin
        YAML.load_file(config_path) || {}
      rescue => e
        abort "Error loading config file: #{e.message}"
      end
    end
  end
end
