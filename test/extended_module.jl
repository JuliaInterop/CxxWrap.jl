# Example on how to load types and methods from C++ into an existing module
module ExtendedTypes

include(joinpath(@__DIR__, "testcommon.jl"))

@readmodule CxxWrap.CxxWrapCore.libextended()
@wraptypes
@wrapfunctions

function __init__()
  @initcxx
end

export ExtendedWorld, greet

end

using .ExtendedTypes
using Test

@testset "$(basename(@__FILE__)[1:end-3])" begin

w = ExtendedWorld()
@test greet(w) == "default hello"

end