using BinaryProvider

const JLCXX_DIR = get(ENV, "JLCXX_DIR", "")
const prefix = Prefix(JLCXX_DIR == "" ? !isempty(ARGS) ? ARGS[1] : joinpath(@__DIR__,"usr") : JLCXX_DIR)

products = Product[
    LibraryProduct(prefix, "libcxxwrap_julia", :libcxxwrap_julia)
]

if any(!satisfied(p; verbose=true) for p in products)
    # TODO: Add download code here
end

write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
