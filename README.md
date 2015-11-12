# CppWrapper

This package aims to provide a Boost.Python-like wrapping for C++ types and functions to Julia. In its current state, it is mostly a proof-of-concept, working only for exposing functions. The main idea is that functions (and later types) are registered in C++ code that is compiled into a dynamic library. This dynamic library is then loaded into Julia, where the Julia part of this package uses the data provided through a C interface to generate functions accessible from Julia. The functions are passed to Julia either as raw function pointers (for regular C++ functions that  don't need argument or return type conversion) or std::functions (for lambda expressions and automatic conversion of arguments and return types). The Julia side of this package wraps all this into Julia methods automatically.

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
  hello.def("greet", &greet);
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

## More extensive example and performance
A more extensive example, including wrapping a C++11 lambda and conversion for arrays can be found in [`deps/src/examples/functions.cpp`](deps/src/examples/functions.cpp) and [`test/functions.jl`](test/functions.jl). This test also includes some performance measurements, showing that the function call overhead is the same as using ccall on a C function if the C++ function is a regular function and does not require argument conversion. When `std::function` is used (e.g. for C++ lambdas) extra overhead appears, as expected.

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
