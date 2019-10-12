module StdLib

using ..CxxWrap

abstract type CppBasicString <: AbstractString end

# These are defined in C++, but the functions need to exist to add methods
function append end
function cppsize end
function cxxgetindex end
function cxxsetindex! end
function push_back end
function resize end

@wrapmodule(CxxWrap.libcxxwrap_julia_stl)

function __init__()
  @initcxx
end

# Pass-through for fundamental types
_append_dispatch(v::StdVector,a::Vector,::Type{CxxWrap.IsNormalType}) = append(v,a)
# For C++ types, convert the array to an array of references, so the pointers can be read directly from a contiguous array on the C++ side
_append_dispatch(v::StdVector{T}, a::Vector{<:T},::Type{CxxWrap.IsCxxType}) where {T} = append(v,CxxWrap.CxxRef.(a))
# Choose the correct append method depending on the type trait
append(v::StdVector{T}, a::Vector{<:T}) where {T} = _append_dispatch(v,a,CxxWrap.cpp_trait_type(T))

Base.ncodeunits(s::CppBasicString)::Int = cppsize(s)
Base.codeunit(s::StdString) = UInt8
Base.codeunit(s::StdWString) = Cwchar_t == Int32 ? UInt32 : UInt16
Base.codeunit(s::CppBasicString, i::Integer) = s[i]
Base.isvalid(s::CppBasicString, i::Integer) = (0 < i <= ncodeunits(s))
function Base.iterate(s::CppBasicString, i::Integer=1)
  if !isvalid(s,i)
    return nothing
  end
  return(convert(Char,codeunit(s,i)),i+1)
end

Base.:(==)(x::CxxWrap.ConstCxxRef{CxxWrap.StdLib.StdString}, y) = x[] == y

function StdWString(s::String)
  char_arr = transcode(Cwchar_t, s)
  StdWString(char_arr, length(char_arr))
end

function StdVector(v::Vector{T}) where {T}
  if (CxxWrap.cpp_trait_type(T) == CxxWrap.IsCxxType)
    return StdVector(CxxRef.(v))
  end
  result = StdVector{T}()
  append(result, v)
  return result
end

function StdVector(v::Vector{CxxRef{T}}) where {T}
  result = isconcretetype(T) ? StdVector{supertype(T)}() : StdVector{T}()
  append(result, v)
  return result
end

function StdVector(v::Vector{Bool})
  result = StdVector{CxxBool}()
  append(result, convert(Vector{CxxBool}, v))
  return result
end

Base.IndexStyle(::Type{<:StdVector}) = IndexLinear()
Base.size(v::StdVector) = (Int(cppsize(v)),)
Base.getindex(v::StdVector, i::Int) = cxxgetindex(v,i)[]
Base.setindex!(v::StdVector{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T,val), i)

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

function Base.append!(v::StdVector{CxxBool}, a::Vector{Bool})
  append(v, convert(Vector{CxxBool}, a))
  return v
end

# Make sure functions taking a C++ string as argument can also take a Julia string
CxxWrap.map_julia_arg_type(x::Type{<:StdString}) = AbstractString
Base.convert(::Type{T}, x::String) where {T<:StdString} = StdString(x)
Base.cconvert(::Type{CxxWrap.ConstCxxRef{StdString}}, x::String) = StdString(x)
Base.unsafe_convert(::Type{CxxWrap.ConstCxxRef{StdString}}, x::StdString) = ConstCxxRef(x)

end
