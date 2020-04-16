module StdLib

using ..CxxWrapCore

abstract type CppBasicString <: AbstractString end

# These are defined in C++, but the functions need to exist to add methods
function append end
function cppsize end
function cxxgetindex end
function cxxsetindex! end
function push_back end
function resize end

import Libdl
import libcxxwrap_julia_jll
@wrapmodule(libcxxwrap_julia_jll.libcxxwrap_julia_stl, :define_cxxwrap_stl_module, Libdl.RTLD_GLOBAL)

function __init__()
  @initcxx
end

# Pass-through for fundamental types
_append_dispatch(v::StdVector,a::Vector,::Type{CxxWrapCore.IsNormalType}) = append(v,a)
# For C++ types, convert the array to an array of references, so the pointers can be read directly from a contiguous array on the C++ side
_append_dispatch(v::StdVector{T}, a::Vector{<:T},::Type{CxxWrapCore.IsCxxType}) where {T} = append(v,CxxWrapCore.CxxRef.(a))
# Choose the correct append method depending on the type trait
append(v::StdVector{T}, a::Vector{<:T}) where {T} = _append_dispatch(v,a,CxxWrapCore.cpp_trait_type(T))

Base.ncodeunits(s::CppBasicString)::Int = cppsize(s)
Base.codeunit(s::StdString) = UInt8
Base.codeunit(s::StdWString) = Cwchar_t == Int32 ? UInt32 : UInt16
Base.codeunit(s::CppBasicString, i::Integer) = reinterpret(codeunit(s), s[i])
Base.isvalid(s::CppBasicString, i::Integer) = (0 < i <= ncodeunits(s))
function Base.iterate(s::CppBasicString, i::Integer=1)
  if !isvalid(s,i)
    return nothing
  end
  return(convert(Char,codeunit(s,i)),i+1)
end

function StdWString(s::String)
  char_arr = transcode(Cwchar_t, s)
  StdWString(char_arr, length(char_arr))
end

function StdVector(v::Vector{T}) where {T}
  if (CxxWrapCore.cpp_trait_type(T) == CxxWrapCore.IsCxxType)
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

@cxxdereference Base.String(s::StdString) = unsafe_string(reinterpret(Ptr{Cchar},c_str(s).cpp_object))
@cxxdereference function Base.String(s::StdWString)
  chars = unsafe_wrap(Vector{Cwchar_t}, reinterpret(Ptr{Cwchar_t},c_str(s).cpp_object), (cppsize(s),))
  return transcode(String, chars)
end
Base.show(io::IO, s::CppBasicString) = show(io, String(s))
Base.cmp(a::CppBasicString, b::String) = cmp(String(a),b)
Base.cmp(a::String, b::CppBasicString) = cmp(a,String(b))

# Make sure functions taking a C++ string as argument can also take a Julia string
CxxWrapCore.map_julia_arg_type(x::Type{<:StdString}) = AbstractString
Base.convert(::Type{T}, x::String) where {T<:StdString} = StdString(x)
Base.cconvert(::Type{CxxWrapCore.ConstCxxRef{StdString}}, x::String) = StdString(x)
Base.unsafe_convert(::Type{CxxWrapCore.ConstCxxRef{StdString}}, x::StdString) = ConstCxxRef(x)

function StdValArray(v::Vector{T}) where {T}
  return StdValArray{T}(v, length(v))
end

Base.IndexStyle(::Type{<:StdValArray}) = IndexLinear()
Base.size(v::StdValArray) = (Int(cppsize(v)),)
Base.getindex(v::StdValArray, i::Int) = cxxgetindex(v,i)[]
Base.setindex!(v::StdValArray{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T,val), i)

end