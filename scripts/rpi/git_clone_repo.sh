#!/bin/bash

usage() {
  echo "Usage: $0 <repo_url> <local_dir> [branch_to_clone] [new_branch_name]"
  echo "  [branch_to_clone] and [new_branch_name] are optional."
  exit 1
}

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  usage
fi

REPO_URL=$1
LOCAL_DIR=$2

# Optional arguments.
if [ "$#" -ge 3 ]; then
  BRANCH_TO_CLONE=$3
else
  BRANCH_TO_CLONE="master" # Default to the master branch if not provided.
fi
if [ "$#" -eq 4 ]; then # Check if the new branch name was provided.
  NEW_BRANCH_NAME=$4
fi

echo "Cloning ref '$BRANCH_TO_CLONE' from repository ${REPO_URL}"
git clone --branch "$BRANCH_TO_CLONE" "$REPO_URL" "$LOCAL_DIR"
if [ $? -ne 0 ]; then
  echo "Error: Failed to clone the repository. Check the URL and branch name."
  exit 1
fi

cd "$LOCAL_DIR" || exit 1

if [ -n "$NEW_BRANCH_NAME" ]; then
  echo "Creating and checking out a new local branch called '$NEW_BRANCH_NAME'..."
  git checkout -b "$NEW_BRANCH_NAME"
  echo "Removing the remote origin..."
  git remote remove origin
else
  echo "No new branch name was provided. The remote origin remains and you are on the cloned branch."
fi

echo "Repository cloned successfully into ${LOCAL_DIR}"