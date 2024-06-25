using .StdLib: StdValArray

function StdValArray(v::Vector{T}) where {T}
    return StdValArray{T}(v, length(v))
end

Base.IndexStyle(::Type{<:StdValArray}) = IndexLinear()
Base.size(v::StdValArray) = (Int(cppsize(v)),)
Base.getindex(v::StdValArray, i::Int) = cxxgetindex(v, i)[]
Base.setindex!(v::StdValArray{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T, val), i)