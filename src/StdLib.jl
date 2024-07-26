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

include("StdLib/StdDeque.jl")
include("StdLib/StdForwardList.jl")
include("StdLib/StdList.jl")
include("StdLib/StdMultisetTypes.jl")
include("StdLib/StdPriorityQueue.jl")
include("StdLib/StdQueue.jl")
include("StdLib/StdSetTypes.jl")
include("StdLib/StdStack.jl")
include("StdLib/StdString.jl")
include("StdLib/StdValArray.jl")
include("StdLib/StdVector.jl")


function Base.fill!(v::T, x) where {T<:Union{StdList,StdForwardList}}
  StdFill(v, x)
  return v
end

end
