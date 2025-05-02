include(joinpath(@__DIR__, "testcommon.jl"))

GC.enable(true)

# Wrap the functions defined in C++
module CppInheritance

using CxxWrap
@wrapmodule(CxxWrap.CxxWrapCore.libinheritance, :define_types_module)

function __init__()
  @initcxx
end

export A, B, C, D, message, create_abstract, shared_ptr_message, shared_b, shared_c, shared_d, weak_ptr_message_a, weak_ptr_message_b, dynamic_message_c, take_ref

end

module VirtualSolver
  using CxxWrap
  @wrapmodule(CxxWrap.CxxWrapCore.libinheritance, :define_vsolver_module)
  
  function __init__()
    @initcxx
  end
end

using .CppInheritance

# Normal Julia callback
function double(x::Float64)
  return 2x
end

# callback as a C function
c_double = @safe_cfunction(double, Float64, (Float64,))

# Base class for extended classes in Julia
abstract type AbstractJuliaExtended <: CppInheritance.VirtualCpp end
# Every C++ function called on the Julia extended classes needs this kind of specialization
CppInheritance.virtualfunc(x::AbstractJuliaExtended) = CppInheritance.virtualfunc(x.referred_object)

# Example of an extension implemented in Julia
struct JuliaExtended <: AbstractJuliaExtended
  function JuliaExtended(len, value)
    ref_obj = CppInheritance.VirtualCfunctionExtended(len,value)

    # Get a reference in case the value changes
    firstval_ref = CxxWrap.StdLib.cxxgetindex(CppInheritance.getData(ref_obj), 1)

    function cb(x::Float64)
      return 2x + firstval_ref[]
    end
    c_cb = @safe_cfunction($cb, Float64, (Float64,))

    CppInheritance.set_callback(ref_obj, c_cb)
    return new(ref_obj, c_cb)
  end
  referred_object::CppInheritance.VirtualCfunctionExtended
  callback::CxxWrap.SafeCFunction # Needed to avoid garbage collection of the function
end

@testset "$(basename(@__FILE__)[1:end-3])" begin

b = B()
c = C()
global d = D()

@test message(b) == "B"
@test message(c) == "C"
@test message(d) == "D"

@test take_ref(b) == "B"
@test take_ref(c) == "C"
@test take_ref(d) == "D"

# factory function returning an abstract type A
let abstract_b = create_abstract()
  @test message(abstract_b) == "B"
  abstract_b_ptr = CxxPtr(abstract_b)
  @test !isnull(convert(CxxPtr{B},abstract_b_ptr))
  @test message(convert(CxxPtr{B},abstract_b_ptr)) == "B"
  @test isnull(convert(CxxPtr{C},abstract_b_ptr))
  @test isnull(convert(CxxPtr{D},abstract_b_ptr))
  @test convert(CxxPtr{A},abstract_b_ptr) === abstract_b_ptr
end

@test dynamic_message_c(c) == "C"

# shared ptr variants
b_ptr = shared_b()
c_ptr = shared_c()
d_ptr = shared_d()

@test shared_ptr_message(b_ptr) == "B"
@test shared_ptr_message(c_ptr) == "C"
@test shared_ptr_message(d_ptr) == "D"

@test message(b_ptr[]) == "B"
@test message(c_ptr[]) == "C"
@test message(d_ptr[]) == "D"

@test weak_ptr_message_b(b_ptr) == "B"
@test weak_ptr_message_a(b_ptr) == "B"
@test weak_ptr_message_a(c_ptr) == "C"
@test weak_ptr_message_a(d_ptr) == "D"

a = VirtualSolver.E()
VirtualSolver.solve(a)

b = VirtualSolver.F(@safe_cfunction(x -> 2x, Float64, (Float64,)))
VirtualSolver.solve(b)

let virt_extended_julia = CppInheritance.VirtualCppJuliaExtended(100000,1.0)
  CppInheritance.set_callback(virt_extended_julia, double)
  @test CppInheritance.virtualfunc(virt_extended_julia) == 200000
  @time CppInheritance.virtualfunc(virt_extended_julia)
end

let virt_extended_julia = CppInheritance.VirtualCfunctionExtended(100000,2.0)
  CppInheritance.set_callback(virt_extended_julia, c_double)
  @test CppInheritance.virtualfunc(virt_extended_julia) == 400000
  @time CppInheritance.virtualfunc(virt_extended_julia)
end

let virt_extended_julia = JuliaExtended(100000, 4.0)
  @test CppInheritance.virtualfunc(virt_extended_julia) == 1200000
  GC.gc()
  @time CppInheritance.virtualfunc(virt_extended_julia)
end

end

