module StdLib

using ..CxxWrap

@wrapmodule(CxxWrap.libcxxwrap_julia_stl)

function __init__()
  @initcxx
end

function StdVector(v::Vector{T}) where {T}
  result = StdVector{T}()
  append(result, v)
  return result
end

function StdVector(v::Vector{T}) where {T<:AbstractString}
  result = StdVector{AbstractString}()
  append(result, v)
  return result
end

Base.IndexStyle(::Type{<:StdVector}) = IndexLinear()
Base.size(v::StdVector) = (Int(cppsize(v)),)

function Base.push!(v::StdVector, x)
  push_back(v, x)
  return v
end

function Base.resize!(v::StdVector, n::Integer)
  resize(v, n)
  return v
end

Base.empty!(v::StdVector) = Base.resize!(v, 0)

function Base.append!(v::StdVector, a::Vector)
  append(v, a)
  return v
end

end