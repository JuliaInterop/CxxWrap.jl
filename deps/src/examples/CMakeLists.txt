project(Examples)

cmake_minimum_required(VERSION 3.1)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")

set(CppWrapper_DIR "${CMAKE_CURRENT_BINARY_DIR}/../../usr/lib/cmake")
find_package(CppWrapper)

add_library(functions SHARED functions.cpp)
target_link_libraries(functions CppWrapper::cpp_wrapper)

add_library(hello SHARED hello.cpp)
target_link_libraries(hello CppWrapper::cpp_wrapper)

add_library(types SHARED types.cpp)
target_link_libraries(types CppWrapper::cpp_wrapper)

add_library(inheritance SHARED inheritance.cpp)
target_link_libraries(inheritance CppWrapper::cpp_wrapper)

add_library(parametric SHARED parametric.cpp)
target_link_libraries(parametric CppWrapper::cpp_wrapper)

install(TARGETS
  functions
  hello
  inheritance
  parametric
  types
LIBRARY DESTINATION lib)
