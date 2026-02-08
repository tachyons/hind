# GitLab CI/CD Integration for Code Intelligence

This guide explains how to integrate `hind` with GitLab CI/CD to enable Code Intelligence (LSIF) for your Ruby projects.

## Prerequisites

Ensure `hind` is installed in your project. You can add it to your `Gemfile`:

```ruby
gem 'hind'
```

And run:

```bash
bundle install
```

## Configuration

Add a job to your `.gitlab-ci.yml` file to generate and upload the LSIF index.

### Basic Configuration

```yaml
code_navigation:
  image: ruby:3.2 # Use your project's Ruby version
  stage: test
  allow_failure: true # Recommended so CI doesn't fail if indexing fails
  script:
    - bundle install
    # Generate LSIF index
    # -o specifies the output file (default: dump.lsif)
    - bundle exec hind lsif -o dump.lsif
  artifacts:
    reports:
      lsif: dump.lsif
```

### Explanation

1.  **Job Name**: You can name the job anything, e.g., `code_navigation` or `lsif`.
2.  **Image**: Use a Ruby image that matches your project's Ruby version.
3.  **Script**:
    *   Installs dependencies.
    *   Runs `hind lsif` to generate the index.
4.  **Artifacts**:
    *   `reports: lsif: dump.lsif`: This is the critical part. It tells GitLab to treat `dump.lsif` as a code navigation report, which enables the "Code Intelligence" features (hover-to-def, find-references) in the GitLab UI.

## Advanced Usage

### Excluding Directories

You can exclude specific directories (like `vendor` or `spec`) to speed up generation and reduce index size:

```bash
bundle exec hind lsif --exclude "vendor/**/*" --exclude "spec/**/*"
```

### SCIP Support

If you prefer SCIP (Source Code Indexing Protocol), you can generate it, though GitLab's primary native integration is via the LSIF report artifact.

```bash
bundle exec hind scip
```

## Troubleshooting

If code navigation doesn't appear in GitLab:
1.  Check the job logs to ensure `hind` completed successfully.
2.  Verify the artifact was uploaded.
3.  Ensure the `artifacts: reports: lsif` path matches your output file.
