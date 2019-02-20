using BinaryProvider
using CxxWrap

products = Product[]
for basename in ["jlcxx_containers", "except", "extended", "functions", "hello", "inheritance", "parametric", "pointer_modification", "types"]
  fullname = "lib"*basename
  push!(products, LibraryProduct(CxxWrap.prefix(), fullname, Symbol(fullname)))
end

if any(!satisfied(p; verbose=true) for p in products)
  error("libcxxwrap-julia was not built with the example libraries required for testing")
end

write_deps_file(joinpath(@__DIR__, "deps.jl"), products)