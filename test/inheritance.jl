# Hello world example, similar to the Boost.Python hello world

using CxxWrap
using Base.Test

# Wrap the functions defined in C++
wrap_modules(CxxWrap._l_inheritance)

using CppInheritance

# Default constructor
b = B()
@test message(b) == "B"

@test message(create_abstract()) == "B"
