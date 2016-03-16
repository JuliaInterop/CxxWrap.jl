# CppWrapper

This package aims to provide a Boost.Python-like wrapping for C++ types and functions to Julia. The idea is to write the code for the Julia wrapper in C++, and then use a one-liner on the Julia side to make the wrapped C++ library available there.

The mechanism behind this package is that functions and types are registered in C++ code that is compiled into a dynamic library. This dynamic library is then loaded into Julia, where the Julia part of this package uses the data provided through a C interface to generate functions accessible from Julia. The functions are passed to Julia either as raw function pointers (for regular C++ functions that  don't need argument or return type conversion) or std::functions (for lambda expressions and automatic conversion of arguments and return types). The Julia side of this package wraps all this into Julia methods automatically.

## What's the difference with Cxx.jl?
With Cxx.jl it is possible to directly access C++ using the `@cxx` macro from Julia. So when facing the task of wrapping a C++ library in a Julia package, authors now have 2 options:
* Use Cxx.jl to write the wrapper package in Julia code (much like one uses `ccall` for wrapping a C library)
* Use CppWrapper to write the wrapper completely in C++ (and one line of Julia code to load the .so)

Boost.Python also uses the latter (C++-only) approach, so translating existing Python bindings based on Boost.Python may be easier using CppWrapper.

## Features
* Support for C++ functions, member functions and lambdas
* Classes with single inheritance, using abstract base classes on the Julia side
* Standard-layout C++ classes can be converted to a Julia isbits immutable
* Standard-layout C++ classes can be converted to an opaque Julia bits type
* Template classes map to parametric types, for the instantiations listed in the wrapper
* Automatic wrapping of default and copy constructor (mapped to deepcopy) if defined on the wrapped C++ class

## Installation
Just like any unregistered package:
```julia
Pkg.clone("https://github.com/barche/CppWrapper.git")
Pkg.build("CppWrapper")
```

## Boost Python Hello World example
Let's try to reproduce the example from the [Boost.Python tutorial](http://www.boost.org/doc/libs/1_59_0/libs/python/doc/tutorial/doc/html/index.html). Suppose we want to expose the following C++ function to Julia in a module called `CppHello`:
```c++
std::string greet()
{
   return "hello, world";
}
```
Using the C++ side of `CppWrapper`, this can be exposed as follows:
```c++
#include <cpp_wrapper.hpp>

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& hello = registry.create_module("CppHello");
  hello.method("greet", &greet);
JULIA_CPP_MODULE_END
```

Once this code is compiled into a shared library (say `libhello.so`) it can be used in Julia as follows:

```julia
using CppWrapper

# Load the module and generate the functions
wrap_modules(joinpath("path/to/built/lib","libhello"))
# Call greet and show the result
@show CppHello.greet()
```
The code for this example can be found in [`deps/src/examples/hello.cpp`](deps/src/examples/hello.cpp) and [`test/hello.jl`](test/hello.jl).

### Exporting symbols
Julia symbols can be exported from the module using the `export_symbols` function on the C++ side. It takes any number of symbols as string. To export `greet` from the `CppHello` module:
```c++
hello.export_symbols("greet");
```

## More extensive example and function call performance
A more extensive example, including wrapping a C++11 lambda and conversion for arrays can be found in [`deps/src/examples/functions.cpp`](deps/src/examples/functions.cpp) and [`test/functions.jl`](test/functions.jl). This test also includes some performance measurements, showing that the function call overhead is the same as using ccall on a C function if the C++ function is a regular function and does not require argument conversion. When `std::function` is used (e.g. for C++ lambdas) extra overhead appears, as expected.

## Exposing classes
Consider the following C++ class to be wrapped:
```c++
struct World
{
  World(const std::string& message = "default hello") : msg(message){}
  void set(const std::string& msg) { this->msg = msg; }
  std::string greet() { return msg; }
  std::string msg;
  ~World() { std::cout << "Destroying World with message " << msg << std::endl; }
};
```

Wrapped in the `JULIA_CPP_MODULE_BEGIN/END` block as before and defining a module `CppTypes`, the code for exposing the type and some methods to Julia is:
```c++
types.add_type<World>("World")
  .constructor<const std::string&>()
  .method("set", &World::set)
  .method("greet", &World::greet);
```
Here, the first line just adds the type. The second line adds the non-default constructor taking a string. Finally, the two `method` calls add member functions, using a pointer-to-member. The member functions become free functions in Julia, taking their object as the first argument. This can now be used in Julia as
```julia
w = CppTypes.World()
@test CppTypes.greet(w) == "default hello"
CppTypes.set(w, "hello")
@test CppTypes.greet(w) == "hello"
```
The full code for this example and more info on immutables and bits types can be found in [`deps/src/examples/types.cpp`](deps/src/examples/types.cpp) and [`test/types.jl`](test/types.jl).

## Inheritance
See the test at [`deps/src/examples/inheritance.cpp`](deps/src/examples/inheritance.cpp) and [`test/inheritance.jl`](test/inheritance.jl).

## Template (parametric) types
The natural Julia equivalent of a C++ template class is the parametric type. The mapping is complicated by the fact that all possible parameter values must be compiled in advance, requiring a deviation from the syntax for adding a regular class. Consider the following template class:
```c++
template<typename A, typename B>
struct TemplateType
{
  typedef typename A::val_type first_val_type;
  typedef typename B::val_type second_val_type;

  first_val_type get_first()
  {
    return A::value();
  }

  second_val_type get_second()
  {
    return B::value();
  }
};
```
The code for wrapping this is:
```c++
types.add_type<Parametric<TypeVar<1>, TypeVar<2>>>("TemplateType")
  .apply<TemplateType<P1,P2>, TemplateType<P2,P1>>([](auto wrapped)
{
  typedef typename decltype(wrapped)::type WrappedT;
  wrapped.method("get_first", &WrappedT::get_first);
  wrapped.method("get_second", &WrappedT::get_second);
});
```
The first line adds the parametric type, using the generic placeholder `Parametric` and a `TypeVar` for each parameter. On the second line, the possible instantiations are created by calling `apply` on the result of `add_type`. Here, we allow for `TemplateType<P1,P2>` and `TemplateType<P2,P1>` to exist, where `P1` and `P2` are C++ classes that also must be wrapped and that fulfill the requirements for being a parameter to `TemplateType`. The argument to `apply` is a functor (generic C++14 lambda here) that takes the wrapped instantiated type (called `wrapped` here) as argument. This object can then be used as before to define methods. In the case of a generic lambda, the actual type being wrapped can be obtained using `decltype` as shown on the 4th line.

Use on the Julia side:
```julia
import ParametricTypes.TemplateType, ParametricTypes.P1, ParametricTypes.P2

p1 = TemplateType{P1, P2}()
p2 = TemplateType{P2, P1}()

@test ParametricTypes.get_first(p1) == 1
@test ParametricTypes.get_second(p2) == 1
```

Full example and test including non-type parameters at: [`deps/src/examples/parametric.cpp`](deps/src/examples/parametric.cpp) and [`test/parametric.jl`](test/parametric.jl).


## Linking with the C++ library
The library (in [`deps/src/cpp_wrapper`](deps/src/cpp_wrapper)) is built using CMake, so it can be found from another CMake project using the following line in a `CMakeLists.txt`:

```cmake
find_package(CppWrapper)
```
The CMake variable `CppWrapper_DIR` should be set to the directory containing the `CppWrapperConfig.cmake`, typically `~/.julia/<Julia version>/CppWrapper/deps/usr/lib/cmake`. One can then link using:
```cmake
target_link_libraries(your_own_lib CppWrapper::cpp_wrapper)
```

A complete `CMakeLists.txt` is at [`deps/src/examples/CMakeLists.txt`](deps/src/examples/CMakeLists.txt).
