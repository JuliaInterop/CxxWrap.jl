using CppWrapper
using Base.Test

# Wrap the functions defined in C++
CppWrapper.wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libfunctions"))
