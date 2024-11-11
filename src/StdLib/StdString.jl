using .StdLib: CppBasicString, StdString, StdWString

Base.ncodeunits(s::CppBasicString)::Int = cppsize(s)
Base.codeunit(s::StdString) = UInt8
Base.codeunit(s::StdWString) = Cwchar_t == Int32 ? UInt32 : UInt16
Base.codeunit(s::CppBasicString, i::Integer) = reinterpret(codeunit(s), cxxgetindex(s, i))
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


@cxxdereference Base.String(s::StdString) = unsafe_string(reinterpret(Ptr{Cchar}, c_str(s).cpp_object), cppsize(s))
@cxxdereference function Base.String(s::StdWString)
    chars = unsafe_wrap(Vector{Cwchar_t}, reinterpret(Ptr{Cwchar_t}, c_str(s).cpp_object), (cppsize(s),))
    return transcode(String, chars)
end
Base.show(io::IO, s::CppBasicString) = show(io, String(s))
Base.cmp(a::CppBasicString, b::String) = cmp(String(a), b)
Base.cmp(a::String, b::CppBasicString) = cmp(a, String(b))

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
StdString(::Union{Cstring,Base.CodeUnits,Vector{UInt8},Ref{Int8},Array{Int8}})

StdString(x::Cstring) = StdString(convert(Ptr{Cchar}, x))
StdString(x::Base.CodeUnits) = StdString(collect(reinterpret(Cchar,x)))
@static if Cchar != UInt8
    StdString(x::Vector{UInt8}) = StdString(collect(reinterpret(Cchar, x)))
end

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
