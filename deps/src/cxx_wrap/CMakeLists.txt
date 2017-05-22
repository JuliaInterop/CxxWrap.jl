cmake_minimum_required(VERSION 2.8.12)
project(CxxWrap)

# Dependencies
# ============

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR})
find_package(Julia REQUIRED)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_MACOSX_RPATH 1)

include(GenerateExportHeader)

# Compilation flags
# =================

include(CheckCXXCompilerFlag)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR CMAKE_CXX_COMPILER_ID MATCHES "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES "Intel")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native -Wunused-parameter -Wextra -Wreorder")
    CHECK_CXX_COMPILER_FLAG("-std=c++11" HAS_CPP11_FLAG)

    if (HAS_CPP11_FLAG)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
    else()
        message(FATAL_ERROR "Unsupported compiler -- cxx_wrap requires C++11 support!")
    endif()
endif()

add_definitions(-DJULIA_ENABLE_THREADING)

if(WIN32 AND DEFINED ENV{MSYSTEM})
  if($ENV{MSYSTEM} STREQUAL "MINGW32")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=pentium4 -static-libstdc++")
  endif()
endif()

set(CMAKE_INSTALL_LIBDIR "lib")

set(CXXWRAP_BUILD_EXAMPLES ON CACHE BOOL "Build the CxxWrap examples")

# Source files
# ============

set(CXXWRAP_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(CXXWRAP_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)

set(CXXWRAP_HEADERS
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/array.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/const_array.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/cxx_wrap.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/cxx_wrap_config.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/functions.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/smart_pointers.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/tuple.hpp
    ${CXXWRAP_INCLUDE_DIR}/cxx_wrap/type_conversion.hpp
)

set(CXXWRAP_SOURCES
  ${CXXWRAP_SOURCE_DIR}/c_interface.cpp
  ${CXXWRAP_SOURCE_DIR}/cxx_wrap.cpp
  ${CXXWRAP_SOURCE_DIR}/functions.cpp
)

set(CXXWRAP_INSTALL_INCLUDEDIR ${CMAKE_INSTALL_PREFIX}/include)

# Versioning
# ==========

file(STRINGS "${CXXWRAP_INCLUDE_DIR}/cxx_wrap/cxx_wrap_config.hpp" cxx_wrap_version_defines
    REGEX "#define CXXWRAP_VERSION_(MAJOR|MINOR|PATCH)")
foreach(ver ${cxx_wrap_version_defines})
    if(ver MATCHES "#define CXXWRAP_VERSION_(MAJOR|MINOR|PATCH) +([^ ]+)$")
        set(CXXWRAP_VERSION_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}" CACHE INTERNAL "")
    endif()
endforeach()
set(${PROJECT_NAME}_VERSION
    ${CXXWRAP_VERSION_MAJOR}.${CXXWRAP_VERSION_MINOR}.${CXXWRAP_VERSION_PATCH})
message(STATUS "${PROJECT_NAME} version: v${${PROJECT_NAME}_VERSION}")

# Output
# ======

set(CXXWRAP_TARGET cxx_wrap)
add_library(${CXXWRAP_TARGET} SHARED ${CXXWRAP_SOURCES} ${CXXWRAP_HEADERS})

target_include_directories(${CXXWRAP_TARGET} PUBLIC
  $<INSTALL_INTERFACE:${CXXWRAP_INSTALL_INCLUDEDIR}>
  $<BUILD_INTERFACE:${CXXWRAP_INCLUDE_DIR}>
  $<BUILD_INTERFACE:${Julia_INCLUDE_DIRS}>
)
generate_export_header(${CXXWRAP_TARGET})

target_link_libraries(${CXXWRAP_TARGET} $<BUILD_INTERFACE:${Julia_LIBRARY}>)
set_target_properties(${CXXWRAP_TARGET} PROPERTIES
                      PUBLIC_HEADER "${CXXWRAP_HEADERS}"
                      COMPILE_DEFINITIONS "CXXWRAP_EXPORTS")
set_property(TARGET ${CXXWRAP_TARGET} PROPERTY VERSION ${${PROJECT_NAME}_VERSION})
set_property(TARGET ${CXXWRAP_TARGET} PROPERTY SOVERSION ${CXXWRAP_VERSION_MAJOR})
set_property(TARGET ${CXXWRAP_TARGET} PROPERTY
  INTERFACE_${CXXWRAP_TARGET}_MAJOR_VERSION ${CXXWRAP_VERSION_MAJOR})
set_property(TARGET ${CXXWRAP_TARGET} APPEND PROPERTY
  COMPATIBLE_INTERFACE_STRING ${CXXWRAP_TARGET}_MAJOR_VERSION
)

set(CXXWRAP_NAME ${CXXWRAP_TARGET})
if(WIN32)
    if(MSVC)
        set(CXXWRAP_LINK_FILE ${CXXWRAP_NAME}${CMAKE_LINK_LIBRARY_SUFFIX})
        set(CXXWRAP_RUNTIME_FILE ${CXXWRAP_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX})
    else()
        set(CXXWRAP_LINK_FILE lib${CXXWRAP_NAME}.dll.a)
        set(CXXWRAP_RUNTIME_FILE lib${CXXWRAP_NAME}.dll)
    endif()
else()
    if(APPLE)
        target_link_libraries(${CXXWRAP_TARGET} "-framework CoreFoundation")
    endif()
    set(CXXWRAP_LINK_FILE lib${CXXWRAP_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX})
    set(CXXWRAP_RUNTIME_FILE lib${CXXWRAP_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX})
endif()

# Installation
# ============

include(CMakePackageConfigHelpers)

# GNUInstallDirs "DATADIR" wrong here; CMake search path wants "share".
set(CXXWRAP_CMAKECONFIG_INSTALL_DIR "share/cmake/${PROJECT_NAME}" CACHE STRING "install path for cxx_wrapConfig.cmake")

install(TARGETS ${CXXWRAP_TARGET} EXPORT CxxWrapTargets
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        PUBLIC_HEADER DESTINATION ${CXXWRAP_INSTALL_INCLUDEDIR}/cxx_wrap)

configure_package_config_file(${PROJECT_NAME}Config.cmake.in
                              "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Config.cmake"
                              INSTALL_DESTINATION ${CXXWRAP_CMAKECONFIG_INSTALL_DIR})
write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake"
  VERSION ${${PROJECT_NAME}_VERSION}
  COMPATIBILITY AnyNewerVersion
)

install(EXPORT CxxWrapTargets
  FILE ${PROJECT_NAME}ConfigExports.cmake
  NAMESPACE CxxWrap::
  DESTINATION ${CXXWRAP_CMAKECONFIG_INSTALL_DIR}
)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Config.cmake
              ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake
              ${CMAKE_CURRENT_SOURCE_DIR}/FindJulia.cmake
  DESTINATION ${CXXWRAP_CMAKECONFIG_INSTALL_DIR}
)

if(CXXWRAP_BUILD_EXAMPLES)
  add_subdirectory(examples)
endif()
