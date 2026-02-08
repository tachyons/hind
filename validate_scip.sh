#!/bin/bash
set -e

# Ensure scip is in path
export PATH=$PATH:$(go env GOPATH)/bin

echo "Validating fixtures..."

for file in spec/fixtures/samples/*.rb; do
  echo "Processing $file..."
  # Output file will be binary protobuf
  bundle exec hind scip -d . -g "$file" -o "${file}.scip" --force --verbose
  
  echo "Printing ${file}.scip..."
  scip print "${file}.scip"
  
  echo "Linting ${file}.scip..."
  scip lint "${file}.scip"
done
