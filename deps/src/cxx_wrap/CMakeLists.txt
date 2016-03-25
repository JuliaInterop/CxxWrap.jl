project(CxxWrap)

cmake_minimum_required(VERSION 3.1)

set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_INCLUDE_CURRENT_DIR_IN_INTERFACE ON)

set(CxxWrap_VERSION 0.1)

include(GenerateExportHeader)

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")

# TODO Figure out why this doesn't work on OS X:
#set(CMAKE_CXX_STANDARD 11)
#set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(JULIA_INCLUDE_DIRECTORY "/usr/include/julia" CACHE PATH "Julia include directory")
set(JULIA_LIBRARY "/usr/lib/julia/libjulia.so" CACHE FILEPATH "Julia library")

add_library(cxx_wrap SHARED
	array.hpp
	c_interface.cpp
	cxx_wrap.cpp
  type_conversion.hpp
)
target_include_directories(cxx_wrap PUBLIC ${JULIA_INCLUDE_DIRECTORY})
generate_export_header(cxx_wrap)

target_link_libraries(cxx_wrap ${JULIA_LIBRARY})

set_property(TARGET cxx_wrap PROPERTY VERSION ${CxxWrap_VERSION})
set_property(TARGET cxx_wrap PROPERTY SOVERSION 0)
set_property(TARGET cxx_wrap PROPERTY
	INTERFACE_cxx_wrap_MAJOR_VERSION 0)
set_property(TARGET cxx_wrap APPEND PROPERTY
	COMPATIBLE_INTERFACE_STRING cxx_wrap_MAJOR_VERSION
)

install(TARGETS cxx_wrap EXPORT CxxWrapTargets
	LIBRARY DESTINATION lib
	ARCHIVE DESTINATION lib
	RUNTIME DESTINATION lib
	INCLUDES DESTINATION include
)
install(
  FILES
    array.hpp
		cxx_wrap.hpp
    type_conversion.hpp
	DESTINATION
		include
	COMPONENT
		Devel
)

include(CMakePackageConfigHelpers)
write_basic_package_version_file(
	"${CMAKE_CURRENT_BINARY_DIR}/CxxWrapConfigVersion.cmake"
	VERSION ${CxxWrap_VERSION}
	COMPATIBILITY AnyNewerVersion
)

export(EXPORT CxxWrapTargets
  FILE "${CMAKE_CURRENT_BINARY_DIR}/CxxWrapConfig.cmake"
	NAMESPACE CxxWrap::
)

install(EXPORT CxxWrapTargets
  FILE
    CxxWrapConfig.cmake
  NAMESPACE
    CxxWrap::
  DESTINATION
    lib/cmake
)

install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/CxxWrapConfigVersion.cmake"
  DESTINATION
    lib/cmake
  COMPONENT
    Devel
)
