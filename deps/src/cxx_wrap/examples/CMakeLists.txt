include_directories(${CMAKE_SOURCE_DIR}/include)

add_library(functions SHARED functions.cpp)
set_target_properties(functions PROPERTIES COMPILE_DEFINITIONS "CXXWRAP_EXAMPLES_EXPORTS")

target_link_libraries(functions ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(hello SHARED hello.cpp)
target_link_libraries(hello ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(types SHARED types.cpp)
target_link_libraries(types ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(inheritance SHARED inheritance.cpp)
target_link_libraries(inheritance ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(parametric SHARED parametric.cpp)
target_link_libraries(parametric ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(extended SHARED extended.cpp)
target_link_libraries(extended ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(cxxwrap_containers SHARED containers.cpp)
target_link_libraries(cxxwrap_containers ${CXXWRAP_TARGET} ${Julia_LIBRARY})

add_library(except SHARED except.cpp)
target_include_directories(except PRIVATE ${Julia_INCLUDE_DIRS})
target_link_libraries(except ${CXXWRAP_TARGET})

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
