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

function get_libcxxwrap_julia_stl_path()::AbstractString
  libcxxwrap_julia_jll.libcxxwrap_julia_stl
end

@wrapmodule(get_libcxxwrap_julia_stl_path, :define_cxxwrap_stl_module, Libdl.RTLD_GLOBAL)

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
Base.codeunit(s::CppBasicString, i::Integer) = reinterpret(codeunit(s), cxxgetindex(s,i))
Base.isvalid(s::CppBasicString, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i
@inline Base.between(b::T1, lo::T2, hi::T2) where {T1<:Integer,T2<:Integer} = (lo ≤ b) & (b ≤ hi)
Base.thisind(s::CppBasicString, i::Int) = Base._thisind_str(s, i)
Base.nextind(s::CppBasicString, i::Int) = Base._nextind_str(s, i)

function Base.iterate(s::CppBasicString, i::Integer=firstindex(s))
  i > ncodeunits(s) && return nothing
  return convert(Char, codeunit(s, i)), nextind(s, i)
end

# Since the Julia base string iteration is `String` specific we need to implement our own.
# This implementation is based around a functioning `nextind` which allows us to convert the
# UTF-8 codeunits into their big-endian encoding.
function Base.iterate(s::StdString, i::Integer=firstindex(s))
  i > ncodeunits(s) && return nothing
  j = isvalid(s, i) ? nextind(s, i) : i + 1
  u = UInt32(codeunit(s, i)) << 24
  (i += 1) < j || @goto ret
  u |= UInt32(codeunit(s, i)) << 16
  (i += 1) < j || @goto ret
  u |= UInt32(codeunit(s, i)) << 8
  (i += 1) < j || @goto ret
  u |= UInt32(codeunit(s, i))
  @label ret
  return reinterpret(Char, u), j
end

function Base.getindex(s::CppBasicString, i::Int)
  checkbounds(s, i)
  isvalid(s, i) || Base.string_index_err(s, i)
  c, i = iterate(s, i)
  return c
end

function StdWString(s::String)
  char_arr = transcode(Cwchar_t, s)
  StdWString(char_arr, length(char_arr))
end

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

@cxxdereference Base.String(s::StdString) = unsafe_string(reinterpret(Ptr{Cchar},c_str(s).cpp_object), cppsize(s))
@cxxdereference function Base.String(s::StdWString)
  chars = unsafe_wrap(Vector{Cwchar_t}, reinterpret(Ptr{Cwchar_t},c_str(s).cpp_object), (cppsize(s),))
  return transcode(String, chars)
end
Base.show(io::IO, s::CppBasicString) = show(io, String(s))
Base.cmp(a::CppBasicString, b::String) = cmp(String(a),b)
Base.cmp(a::String, b::CppBasicString) = cmp(a,String(b))

# Make sure functions taking a C++ string as argument can also take a Julia string
CxxWrapCore.map_julia_arg_type(x::Type{<:StdString}) = AbstractString

"""
    StdString(str::String)

Create a `StdString` from the contents of the string. Any null-characters ('\\0') will be
included in the string such that `ncodeunits(str) == ncodeunits(StdString(str))`.
"""
StdString(x::String) = StdString(x, ncodeunits(x))

"""
    StdString(str::Union{Cstring, Base.CodeUnits, Vector{UInt8}, Ref{Int8}, Array{Int8}})

Create a `StdString` from the null-terminated character sequence.

If you want to  construct a `StdString` that includes the null-character ('\\0') either use
[`StdString(::String)`](@ref) or [`StdString(::Any, ::Int)`](@ref).

## Examples

```julia
julia> StdString(b"visible\\0hidden")
"visible"
```
"""
StdString(::Union{Cstring, Base.CodeUnits, Vector{UInt8}, Ref{Int8}, Array{Int8}})

StdString(x::Cstring) = StdString(convert(Ptr{Int8}, x))
StdString(x::Base.CodeUnits) = StdString(collect(x))
StdString(x::Vector{UInt8}) = StdString(collect(reinterpret(Int8, x)))

"""
    StdString(str, n::Integer)

Create a `StdString` from the first `n` code units of `str` (including null-characters).

## Examples

```julia
julia> StdString("visible\\0hidden", 10)
"visible\\0hi"
```
"""
StdString(::Any, ::Integer)

Base.cconvert(::Type{CxxWrapCore.ConstCxxRef{StdString}}, x::String) = StdString(x, ncodeunits(x))
Base.cconvert(::Type{StdLib.StdStringDereferenced}, x::String) = StdString(x, ncodeunits(x))
Base.unsafe_convert(::Type{CxxWrapCore.ConstCxxRef{StdString}}, x::StdString) = ConstCxxRef(x)

function StdValArray(v::Vector{T}) where {T}
  return StdValArray{T}(v, length(v))
end

Base.IndexStyle(::Type{<:StdValArray}) = IndexLinear()
Base.size(v::StdValArray) = (Int(cppsize(v)),)
Base.getindex(v::StdValArray, i::Int) = cxxgetindex(v,i)[]
Base.setindex!(v::StdValArray{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T,val), i)

Base.IndexStyle(::Type{<:StdDeque}) = IndexLinear()
Base.size(v::StdDeque) = (Int(cppsize(v)),)
Base.getindex(v::StdDeque, i::Int) = cxxgetindex(v,i)[]
Base.setindex!(v::StdDeque{T}, val, i::Int) where {T} = cxxsetindex!(v, convert(T,val), i)
Base.push!(v::StdDeque, x) = push_back!(v, x)
Base.pushfirst!(v::StdDeque, x) = push_front!(v, x)
Base.pop!(v::StdDeque) = pop_back!(v)
Base.popfirst!(v::StdDeque) = pop_front!(v)
Base.resize!(v::StdDeque, n::Integer) = resize!(v, n)

Base.size(v::StdQueue) = (Int(cppsize(v)),)
Base.push!(v::StdQueue, x) = push_back!(v, x)
Base.first(v::StdQueue) = front(v)
Base.pop!(v::StdQueue) = pop_front!(v)

for StdSetType in (StdSet, StdUnorderedSet)
  Base.size(v::StdSetType) = (Int(cppsize(v)),)
  Base.length(v::StdSetType) = Int(cppsize(v))
  Base.isempty(v::StdSetType) = set_isempty(v)
  Base.empty!(v::StdSetType) = (set_empty!(v); v)
  Base.push!(v::StdSetType, x) = (set_insert!(v, x); v)
  Base.in(x, v::StdSetType) = set_in(v, x)
  Base.delete!(v::StdSetType, x) = (set_delete!(v, x); v)
end

for StdMultisetType in (StdMultiset, StdUnorderedMultiset)
  Base.size(v::StdMultisetType) = (Int(cppsize(v)),)
  Base.length(v::StdMultisetType) = Int(cppsize(v))
  Base.isempty(v::StdMultisetType) = multiset_isempty(v)
  Base.empty!(v::StdMultisetType) = (multiset_empty!(v); v)
  Base.push!(v::StdMultisetType, x) = (multiset_insert!(v, x); v)
  Base.in(x, v::StdMultisetType) = multiset_in(v, x)
  Base.delete!(v::StdMultisetType, x) = (multiset_delete!(v, x); v)
  Base.count(x, v::StdMultisetType) = multiset_count(v, x)
end

function Base.fill!(v::T, x) where T <: Union{StdVector, StdValArray, StdDeque}
  StdFill(v, x)
  return v
end

end
