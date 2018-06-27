using BinaryProvider

const JLCXX_LIBDIR = get(ENV, "JLCXX_LIBDIR", "")
const prefix = Prefix(JLCXX_LIBDIR == "" ? !isempty(ARGS) ? ARGS[1] : joinpath(@__DIR__,"usr") : JLCXX_LIBDIR)

products = Product[
    LibraryProduct(prefix, "libcxxwrap_julia", :libcxxwrap_julia)
]

if any(!satisfied(p; verbose=true) for p in products)
    # TODO: Add download code here
end

write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
