#!/bin/bash

# print all intermediate commands
set -x

# our configuration for this run
TEMPDIR="tmp"
NEXT="0.3.0-rc-$(date +'%Y-%m-%d')"

# Define array of repo names (owner/repo format)
repos=(
  "webassembly/wasi-random"
  # "webassembly/wasi-clocks"
  # "webassembly/wasi-filesystem"
  # "webassembly/wasi-sockets"
  # "webassembly/wasi-cli"
  # "webassembly/wasi-http"
)

# Create a tempdir to clone into
mkdir "$TEMPDIR"
cd "$TEMPDIR"

for repo in "${repos[@]}"; do
  # Check out the repo
  repo_dir=$(basename "$repo")
  git clone "https://github.com/$repo.git"
  cd "$repo_dir" || exit 1
  echo "Inside $(pwd)"

  # Run the action to create a release PR
  repo_name="$(basename "$(pwd)")"
  gh repo set-default WebAssembly/"$repo_name"
  gh workflow run "update-0.3.yml"

  # Wait for the release PR to be filed
  sleep 5 # Sleep to prevent race conditions
  update_run="$(gh run list --workflow "update-0.3.yml" --json databaseId | jq -r '.[0].databaseId')"
  gh run watch "$update_run"

  # Wait for the CI on the PR to pass before merging
  pr="$(gh pr list --author "app/github-actions" --json number | jq -r '.[0].number')"
  gh pr checks "$pr" --watch
  gh pr merge "$pr" -m

  # Create a new GitHub Release
  gh release create v"$NEXT" --generate-notes
  gh release view v"$NEXT"

  # Wait for the release to finish releasing
  sleep 5 # Sleep to prevent race conditions
  release_run="$(gh run list --workflow "publish.yml" --branch v"$NEXT" --json databaseId | jq -r '.[].databaseId')"
  gh run watch "$release_run"

  cd ..
  printf "/n/n"
done

# Clean up all the git clones when we're done
rm -rf "$TEMPDIR"
