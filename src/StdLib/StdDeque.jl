using .StdLib: StdDeque

Base.IndexStyle(::Type{<:StdDeque}) = IndexLinear()
Base.size(v::StdDeque) = (Int(cppsize(v)),)
Base.getindex(v::StdDeque, i::Int) = cxxgetindex(v, i)[]
Base.setindex!(v::StdDeque{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T, val), i)
Base.push!(v::StdDeque, x) = push_back!(v, x)
Base.pushfirst!(v::StdDeque, x) = push_front!(v, x)
Base.pop!(v::StdDeque) = pop_back!(v)
Base.popfirst!(v::StdDeque) = pop_front!(v)
Base.resize!(v::StdDeque, n::Integer) = resize!(v, n)