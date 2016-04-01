# Example on how to load types and methods from C++ into an existing module

println("Running extended_module.jl...")
using Base.Test

module ExtendedTypes

using CxxWrap

wrap_module(joinpath(Pkg.dir("CxxWrap"),"deps","usr","lib","libextended"))

export ExtendedWorld, greet

end

using ExtendedTypes

w = ExtendedWorld()
@test greet(w) == "default hello"
