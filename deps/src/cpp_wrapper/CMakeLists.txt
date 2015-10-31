project(CppWrapper)

cmake_minimum_required(VERSION 3.1)

set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_INCLUDE_CURRENT_DIR_IN_INTERFACE ON)

set(CppWrapper_VERSION 0.1)

list(APPEND CMAKE_CXX_FLAGS "-std=c++11")

set(JULIA_INCLUDE_DIRECTORY "/usr/include/julia" CACHE PATH "Julia include directory")
set(JULIA_LIBRARY "/usr/lib/julia/libjulia.so" CACHE FILEPATH "Julia library")

include_directories(${JULIA_INCLUDE_DIRECTORY})

add_library(cpp_wrapper SHARED cpp_wrapper.cpp)

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
	RUNTIME DESTINATION bin
	INCLUDES DESTINATION include
)
install(
	FILES
		cpp_wrapper.hpp
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
