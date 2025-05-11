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
          say "  Classes: #{debug_info[:classes_count]} (#{debug_info[:open_classes_count]} open classes)", :cyan
          say "  Modules: #{debug_info[:modules_count]} (#{debug_info[:open_modules_count]} open modules)", :cyan
          say "  Constants: #{debug_info[:constants_count]}", :cyan
          say "  References: #{debug_info[:references_count]}", :cyan
          say "  Result Sets: #{debug_info[:result_sets_count]}", :cyan

          # Report on the most frequently reopened classes/modules
          if debug_info[:open_classes_count] > 0
            most_opened_classes = GlobalState.instance.classes
              .map { |name, data| [name, data[:definitions].size] }
              .select { |_, count| count > 1 }
              .sort_by { |_, count| -count }
              .take(5)

            say "\nMost frequently reopened classes:", :cyan
            most_opened_classes.each do |name, count|
              say "  #{name}: #{count} definitions", :cyan
            end
          end

          if debug_info[:open_modules_count] > 0
            most_opened_modules = LSIF::GlobalState.instance.modules
              .map { |name, data| [name, data[:definitions].size] }
              .select { |_, count| count > 1 }
              .sort_by { |_, count| -count }
              .take(5)

            say "\nMost frequently reopened modules:", :cyan
            most_opened_modules.each do |name, count|
              say "  #{name}: #{count} definitions", :cyan
            end
          end
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
        declaration_data = { lsif_data: [] }
        files.each_with_index do |file, index|
          absolute_path = File.expand_path(file)
          relative_path = Pathname.new(absolute_path)
            .relative_path_from(Pathname.new(generator.metadata[:projectRoot]))
            .to_s

          if options[:verbose] && (index % 50 == 0 || index == files.size - 1)
            say "Processing declarations: #{index + 1}/#{files.size} files", :cyan
          end

          begin
            content = File.read(absolute_path)
            file_declaration_data = generator.collect_file_declarations(content, relative_path)

            # Merge LSIF data
            if file_declaration_data[:lsif_data]&.any?
              declaration_data[:lsif_data].concat(file_declaration_data[:lsif_data])
            end
          rescue => e
            warn "Warning: Failed to read file '#{file}': #{e.message}"
            next
          end
        end

        # Get counts from global state
        if options[:verbose]
          say "Found #{LSIF::GlobalState.instance.classes.size} classes, #{LSIF::GlobalState.instance.modules.size} modules, and #{LSIF::GlobalState.instance.constants.size} constants", :cyan
        end

        # Write declaration LSIF data
        if declaration_data[:lsif_data].any?
          output_file.puts(declaration_data[:lsif_data].map(&:to_json).join("\n"))
        end

        say 'Processing files for references...', :cyan if options[:verbose]

        # Second pass: Process each file for references
        files.each_with_index do |file, index|
          absolute_path = File.expand_path(file)
          relative_path = Pathname.new(absolute_path)
            .relative_path_from(Pathname.new(generator.metadata[:projectRoot]))
            .to_s

          if options[:verbose] && (index % 50 == 0 || index == files.size - 1)
            say "Processing references: #{index + 1}/#{files.size} files", :cyan
          end

          begin
            content = File.read(absolute_path)
            reference_lsif_data = generator.process_file(
              content: content,
              uri: relative_path
            )

            # Write reference LSIF data in chunks to avoid memory issues with large codebases
            if reference_lsif_data&.any?
              output_file.puts(reference_lsif_data.map(&:to_json).join("\n"))
            end
          rescue => e
            warn "Warning: Failed to process file '#{file}': #{e.message}"
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
