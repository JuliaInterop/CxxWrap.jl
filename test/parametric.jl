# Hello world example, similar to the Boost.Python hello world

using CppWrapper
using Base.Test

# Wrap the functions defined in C++
wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libparametric"))

xdump(ParametricTypes.Parametric)
xdump(ParametricTypes.SimpleParametric)

@show sp = ParametricTypes.SimpleParametric{Int32}()
