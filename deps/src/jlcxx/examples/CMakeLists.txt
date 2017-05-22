include_directories(${CMAKE_SOURCE_DIR}/include)

add_library(functions SHARED functions.cpp)
set_target_properties(functions PROPERTIES COMPILE_DEFINITIONS "JLCXX_EXAMPLES_EXPORTS")

target_link_libraries(functions ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(hello SHARED hello.cpp)
target_link_libraries(hello ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(types SHARED types.cpp)
target_link_libraries(types ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(inheritance SHARED inheritance.cpp)
target_link_libraries(inheritance ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(parametric SHARED parametric.cpp)
target_link_libraries(parametric ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(extended SHARED extended.cpp)
target_link_libraries(extended ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(jlcxx_containers SHARED containers.cpp)
target_link_libraries(jlcxx_containers ${JLCXX_TARGET} ${Julia_LIBRARY})

add_library(except SHARED except.cpp)
target_include_directories(except PRIVATE ${Julia_INCLUDE_DIRS})
target_link_libraries(except ${JLCXX_TARGET})

install(TARGETS
  jlcxx_containers
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
INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/jlcxx-examples)
