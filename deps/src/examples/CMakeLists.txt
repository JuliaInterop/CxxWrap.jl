project(Examples)

cmake_minimum_required(VERSION 3.1)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")

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

install(TARGETS
  functions
  hello
  inheritance
  parametric
  types
LIBRARY DESTINATION lib
ARCHIVE DESTINATION lib
RUNTIME DESTINATION lib
INCLUDES DESTINATION include)
