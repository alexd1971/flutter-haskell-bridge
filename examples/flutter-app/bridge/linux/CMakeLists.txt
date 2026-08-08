# The Flutter tooling requires CMake 3.10 or later.
cmake_minimum_required(VERSION 3.10)

project(bridge LANGUAGES CXX)

file(GLOB bridge_haskell_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/lib/*.so*"
)

set(bridge_bundled_libraries
  ${bridge_haskell_libraries}
  PARENT_SCOPE
)
