# Hello world example, similar to the Boost.Python hello world

using CxxWrap
using Base.Test

# Wrap the functions defined in C++
wrap_modules(CxxWrap._l_inheritance)

using CppInheritance

b = B()
c = C()
d = D()

@test message(b) == "B"
@test message(c) == "C"
@test message(d) == "D"

# factory function returning an abstract type A
@test message(create_abstract()) == "B"

# shared ptr variants
b_ptr = shared_b()
c_ptr = shared_c()
d_ptr = shared_d()

@test shared_ptr_message(b_ptr) == "B"
@test shared_ptr_message(c_ptr) == "C"
@test shared_ptr_message(d_ptr) == "D"
