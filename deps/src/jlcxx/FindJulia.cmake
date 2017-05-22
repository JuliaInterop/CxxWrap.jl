
if(Julia_FOUND)
    return()
endif()

####################
# Julia Executable #
####################

find_program(Julia_EXECUTABLE julia DOC "Julia executable")
MESSAGE(STATUS "Julia_EXECUTABLE:     ${Julia_EXECUTABLE}")

#################
# Julia Version #
#################

execute_process(
    COMMAND ${Julia_EXECUTABLE} --version
    OUTPUT_VARIABLE Julia_VERSION_STRING
)

string(
    REGEX REPLACE ".*([0-9]+\\.[0-9]+\\.[0-9]+).*" "\\1"
      Julia_VERSION_STRING ${Julia_VERSION_STRING}
)

MESSAGE(STATUS "Julia_VERSION_STRING: ${Julia_VERSION_STRING}")

##################
# Julia Includes #
##################

execute_process(
    COMMAND ${Julia_EXECUTABLE} -E "julia_include_dir = joinpath(match(r\"(.*)(bin)\",JULIA_HOME).captures[1],\"include\",\"julia\")\n
        if !isdir(julia_include_dir)  # then we're running directly from build\n
          julia_base_dir_aux = splitdir(splitdir(JULIA_HOME)[1])[1]  # useful for running-from-build\n
          julia_include_dir = joinpath(julia_base_dir_aux, \"usr\", \"include\" )\n
          julia_include_dir *= \";\" * joinpath(julia_base_dir_aux, \"src\", \"support\" )\n
          julia_include_dir *= \";\" * joinpath(julia_base_dir_aux, \"src\" )\n
        end\n
        julia_include_dir"
    OUTPUT_VARIABLE Julia_INCLUDE_DIRS
)

string(REGEX REPLACE "\"" "" Julia_INCLUDE_DIRS ${Julia_INCLUDE_DIRS})
string(REGEX REPLACE "\n" "" Julia_INCLUDE_DIRS ${Julia_INCLUDE_DIRS})
set(Julia_INCLUDE_DIRS ${Julia_INCLUDE_DIRS}
    CACHE PATH "Location of Julia include files")

MESSAGE(STATUS "Julia_INCLUDE_DIRS:   ${Julia_INCLUDE_DIRS}")

###################
# Julia Libraries #
###################

execute_process(
    COMMAND ${Julia_EXECUTABLE} -E "abspath(dirname(Libdl.dlpath(\"libjulia\")))"
    OUTPUT_VARIABLE Julia_LIBRARY_DIR
)

string(REGEX REPLACE "\"" "" Julia_LIBRARY_DIR ${Julia_LIBRARY_DIR})
string(REGEX REPLACE "\n" "" Julia_LIBRARY_DIR ${Julia_LIBRARY_DIR})

string(STRIP ${Julia_LIBRARY_DIR} Julia_LIBRARY_DIR)
set(Julia_LIBRARY_DIR ${Julia_LIBRARY_DIR}
    CACHE PATH "Julia library directory")

if(WIN32)
    set(CMAKE_FIND_LIBRARY_SUFFIXES ${CMAKE_FIND_LIBRARY_SUFFIXES} .a)
    find_library(Julia_LIBRARY
        NAMES libjulia.dll.a
        PATHS ${Julia_LIBRARY_DIR}//..//lib
        NO_DEFAULT_PATH
    )
else()
    find_library(Julia_LIBRARY
        NAMES julia libjulia
        PATHS ${Julia_LIBRARY_DIR}
        NO_DEFAULT_PATH
    )
endif()

MESSAGE(STATUS "Julia_LIBRARY_DIR:    ${Julia_LIBRARY_DIR}")
MESSAGE(STATUS "Julia_LIBRARY:        ${Julia_LIBRARY}")

##############
# JULIA_HOME #
##############

execute_process(
    COMMAND ${Julia_EXECUTABLE} -E "JULIA_HOME"
    OUTPUT_VARIABLE JULIA_HOME
)

string(REGEX REPLACE "\"" "" JULIA_HOME ${JULIA_HOME})
string(REGEX REPLACE "\n" "" JULIA_HOME ${JULIA_HOME})

MESSAGE(STATUS "JULIA_HOME:           ${JULIA_HOME}")

###################
# libLLVM version #
###################

execute_process(
    COMMAND ${Julia_EXECUTABLE} -E "Base.libllvm_version"
    OUTPUT_VARIABLE Julia_LLVM_VERSION
)

string(REGEX REPLACE "\"" "" Julia_LLVM_VERSION ${Julia_LLVM_VERSION})
string(REGEX REPLACE "\n" "" Julia_LLVM_VERSION ${Julia_LLVM_VERSION})

##################################
# Check for Existence of Headers #
##################################

find_path(Julia_MAIN_HEADER julia.h HINTS ${Julia_INCLUDE_DIRS})

MESSAGE(STATUS "Julia_LLVM_VERSION:   ${Julia_LLVM_VERSION}")

###########################
# FindPackage Boilerplate #
###########################

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Julia
    REQUIRED_VARS   Julia_LIBRARY Julia_LIBRARY_DIR Julia_INCLUDE_DIRS
    VERSION_VAR     Julia_VERSION_STRING
    FAIL_MESSAGE    "Julia not found"
)
