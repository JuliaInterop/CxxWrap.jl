include(joinpath(@__DIR__, "testcommon.jl"))

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

#@testset "$(basename(@__FILE__)[1:end-3])" begin

b = B()
c = C()
global d = D()

# @test message(b) == "B"
# @test message(c) == "C"
# @test message(d) == "D"

# @test take_ref(b) == "B"
# @test take_ref(c) == "C"
# @test take_ref(d) == "D"

# # factory function returning an abstract type A
# let abstract_b = create_abstract()
#   @test message(abstract_b) == "B"
#   abstract_b_ptr = CxxPtr(abstract_b)
#   @test !isnull(convert(CxxPtr{B},abstract_b_ptr))
#   @test message(convert(CxxPtr{B},abstract_b_ptr)) == "B"
#   @test isnull(convert(CxxPtr{C},abstract_b_ptr))
#   @test isnull(convert(CxxPtr{D},abstract_b_ptr))
#   @test convert(CxxPtr{A},abstract_b_ptr) === abstract_b_ptr
# end

# @test dynamic_message_c(c) == "C"

# # shared ptr variants
# b_ptr = shared_b()
# c_ptr = shared_c()
# d_ptr = shared_d()

# @test shared_ptr_message(b_ptr) == "B"
# @test shared_ptr_message(c_ptr) == "C"
# @test shared_ptr_message(d_ptr) == "D"

# @test message(b_ptr[]) == "B"
# @test message(c_ptr[]) == "C"
# @test message(d_ptr[]) == "D"

# @test weak_ptr_message_b(b_ptr) == "B"
# @test weak_ptr_message_a(b_ptr) == "B"
# @test weak_ptr_message_a(c_ptr) == "C"
# @test weak_ptr_message_a(d_ptr) == "D"

# a = VirtualSolver.E()
# VirtualSolver.solve(a)

# b = VirtualSolver.F(@safe_cfunction(x -> 2x, Float64, (Float64,)))
# VirtualSolver.solve(b)

# let static_base = CppInheritance.StaticBase(), static_derived = CppInheritance.StaticDerived()
#   to_base = convert(CppInheritance.StaticBase,static_derived)
#   @test static_derived.cpp_object == to_base.cpp_object
#   @test convert(CxxPtr{CppInheritance.StaticDerived}, CxxPtr(to_base))[] == static_derived
# end

# end