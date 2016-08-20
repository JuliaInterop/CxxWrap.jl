# Example on how to load types and methods from C++ into an existing module
using Base.Test

module ExtendedTypes

using CxxWrap

wrap_module(CxxWrap._l_extended)

export ExtendedWorld, greet

end

using ExtendedTypes

w = ExtendedWorld()
@test greet(w) == "default hello"
