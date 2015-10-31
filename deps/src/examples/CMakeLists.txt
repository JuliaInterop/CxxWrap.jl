project(Examples)

cmake_minimum_required(VERSION 3.1)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")

set(CppWrapper_DIR "${CMAKE_CURRENT_BINARY_DIR}/../cpp_wrapper")
find_package(CppWrapper)

add_library(functions SHARED functions.cpp)
target_link_libraries(functions CppWrapper::cpp_wrapper)

install(TARGETS functions LIBRARY DESTINATION lib)
