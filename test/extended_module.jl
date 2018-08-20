# Example on how to load types and methods from C++ into an existing module
module ExtendedTypes

include(joinpath(@__DIR__, "testcommon.jl"))

@readmodule libextended
@wraptypes
@wrapfunctions

function __init__()
  @initcxx
end

export ExtendedWorld, greet

end

using .ExtendedTypes
using Test

w = ExtendedWorld()
@test greet(w) == "default hello"
