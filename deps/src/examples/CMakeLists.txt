project(Examples)

cmake_minimum_required(VERSION 2.8.12)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../cxx_wrap/)

set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_MACOSX_RPATH 1)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
add_definitions(-DJULIA_ENABLE_THREADING)

if(WIN32 AND DEFINED ENV{MSYSTEM})
  if($ENV{MSYSTEM} STREQUAL "MINGW32")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=pentium4 -static-libstdc++")
  endif()
endif()

find_package(CxxWrap)
find_package(Julia)

include_directories(${CxxWrap_INCLUDE_DIRS})
include_directories(${Julia_INCLUDE_DIRS})

add_library(functions SHARED src/functions.cpp)
set_target_properties(functions PROPERTIES COMPILE_DEFINITIONS "CXXWRAP_EXAMPLES_EXPORTS")

MESSAGE(STATUS ${CxxWrap_LIBRARY})
target_link_libraries(functions ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(hello SHARED src/hello.cpp)
target_link_libraries(hello ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(types SHARED src/types.cpp)
target_link_libraries(types ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(inheritance SHARED src/inheritance.cpp)
target_link_libraries(inheritance ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(parametric SHARED src/parametric.cpp)
target_link_libraries(parametric ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(extended SHARED src/extended.cpp)
target_link_libraries(extended ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(cxxwrap_containers SHARED src/containers.cpp)
target_link_libraries(cxxwrap_containers ${CxxWrap_LIBRARY} ${Julia_LIBRARY})

add_library(except SHARED src/except.cpp)
target_include_directories(except PRIVATE ${Julia_INCLUDE_DIRS})
target_link_libraries(except ${Julia_LIBRARY})

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

install(TARGETS
  cxxwrap_containers
  except
  extended
  functions
  hello
  inheritance
  parametric
  types
ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cxx_wrap-examples)
