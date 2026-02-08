# frozen_string_literal: true

require 'thor'
require 'json'
require 'pathname'
require 'fileutils'

require_relative 'lsif/global_state'
require_relative 'lsif/generator'
require_relative 'scip/generator'

module Hind
  class CLI < Thor
    class_option :verbose, type: :boolean, aliases: '-v', desc: 'Enable verbose output'

    desc 'lsif [DIRECTORY]', 'Generate LSIF index for Ruby classes, modules, and constants'
    method_option :directory, type: :string, aliases: '-d', desc: 'Root directory to process (deprecated, use positional argument)'
    method_option :output, type: :string, aliases: '-o', default: 'dump.lsif', desc: 'Output file path'
    method_option :glob, type: :string, aliases: '-g', default: '**/*.rb', desc: 'File pattern to match'
    method_option :force, type: :boolean, aliases: '-f', desc: 'Overwrite output file if it exists'
    method_option :exclude, type: :array, aliases: '-e', desc: 'Patterns to exclude'
    def lsif(dir = options[:directory] || '.')
      validate_directory(dir)
      validate_output_file(options[:output], options[:force])

      files = find_files(dir, options[:glob], options[:exclude])
      abort "No files found matching pattern '#{options[:glob]}' in #{dir}" if files.empty?

      say "Found #{files.length} files to process in #{dir}", :green if options[:verbose]

      begin
        generate_lsif(files, dir, options)

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
            most_opened_classes = LSIF::GlobalState.instance.classes
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

    desc 'scip [DIRECTORY]', 'Generate SCIP index'
    method_option :directory, type: :string, aliases: '-d', desc: 'Root directory to process (deprecated, use positional argument)'
    method_option :output, type: :string, aliases: '-o', default: 'index.scip', desc: 'Output file path'
    method_option :glob, type: :string, aliases: '-g', default: '**/*.rb', desc: 'File pattern to match'
    method_option :force, type: :boolean, aliases: '-f', desc: 'Overwrite output file if it exists'
    method_option :exclude, type: :array, aliases: '-e', desc: 'Patterns to exclude'
    def scip(dir = options[:directory] || '.')
      validate_directory(dir)
      validate_output_file(options[:output], options[:force])
      
      files = find_files(dir, options[:glob], options[:exclude])
      abort "No files found matching pattern '#{options[:glob]}' in #{dir}" if files.empty?

      say "Found #{files.length} files to process in #{dir}", :green if options[:verbose]

      generator = Hind::SCIP::Generator.new(File.expand_path(dir))
      index = generator.execute(files)
      
      File.write(options[:output], index.to_proto, mode: 'wb')
      say "SCIP index written to #{options[:output]}", :green
    end

    desc 'version', 'Show version'
    def version
      say "Hind version #{Hind::VERSION}"
    end

    private

    def generate_lsif(files, directory, options)
      # Initialize generator with absolute project root
      generator = Hind::LSIF::Generator.new(
        {
          vertex_id: 1,
          projectRoot: File.expand_path(directory)
        }
      )

      File.open(options[:output], 'w') do |output_file|
        say 'Processing files...', :cyan if options[:verbose]

        lsif_data = generator.execute(files, options)

        # Get counts from global state
        if options[:verbose]
          say "Found #{LSIF::GlobalState.instance.classes.size} classes, #{LSIF::GlobalState.instance.modules.size} modules, and #{LSIF::GlobalState.instance.constants.size} constants", :cyan
        end

        output_file.puts(lsif_data.map(&:to_json).join("\n"))
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
      absolute_directory = File.expand_path(directory)
      
      files = Dir.glob(pattern).map do |file|
        # Return relative path to the directory for indexing
        Pathname.new(File.expand_path(file)).relative_path_from(Pathname.new(absolute_directory)).to_s
      end

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
