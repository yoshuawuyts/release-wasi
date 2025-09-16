#!/bin/bash

# print all intermediate commands
set -x

# our configuration for this run
DATE="$(date +'%Y-%m-%d')"
TEMPDIR="tmp"
TAG="0.3.0-rc-$DATE"

# Define array of repo names (owner/repo format)
repos=(
  "webassembly/wasi-random"
  # "webassembly/wasi-clocks"
  # "webassembly/wasi-filesystem"
  # "webassembly/wasi-sockets"
  # "webassembly/wasi-cli"
  # "webassembly/wasi-http"
)

delete_release_and_tag() {
  gh release delete "$TAG" --yes
  git tag -d "$TAG"
  git push --delete origin "$TAG"
}

bump_versions() {
  local REPO_NAME="$1"

  # Run the action to create a release PR
  gh repo set-default WebAssembly/"$REPO_NAME"
  gh workflow run "update-0.3.yml"

  # Wait for the release PR to be filed
  sleep 5 # Sleep to prevent race conditions
  update_run="$(gh run list --workflow "update-0.3.yml" --created "$DATE" --json databaseId | jq -r '.[0].databaseId')"
  gh run watch "$update_run" --exit-status || exit 1

  # Wait for the CI on the PR to pass before merging
  pr="$(gh pr list --author "app/github-actions" --json number | jq -r '.[0].number')"
  gh pr checks "$pr" --watch
  gh pr merge "$pr" --merge --delete-branch
}

release() {
  # Create a new GitHub Release
  gh release create v"$TAG" --prerelease --generate-notes
  gh release view v"$TAG"

  # Wait for the release to finish releasing
  sleep 5 # Sleep to prevent race conditions
  release_run="$(gh run list --workflow "update-0.3.yml" --created "$DATE" --json databaseId | jq -r '.[0].databaseId')"
  gh run watch "$release_run" --exit-status || exit 1

  # Validate the release went through
  sleep 5 # Sleep to prevent race conditions
  local proposal_name="${repo_name#wasi-}"
  oras manifest fetch ghcr.io/webassembly/"$proposal_name":0.3.0-rc-"$DATE" || exit 1
}

main() {
  # Create a tempdir to clone into
  rm -rf "$TEMPDIR"
  mkdir "$TEMPDIR"
  cd "$TEMPDIR" || exit 1

  for repo in "${repos[@]}"; do
    # Check out the repo
    repo_name=$(basename "$repo")
    git clone "https://github.com/$repo.git"
    cd "$repo_name" || exit 1

    if ! (gh release view "$TAG" &>/dev/null); then
      # Bump the versions in the WIT if we haven't already
      # done so in a previous run (idempotency)
      bump_versions "$repo_name"
    else
      # If we've already tried (and failed) to make a release,
      # delete the tags and try again
      delete_release_and_tag
    fi

    # Regardless, try to run the release again
    release

    cd ..
    printf "/n/n"
  done

  # Clean up all the git clones when we're done
  rm -rf "$TEMPDIR"
}

main
