using BinaryProvider
using CxxWrap

libdir = dirname(CxxWrap.jlcxx_path)
if isfile(joinpath(libdir,"CMakeCache.txt"))
  libdir = joinpath(libdir,"examples")
end

products = Product[]
for basename in ["jlcxx_containers", "except", "extended", "functions", "hello", "inheritance", "parametric", "types"]
  fullname = "lib"*basename
  push!(products, LibraryProduct(libdir, fullname, Symbol(fullname)))
end

write_deps_file(joinpath(@__DIR__, "deps.jl"), products)