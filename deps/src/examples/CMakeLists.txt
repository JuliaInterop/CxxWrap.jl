project(Examples)

cmake_minimum_required(VERSION 2.8.12)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")
set(CMAKE_MACOSX_RPATH 1)

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")
add_definitions(-DJULIA_ENABLE_THREADING)

if(WIN32 AND DEFINED ENV{MSYSTEM})
  if($ENV{MSYSTEM} STREQUAL "MINGW32")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=pentium4")
  endif()
endif()

set(CxxWrap_DIR "${CMAKE_CURRENT_BINARY_DIR}/../../usr/lib/cmake")
find_package(CxxWrap)

add_library(functions SHARED functions.cpp)
target_link_libraries(functions CxxWrap::cxx_wrap)

add_library(hello SHARED hello.cpp)
target_link_libraries(hello CxxWrap::cxx_wrap)

add_library(types SHARED types.cpp)
target_link_libraries(types CxxWrap::cxx_wrap)

add_library(inheritance SHARED inheritance.cpp)
target_link_libraries(inheritance CxxWrap::cxx_wrap)

add_library(parametric SHARED parametric.cpp)
target_link_libraries(parametric CxxWrap::cxx_wrap)

add_library(extended SHARED extended.cpp)
target_link_libraries(extended CxxWrap::cxx_wrap)

add_library(cxxwrap_containers SHARED containers.cpp)
target_link_libraries(cxxwrap_containers CxxWrap::cxx_wrap)

get_property(JULIA_LIBRARY TARGET CxxWrap::cxx_wrap PROPERTY INTERFACE_LINK_LIBRARIES)
get_property(JULIA_INCLUDES TARGET CxxWrap::cxx_wrap PROPERTY INTERFACE_INCLUDE_DIRECTORIES)
add_library(except SHARED except.cpp)
target_include_directories(except PRIVATE ${JULIA_INCLUDES})
target_link_libraries(except ${JULIA_LIBRARY})

install(TARGETS
  cxxwrap_containers
  except
  extended
  functions
  hello
  inheritance
  parametric
  types
LIBRARY DESTINATION lib${LIBDIR_SUFFIX}
ARCHIVE DESTINATION lib${LIBDIR_SUFFIX}
RUNTIME DESTINATION lib${LIBDIR_SUFFIX}
INCLUDES DESTINATION include)
