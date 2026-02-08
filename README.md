# Hind

Hind is a Ruby gem for generating code intelligence data in LSIF (Language Server Index Format) and SCIP (Sourcegraph Code Intelligence Protocol) formats. It helps create index files that power code navigation features like go-to-definition, find references, and hover documentation.

## Installation

Install the gem:

```bash
gem install hind
```

Or add it to your Gemfile:

```ruby
gem 'hind'
```

## Usage

### GitLab CI Integration

See [GitLab CI Integration Guide](docs/gitlab_ci.md) for detailed instructions.

### Generating LSIF Data

To generate LSIF data for your Ruby project:

```bash
# Basic usage
hind lsif

# Specify directory and output file
hind lsif -d /path/to/project -o output.lsif

# Process specific files with glob pattern
hind lsif -g "lib/**/*.rb"

# Exclude patterns
hind lsif -e "test/**/*" -e "spec/**/*"

# Verbose output
hind lsif -v
```

### Generating SCIP Data

To generate SCIP data for your Ruby project:

```bash
hind scip
```

This will produce an `index.scip` file which is a JSON serialization of the SCIP index.

Options:
- `-d, --directory DIR` - Root directory to process (default: current directory)
- `-o, --output FILE` - Output file path (default: dump.lsif)
- `-g, --glob PATTERN` - File pattern to match (default: **/*.rb)
- `-f, --force` - Overwrite output file if it exists
- `-e, --exclude PATTERN` - Patterns to exclude (can be specified multiple times)
- `-v, --verbose` - Enable verbose output
- `-c, --config FILE` - Path to configuration file



### GitLab Integration

To use Hind with GitLab for code intelligence:

1. Add this to your `.gitlab-ci.yml`:

```yaml
lsif:
  stage: lsif
  script:
    - gem install hind
    - hind lsif -d . -o dump.lsif -v
  artifacts:
    reports:
      lsif: dump.lsif
```

2. GitLab will automatically process the LSIF data and enable code intelligence features.

## Features

- Generates LSIF data for Ruby code
- Supports code intelligence features:
  - Go to definition
  - Find references
  - Hover documentation
  - Symbol search
- Integrates with GitLab code intelligence
- Configurable output and processing
- Comprehensive error checking and reporting

## Development

After checking out the repo:

1. Install dependencies:
```bash
bundle install
```

2. Run tests:
```bash
bundle exec rspec
```

3. Run the gem locally:
```bash
bundle exec bin/hind
```

## Roadmap / TODO

The following features are planned for future releases to improve indexing fidelity and performance:

- **Ruby Semantic Fidelity**
  - [ ] Ancestor Chain Resolution (`include`, `extend`, `prepend`)
  - [ ] Local Variables & Method Parameters
  - [ ] Dynamic Method Support (`attr_accessor`, `delegate`, etc.)
  - [ ] Block & Lambda Scopes
- **External Dependencies**
  - [ ] External Gem Resolution (linking to symbols in dependencies)
  - [ ] Core & Standard Library Linking
- **Advanced SCIP/LSIF Features**
  - [ ] SCIP Relationships (implementation/inheritance edges)
  - [ ] LSIF Monikers for cross-repo resolution
- **Performance**
  - [ ] Parallel Processing for large codebases
  - [ ] Incremental Indexing

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yourusername/hind.

## License

The gem is available as open source under the terms of the MIT License.
