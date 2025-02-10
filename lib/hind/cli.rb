# frozen_string_literal: true

require 'thor'
require 'json'
require 'pathname'
require 'fileutils'
require 'yaml'

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
    method_option :workers, type: :numeric, aliases: '-w', default: 1, desc: 'Number of parallel workers'
    def lsif
      config = load_config(options[:config])
      opts = config.merge(symbolize_keys(options))

      validate_directory(opts[:directory])
      validate_output_file(opts[:output], opts[:force])

      files = find_files(opts[:directory], opts[:glob], opts[:exclude])
      abort "No files found matching pattern '#{opts[:glob]}'" if files.empty?

      say "Found #{files.length} files to process", :green if opts[:verbose]

      begin
        generate_lsif(files, opts)
        say "\nLSIF data has been written to: #{opts[:output]}", :green if opts[:verbose]
      rescue StandardError => e
        handle_error(e, opts[:verbose])
      end
    end

    desc 'check', 'Check LSIF dump file for validity and provide insights'
    method_option :file, type: :string, aliases: '-f', default: 'dump.lsif', desc: 'LSIF dump file to check'
    method_option :json, type: :boolean, desc: 'Output results in JSON format'
    method_option :strict, type: :boolean, desc: 'Treat warnings as errors'
    def check
      abort "Error: File '#{options[:file]}' does not exist" unless File.exist?(options[:file])

      begin
        checker = Hind::LSIF::Checker.new(options[:file])
        results = checker.check

        if options[:json]
          puts JSON.pretty_generate(results)
        else
          print_check_results(results)
        end

        exit(1) if !results[:valid] || (options[:strict] && results[:warnings].any?)
      rescue StandardError => e
        handle_error(e, options[:verbose])
      end
    end

    desc 'version', 'Show version'
    def version
      say "Hind version #{Hind::VERSION}"
    end

    desc 'init', 'Initialize Hind configuration file'
    method_option :force, type: :boolean, aliases: '-f', desc: 'Overwrite existing configuration'
    def init
      config_file = '.hind.yml'
      if File.exist?(config_file) && !options[:force]
        abort "Configuration file already exists. Use --force to overwrite."
      end

      create_default_config(config_file)
      say "Created configuration file: #{config_file}", :green
    end

    private

    def generate_lsif(files, options)
      # Initialize generator with absolute project root
      generator = Hind::LSIF::Generator.new(
        {
          vertex_id: 1,
          initial: true,
          projectRoot: File.expand_path(options[:directory])
        }
      )

      # Create file content map with relative paths
      file_contents = {}
      files.each do |file|
        absolute_path = File.expand_path(file)
        relative_path = Pathname.new(absolute_path)
                              .relative_path_from(Pathname.new(generator.metadata[:projectRoot]))
                              .to_s
        file_contents[relative_path] = File.read(absolute_path)
      rescue StandardError => e
        warn "Warning: Failed to read file '#{file}': #{e.message}"
        next
      end

      File.open(options[:output], 'w') do |output_file|
        say "First pass: Collecting declarations...", :cyan if options[:verbose]

        # First pass: Process all files to collect declarations
        declaration_data = generator.collect_declarations(file_contents)

        say "Found #{declaration_data[:declarations].size} declarations", :cyan if options[:verbose]
        say "Processing files...", :cyan if options[:verbose]

        # Second pass: Process each file
        file_contents.each do |relative_path, content|
          if options[:verbose]
            say "Processing file: #{relative_path}", :cyan
          end

          lsif_data = generator.process_file(
            content: content,
            uri: relative_path
          )

          output_file.puts(lsif_data.map(&:to_json).join("\n"))
        end

        # Write cross-reference data
        say "Finalizing cross-references...", :cyan if options[:verbose]
        cross_refs = generator.finalize_cross_references
        output_file.puts(cross_refs.map(&:to_json).join("\n")) if cross_refs&.any?
      end
    end

    def validate_directory(directory)
      abort "Error: Directory '#{directory}' does not exist" unless Dir.exist?(directory)
    end

    def validate_output_file(output, force)
      if File.exist?(output) && !force
        abort "Error: Output file '#{output}' already exists. Use --force to overwrite."
      end

      # Ensure output directory exists
      FileUtils.mkdir_p(File.dirname(output))
    end

    def find_files(directory, glob, exclude_patterns)
      pattern = File.join(directory, glob)
      files = Dir.glob(pattern)

      if exclude_patterns
        exclude_patterns.each do |exclude|
          files.reject! { |f| File.fnmatch?(exclude, f) }
        end
      end

      files
    end

    def load_config(config_path)
      return {} unless config_path && File.exist?(config_path)

      begin
        YAML.load_file(config_path) || {}
      rescue StandardError => e
        abort "Error loading config file: #{e.message}"
      end
    end

    def create_default_config(config_file)
      config = {
        'directory' => '.',
        'output' => 'dump.lsif',
        'glob' => '**/*.rb',
        'exclude' => [
          'test/**/*',
          'spec/**/*',
          'vendor/**/*'
        ],
        'workers' => 1
      }

      File.write(config_file, config.to_yaml)
    end

    def print_check_results(results)
      print_check_status(results[:valid])
      print_check_errors(results[:errors])
      print_check_warnings(results[:warnings])
      print_check_statistics(results[:statistics])
    end

    def print_check_status(valid)
      status = valid ? "✅ LSIF dump is valid" : "❌ LSIF dump contains errors"
      say(status, valid ? :green : :red)
      puts
    end

    def print_check_errors(errors)
      return if errors.empty?

      say "Errors:", :red
      errors.each do |error|
        say "  • #{error}", :red
      end
      puts
    end

    def print_check_warnings(warnings)
      return if warnings.empty?

      say "Warnings:", :yellow
      warnings.each do |warning|
        say "  • #{warning}", :yellow
      end
      puts
    end

    def print_check_statistics(stats)
      say "Statistics:", :cyan
      say "  Total Elements: #{stats[:total_elements]}"
      say "  Vertices: #{stats[:vertices][:total]}"
      say "  Edges: #{stats[:edges][:total]}"
      say "  Vertex/Edge Ratio: #{stats[:vertex_to_edge_ratio]}"
      puts

      say "  Documents: #{stats[:documents]}"
      say "  Ranges: #{stats[:ranges]}"
      say "  Definitions: #{stats[:definitions]}"
      say "  References: #{stats[:references]}"
      say "  Hovers: #{stats[:hovers]}"
      puts

      say "  Vertex Types:", :cyan
      stats[:vertices][:by_type].each do |type, count|
        say "    #{type}: #{count}"
      end
      puts

      say "  Edge Types:", :cyan
      stats[:edges][:by_type].each do |type, count|
        say "    #{type}: #{count}"
      end
    end

    def handle_error(error, verbose)
      message = "Error: #{error.message}"
      message += "\n#{error.backtrace.join("\n")}" if verbose
      abort message
    end

    def symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
