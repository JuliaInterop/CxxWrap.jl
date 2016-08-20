using Compat

myname = splitdir(@__FILE__)[end]

excluded = []

if is_windows() && Sys.WORD_SIZE == 32
  push!(excluded, "except.jl")
end

for fname in readdir()
  if fname != myname && endswith(fname, ".jl") && fname ∉ excluded
    println("running test ", fname, "...")
    include(fname)
  end
end
