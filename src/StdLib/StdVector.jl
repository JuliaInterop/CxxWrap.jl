using .StdLib: StdVector

# Pass-through for fundamental types
_append_dispatch(v::StdVector, a::Vector, ::Type{CxxWrapCore.IsNormalType}) = append(v, a)
# For C++ types, convert the array to an array of references, so the pointers can be read directly from a contiguous array on the C++ side
_append_dispatch(v::StdVector{T}, a::Vector{<:T}, ::Type{CxxWrapCore.IsCxxType}) where {T} = append(v, CxxWrapCore.CxxRef.(a))
# Choose the correct append method depending on the type trait
append(v::StdVector{T}, a::Vector{<:T}) where {T} = _append_dispatch(v, a, CxxWrapCore.cpp_trait_type(T))

function StdVector{T}(v::Union{Vector{T},Vector{CxxRef{T}}}) where {T}
    result = StdVector{T}()
    isempty(v) || append(result, v)
    return result
end

StdVector{T}(v::Vector) where {T} = StdVector{T}(convert(Vector{T}, v))

function StdVector(v::Vector{CxxRef{T}}) where {T}
    S = isconcretetype(T) ? supertype(T) : T
    return StdVector{S}(v)
end

function StdVector(v::Vector{T}) where {T}
    S = if isconcretetype(T) && CxxWrapCore.cpp_trait_type(T) == CxxWrapCore.IsCxxType
        supertype(T)
    else
        T
    end
    return StdVector{S}(v)
end

StdVector(v::Vector{Bool}) = StdVector{CxxBool}(v)

Base.IndexStyle(::Type{<:StdVector}) = IndexLinear()
Base.size(v::StdVector) = (Int(cppsize(v)),)
Base.getindex(v::StdVector, i::Int) = cxxgetindex(v, i)[]
Base.getindex(v::StdVector{<:Tuple}, i::Int) = cxxgetindex(v, i)
Base.setindex!(v::StdVector{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T, val), i)

@cxxdereference function Base.push!(v::StdVector, x)
    push_back(v, x)
    return v
end

@cxxdereference function Base.resize!(v::StdVector, n::Integer)
    resize(v, n)
    return v
end

@cxxdereference Base.empty!(v::StdVector) = Base.resize!(v, 0)

@cxxdereference function Base.append!(v::StdVector, a::Vector)
    append(v, a)
    return v
end

@cxxdereference function Base.append!(v::StdVector{CxxBool}, a::Vector{Bool})
    append(v, convert(Vector{CxxBool}, a))
    return v
end
