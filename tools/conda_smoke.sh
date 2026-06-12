#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

repo_root="$(pwd)"
packages=("${repo_root}"/dist/linux-64/placo-*.conda)
package_version="$(
  sed -n 's/^  version: "\([^"]*\)"/\1/p' recipe/recipe.yaml | head -n 1
)"

if (( ${#packages[@]} != 1 )); then
  echo "Expected exactly one package in dist/linux-64/, found ${#packages[@]}." >&2
  exit 1
fi

channel_dir="$(mktemp -d /tmp/placo-local-channel.XXXXXX)"
project_dir="$(mktemp -d /tmp/placo-consumer-smoke.XXXXXX)"
cache_dir="$(mktemp -d /tmp/placo-pixi-cache.XXXXXX)"
rattler_cache_dir="$(mktemp -d /tmp/placo-rattler-cache.XXXXXX)"

mkdir -p "${channel_dir}/noarch" "${channel_dir}/linux-64"
printf '%s\n' '{"packages":{},"packages.conda":{},"repodata_version":1}' \
  > "${channel_dir}/noarch/repodata.json"
printf '%s\n' '{"packages":{},"packages.conda":{},"repodata_version":1}' \
  > "${channel_dir}/linux-64/repodata.json"

rattler-build publish \
  --to "${channel_dir}" \
  "${packages[0]}" \
  --force

cat > "${project_dir}/pixi.toml" <<EOF
[workspace]
name = "placo-consumer-smoke"
version = "0.1.0"
channels = [
  "file://${channel_dir}",
  "conda-forge",
  "https://prefix.dev/robostack-jazzy"
]
platforms = ["linux-64"]

[dependencies]
cmake = "*"
ninja = "*"
cxx-compiler = "*"
placo = "==${package_version}"

[tasks]
configure = "cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=\$CONDA_PREFIX"
build = "cmake --build build --parallel"
run = "./build/smoke"
EOF

cat > "${project_dir}/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(placo_consumer_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(placo REQUIRED)

add_executable(smoke main.cpp)
target_link_libraries(smoke PRIVATE placo::placo)
EOF

cat > "${project_dir}/main.cpp" <<'EOF'
#include <cmath>
#include <iostream>

#include <placo/problem/problem.h>

int main()
{
  placo::problem::Problem problem;
  placo::problem::Variable& x = problem.add_variable(1);
  problem.add_constraint(x.expr() == 3.0);
  problem.solve();

  if (std::fabs(x.value(0) - 3.0) > 1e-6) {
    std::cerr << "unexpected QP solution: " << x.value(0) << "\n";
    return 1;
  }
  std::cout << "placo consumer smoke test passed\n";
  return 0;
}
EOF

(
  cd "${project_dir}"
  PIXI_CACHE_DIR="${cache_dir}" RATTLER_CACHE_DIR="${rattler_cache_dir}" pixi install
  PIXI_CACHE_DIR="${cache_dir}" RATTLER_CACHE_DIR="${rattler_cache_dir}" pixi run configure
  PIXI_CACHE_DIR="${cache_dir}" RATTLER_CACHE_DIR="${rattler_cache_dir}" pixi run build
  PIXI_CACHE_DIR="${cache_dir}" RATTLER_CACHE_DIR="${rattler_cache_dir}" pixi run run
)

echo "Smoke project: ${project_dir}"
