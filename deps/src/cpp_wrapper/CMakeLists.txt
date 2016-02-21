project(CppWrapper)

cmake_minimum_required(VERSION 3.1)

set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_INCLUDE_CURRENT_DIR_IN_INTERFACE ON)

set(CppWrapper_VERSION 0.1)

include(GenerateExportHeader)

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")

# TODO Figure out why this doesn't work on OS X:
#set(CMAKE_CXX_STANDARD 11)
#set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(JULIA_INCLUDE_DIRECTORY "/usr/include/julia" CACHE PATH "Julia include directory")
set(JULIA_LIBRARY "/usr/lib/julia/libjulia.so" CACHE FILEPATH "Julia library")

add_library(cpp_wrapper SHARED
	array.hpp
	c_interface.cpp
	cpp_wrapper.cpp
  type_conversion.hpp
)
target_include_directories(cpp_wrapper PUBLIC ${JULIA_INCLUDE_DIRECTORY})
generate_export_header(cpp_wrapper)

target_link_libraries(cpp_wrapper ${JULIA_LIBRARY})

set_property(TARGET cpp_wrapper PROPERTY VERSION ${CppWrapper_VERSION})
set_property(TARGET cpp_wrapper PROPERTY SOVERSION 0)
set_property(TARGET cpp_wrapper PROPERTY
	INTERFACE_cpp_wrapper_MAJOR_VERSION 0)
set_property(TARGET cpp_wrapper APPEND PROPERTY
	COMPATIBLE_INTERFACE_STRING cpp_wrapper_MAJOR_VERSION
)

install(TARGETS cpp_wrapper EXPORT CppWrapperTargets
	LIBRARY DESTINATION lib
	ARCHIVE DESTINATION lib
	RUNTIME DESTINATION lib
	INCLUDES DESTINATION include
)
install(
  FILES
    array.hpp
		cpp_wrapper.hpp
    type_conversion.hpp
	DESTINATION
		include
	COMPONENT
		Devel
)

include(CMakePackageConfigHelpers)
write_basic_package_version_file(
	"${CMAKE_CURRENT_BINARY_DIR}/CppWrapperConfigVersion.cmake"
	VERSION ${CppWrapper_VERSION}
	COMPATIBILITY AnyNewerVersion
)

export(EXPORT CppWrapperTargets
  FILE "${CMAKE_CURRENT_BINARY_DIR}/CppWrapperConfig.cmake"
	NAMESPACE CppWrapper::
)

install(EXPORT CppWrapperTargets
  FILE
    CppWrapperConfig.cmake
  NAMESPACE
    CppWrapper::
  DESTINATION
    lib/cmake
)

install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/CppWrapperConfigVersion.cmake"
  DESTINATION
    lib/cmake
  COMPONENT
    Devel
)
