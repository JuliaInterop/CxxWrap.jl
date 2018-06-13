# Example on how to load types and methods from C++ into an existing module
module ExtendedTypes

include(joinpath(@__DIR__, "testcommon.jl"))

wrap_module(libextended, ExtendedTypes)

export ExtendedWorld, greet

end

using .ExtendedTypes
using Test

w = ExtendedWorld()
@test greet(w) == "default hello"
