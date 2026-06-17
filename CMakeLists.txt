cmake_minimum_required(VERSION 3.25)
project(wire_cell_phlex_arrow VERSION 0.1.0 LANGUAGES CXX)

# C++23: phlex/module.hpp (pulled in by the convert plugin and the convert-node
# helper) uses std::forward_like / std::ranges::to.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "14.1")
    if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS "15")
      add_compile_options(-Wno-stringop-overflow)
    endif()
    if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS "16")
      add_compile_options(-Wno-array-bounds)
    endif()
  endif()
endif()

add_compile_options(-Wall -Wpedantic -Werror)

# Dependencies.  Find phlex's un-found-dependency deps (TBB/Boost/spdlog) and
# Arrow before phlex; then the wire-cell-arrow converters, the wire-cell-phlex
# wrappers, and the Phlex Arrow glue.
find_package(Arrow CONFIG REQUIRED)
find_package(TBB REQUIRED)
find_package(Boost REQUIRED COMPONENTS json)
find_package(spdlog REQUIRED)
find_package(phlex REQUIRED)
find_package(WireCell REQUIRED)
find_package(wire_cell_arrow CONFIG REQUIRED)
find_package(wire_cell_phlex CONFIG REQUIRED)
find_package(phlex_arrow_common CONFIG REQUIRED)

# Link the Spack view's gcc15 libstdc++ explicitly (GLIBCXX/CXXABI resolution).
set(WCPA_RUNTIME_LIBS "")
foreach(_prefix IN LISTS CMAKE_PREFIX_PATH)
  if(EXISTS "${_prefix}/lib/libstdc++.so.6")
    file(REAL_PATH "${_prefix}/lib/libstdc++.so.6" _stdc_real)
    get_filename_component(_stdc_dir "${_stdc_real}" DIRECTORY)
    set(WCPA_RUNTIME_LIBS "${_stdc_real}")
    string(APPEND CMAKE_EXE_LINKER_FLAGS " -Wl,-rpath,${_stdc_dir}")
    break()
  endif()
endforeach()

# The conversion logic (unit-testable, no Phlex graph machinery).
add_library(wire_cell_phlex_arrow SHARED
  wire_cell_phlex_arrow/Convert.cpp
)
target_include_directories(wire_cell_phlex_arrow
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(wire_cell_phlex_arrow
  PUBLIC
    wire_cell_arrow::wire_cell_arrow
    wire_cell_phlex::wire_cell_phlex
    phlex_arrow_common::phlex_arrow_common
    Arrow::arrow_shared
    ${WCPA_RUNTIME_LIBS}
)

# The Phlex plugin (dlopen MODULE): loading it registers the convert nodes.
add_library(wire_cell_phlex_arrow_convert MODULE
  wire_cell_phlex_arrow/ConvertModule.cpp
)
target_link_libraries(wire_cell_phlex_arrow_convert PRIVATE
  wire_cell_phlex_arrow
  phlex::module
  ${WCPA_RUNTIME_LIBS}
)

enable_testing()
add_subdirectory(test)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

install(TARGETS wire_cell_phlex_arrow
  EXPORT wire_cell_phlex_arrowTargets
  LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")
install(TARGETS wire_cell_phlex_arrow_convert
  LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")
install(DIRECTORY wire_cell_phlex_arrow/
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/wire_cell_phlex_arrow"
  FILES_MATCHING PATTERN "*.h")

install(EXPORT wire_cell_phlex_arrowTargets
  FILE wire_cell_phlex_arrowTargets.cmake
  NAMESPACE wire_cell_phlex_arrow::
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/wire_cell_phlex_arrow")

# Bundle FindWireCell.cmake so the installed config can re-find WireCell
# (WireCell ships no CMake config package).
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/cmake/FindWireCell.cmake"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/wire_cell_phlex_arrow")

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/wire_cell_phlex_arrowConfigVersion.cmake"
  VERSION ${PROJECT_VERSION} COMPATIBILITY SameMajorVersion)
configure_package_config_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/wire_cell_phlex_arrowConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/wire_cell_phlex_arrowConfig.cmake"
  INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/wire_cell_phlex_arrow")
install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/wire_cell_phlex_arrowConfig.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/wire_cell_phlex_arrowConfigVersion.cmake"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/wire_cell_phlex_arrow")
