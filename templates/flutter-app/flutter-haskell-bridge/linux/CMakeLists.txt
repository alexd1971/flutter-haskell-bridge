# The Flutter tooling requires CMake 3.10 or later.
cmake_minimum_required(VERSION 3.10)

project(flutter_haskell_bridge LANGUAGES CXX)

file(GLOB flutter_haskell_bridge_haskell_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/lib/*.so*"
)

set(flutter_haskell_bridge_bundled_libraries
  ${flutter_haskell_bridge_haskell_libraries}
  PARENT_SCOPE
)
