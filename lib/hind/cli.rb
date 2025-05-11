# frozen_string_literal: true

require 'thor'
require 'json'
require 'pathname'
require 'fileutils'

require_relative 'lsif/global_state'

module Hind
  class CLI < Thor
    class_option :verbose, type: :boolean, aliases: '-v', desc: 'Enable verbose output'

    desc 'lsif', 'Generate LSIF index for Ruby classes, modules, and constants'
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

        # Add debug info from the global state
        if options[:verbose]
          debug_info = LSIF::GlobalState.instance.debug_info
          say "\nGlobal State Summary:", :cyan
          say "  Classes: #{debug_info[:classes_count]}", :cyan
          say "  Modules: #{debug_info[:modules_count]}", :cyan
          say "  Constants: #{debug_info[:constants_count]}", :cyan
          say "  References: #{debug_info[:references_count]}", :cyan
          say "  Result Sets: #{debug_info[:result_sets_count]}", :cyan
        end

        say "\nLSIF data has been written to: #{options[:output]}", :green if options[:verbose]
      rescue => e
        handle_error(e, options[:verbose])
      end
    end

    desc 'version', 'Show version'
    def version
      say "Hind version #{Hind::VERSION}"
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

      File.open(options[:output], 'w') do |output_file|
        say 'First pass: Collecting declarations...', :cyan if options[:verbose]

        # Write initial LSIF data (metadata and project vertices)
        initial_data = generator.get_initial_data
        if initial_data&.any?
          say 'Writing initial LSIF data...', :cyan if options[:verbose]
          output_file.puts(initial_data.map(&:to_json).join("\n"))
        end

        # First pass: Process all files to collect declarations
        declaration_data = {}
        files.each do |file|
          absolute_path = File.expand_path(file)
          relative_path = Pathname.new(absolute_path)
            .relative_path_from(Pathname.new(generator.metadata[:projectRoot]))
            .to_s

          begin
            content = File.read(absolute_path)
            file_declaration_data = generator.collect_file_declarations(content, relative_path)
            declaration_data.merge!(file_declaration_data)
          rescue => e
            warn "Warning: Failed to read file '#{file}': #{e.message}"
            next
          end
        end

        say "Found #{LSIF::GlobalState.instance.classes.size} classes, #{LSIF::GlobalState.instance.modules.size} modules, and #{LSIF::GlobalState.instance.constants.size} constants", :cyan if options[:verbose]

        # Write declaration LSIF data next
        if declaration_data[:lsif_data]&.any?
          output_file.puts(declaration_data[:lsif_data].map(&:to_json).join("\n"))
        end

        say 'Processing files for references...', :cyan if options[:verbose]

        # Second pass: Process each file for references
        files.each do |file|
          absolute_path = File.expand_path(file)
          relative_path = Pathname.new(absolute_path)
            .relative_path_from(Pathname.new(generator.metadata[:projectRoot]))
            .to_s

          if options[:verbose]
            say "Processing file: #{relative_path}", :cyan
          end

          begin
            content = File.read(absolute_path)
            reference_lsif_data = generator.process_file(
              content: content,
              uri: relative_path
            )
            output_file.puts(reference_lsif_data.map(&:to_json).join("\n"))
          rescue => e
            warn "Warning: Failed to read file '#{file}': #{e.message}"
            next
          end
        end
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

      exclude_patterns&.each do |exclude|
        files.reject! { |f| File.fnmatch?(exclude, f) }
      end

      files
    end

    def handle_error(error, verbose)
      message = "Error: #{error.message}"
      message += "\n#{error.backtrace.join("\n")}" if verbose
      abort message
    end
  end
end
