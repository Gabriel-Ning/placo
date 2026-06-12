#!/usr/bin/env bash
set -euo pipefail

cmake_version="$(sed -n 's/^project(placo VERSION \([0-9.]*\))/\1/p' CMakeLists.txt)"
recipe_version="$(sed -n 's/^  version: "\([^"]*\)"/\1/p' recipe/recipe.yaml | head -n 1)"
pyproject_version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' pyproject.toml)"

if [[ "${cmake_version}" != "${recipe_version}" || "${cmake_version}" != "${pyproject_version}" ]]; then
  echo "Version mismatch: CMakeLists=${cmake_version} recipe=${recipe_version} pyproject=${pyproject_version}" >&2
  exit 1
fi

rm -rf dist
rattler-build build \
  -r recipe \
  --channel conda-forge \
  --channel https://prefix.dev/robostack-jazzy \
  --output-dir dist
