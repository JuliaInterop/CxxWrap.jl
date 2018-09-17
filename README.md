# CxxWrap

[![Build Status](https://travis-ci.org/JuliaInterop/CxxWrap.jl.svg?branch=master)](https://travis-ci.org/JuliaInterop/CxxWrap.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/emjnb5afswn0lq6x?svg=true)](https://ci.appveyor.com/project/barche/cxxwrap-jl)
[![CxxWrap](http://pkg.julialang.org/badges/CxxWrap_0.4.svg)](http://pkg.julialang.org/?pkg=CxxWrap)
[![CxxWrap](http://pkg.julialang.org/badges/CxxWrap_0.5.svg)](http://pkg.julialang.org/?pkg=CxxWrap)

This package aims to provide a Boost.Python-like wrapping for C++ types and functions to Julia. The idea is to write the code for the Julia wrapper in C++, and then use a one-liner on the Julia side to make the wrapped C++ library available there.

The mechanism behind this package is that functions and types are registered in C++ code that is compiled into a dynamic library. This dynamic library is then loaded into Julia, where the Julia part of this package uses the data provided through a C interface to generate functions accessible from Julia. The functions are passed to Julia either as raw function pointers (for regular C++ functions that  don't need argument or return type conversion) or std::functions (for lambda expressions and automatic conversion of arguments and return types). The Julia side of this package wraps all this into Julia methods automatically.

## What's the difference with Cxx.jl?
With [Cxx.jl](https://github.com/Keno/Cxx.jl/) it is possible to directly access C++ using the `@cxx` macro from Julia. So when facing the task of wrapping a C++ library in a Julia package, authors now have two options:
* Use Cxx.jl to write the wrapper package in Julia code (much like one uses `ccall` for wrapping a C library)
* Use CxxWrap to write the wrapper completely in C++ (and one line of Julia code to load the .so)

Boost.Python also uses the latter (C++-only) approach, so translating existing Python bindings based on Boost.Python may be easier using CxxWrap.

## Features
* Support for C++ functions, member functions and lambdas
* Classes with single inheritance, using abstract base classes on the Julia side
* Trivial C++ classes can be converted to a Julia isbits immutable
* Template classes map to parametric types, for the instantiations listed in the wrapper
* Automatic wrapping of default and copy constructor (mapped to deepcopy) if defined on the wrapped C++ class
* Facilitate calling Julia functions from C++

## Installation
Just like any registered package, in pkg mode (`]` at the REPL)
```julia
add CxxWrap
```

This will also install the [JlCxx](https://github.com/JuliaInterop/libcxxwrap-julia) library (in `deps/usr` relative to the package dir), which is the C++ component of this package. If you want to use existing binaries for this library, set the environment variable `JLCXX_DIR` to the prefix where libcxxwrap-julia is installed and then add the package or run `Pkg.build("CxxWrap")`.

## Boost Python Hello World example
Let's try to reproduce the example from the [Boost.Python tutorial](http://www.boost.org/doc/libs/1_59_0/libs/python/doc/tutorial/doc/html/index.html). Suppose we want to expose the following C++ function to Julia in a module called `CppHello`:
```c++
std::string greet()
{
   return "hello, world";
}
```
Using the C++ side of `CxxWrap`, this can be exposed as follows:
```c++
#include "jlcxx/jlcxx.hpp"

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
  mod.method("greet", &greet);
}
```

Once this code is compiled into a shared library (say `libhello.so`) it can be used in Julia as follows:

```julia
# Load the module and generate the functions
module CppHello
  using CxxWrap
  @wrapmodule(joinpath("path/to/built/lib","libhello"))

  function __init__()
    @initcxx
  end
end

# Call greet and show the result
@show CppHello.greet()
```
The code for this example can be found in [`hello.cpp`] in the [examples](https://github.com/JuliaInterop/libcxxwrap-julia/tree/master/examples) directory of the libcxx-julia project and [`test/hello.jl`](test/hello.jl).
Note that the `__init__` function is necessary to support precompilation, which is on by default in Julia 1.0.

## Hello World example on Windows
On Windows, it is not necessary to create the Visual Studio project by hand: CMake creates a .sln file in the deps/build directory of the package, and that can be opened using Visual Studio to edit the source files and so on. The drawback is that this file gets overwritten if you add a new C++ source file for example.

If creating the Visual Studio project by hand is preferred, however, the following are the steps (assume Julia has been installed to C:\JuliaPro).

* In Visual Studio 2015, New Project, Installed | Templates | Other Languages | Visual C++ | Win32 | Win32 Project. Type in the name "CppHello" and choose Location of the project.
* In the Win32 Application Wizard, click Next, then select Application Type as DLL; in Additional options uncheck Security Development Lifecycle (SDL) checks. Then click Finish.
* Choose the active configuration as Release; choose x86 or x64 to match the CPU and the Julia version installed.
* Right click on the project name in the Solution Explorer, and choose Properties. Make the following changes (modify directory names as needed to match the actual Julia installation path):
  * C/C++ | General | Additional Include Directories: insert "C:\JuliaPro\Julia-0.5.1\include\julia;C:\JuliaPro\pkgs-0.5.1.1\v0.5\CxxWrap\deps\usr\include;"
  * C/C++ | Preprocessor | Preprocessor Definitions: insert "JULIA_ENABLE_THREADING;" before "%(PreprocessorDefinitions)"
  * Linker | Input | Additional Dependencies: insert "C:\JuliaPro\pkgs-0.5.1.1\v0.5\CxxWrap\deps\usr\lib\jlcxx.lib;C:\JuliaPro\Julia-0.5.1\lib\libjulia.dll.a;" before "%(AdditionalIncludeDirectories)"
* Click OK to exit the CppHello Property Pages.
* In Solution Explorer, under Source Files, double click "CppHello.cpp" to open it. Append the following code at the end and save:
```c++
#include "jlcxx/jlcxx.hpp"

std::string greet()
{
  return "hello, world";
}

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
  mod.method("greet", &greet);
}
```
* Build the CppHello project.
* Locate the resulted CppHello.dll file under the Release folder. For a 64-bit build, the path is the project folder\x64\Release\CppHello.dll.

## Module entry point

Above, we defined the module entry point as a function `JLCXX_MODULE define_julia_module(jlcxx::Module& mod)`. In the general case, there may be multiple modules defined in a single library, and each should have its own entry
point, called within the appropriate module:

```c++
JLCXX_MODULE define_module_a(jlcxx::Module& mod)
{
  // add stuff for A
}

JLCXX_MODULE define_module_b(jlcxx::Module& mod)
{
  // add stuff for B
}
```

In Julia, the name of the entry point must now be specified explicitly:
```julia
module A
  using CxxWrap
  @wrapmodule("mylib.so",:define_module_a)
end

module B
  using CxxWrap
  @wrapmodule("mylib.so",:define_module_b)
end
```

## More extensive example and function call performance
A more extensive example, including wrapping a C++11 lambda and conversion for arrays can be found in [`deps/src/jlcxx/examples/functions.cpp`](deps/src/jlcxx/examples/functions.cpp) and [`test/functions.jl`](test/functions.jl). This test also includes some performance measurements, showing that the function call overhead is the same as using ccall on a C function if the C++ function is a regular function and does not require argument conversion. When `std::function` is used (e.g. for C++ lambdas) extra overhead appears, as expected.

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

Wrapped in the an entry point function as before and defining a module `CppTypes`, the code for exposing the type and some methods to Julia is:
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

The manually added constructor using the `constructor` function also creates a finalizer. This can be disabled by adding the argument `false`:

```c++
types.add_type<World>("World")
  .constructor<const std::string&>(false);
```

The `add_type` function actually builds 3 Julia types related to World. The first is an abstract type:

```julia
abstract type World end
```

The second is an immutable type (the "reference type") with the following structure:

```julia
struct WorldRef <: World
  cpp_object::Ptr{Cvoid}
end
```

It is an immutable type to be able to refer to C++ values without needing to allocate. This also means there are no finalizers for this kind of type, which is why there is also an equivalent mutable type that is returned by constructors and has a finalize attached that calls `delete` in C++:

```julia
mutable struct WorldAllocated <: World
  cpp_object::Ptr{Cvoid}
end
```

This means that the variable `w` in the above example is of concrete type `WorldAllocated` and letting it go out of scope may trigger the finalizer and delete the object. When calling a C++ constructor, it is the responsibility of the caller to manage the lifetime of the resulting variable.

The above types are used in method generation as follows, considering for example the greet method taking a `World` argument:

```julia
greet(w::World) = ccall($fpointer, Any, (Ptr{Cvoid}, WorldRef), $thunk, cconvert(WorldRef, w))
```

Here, the `cconvert` from `WorldAllocated` to `WorldRef` is defined automatically when creating the type.

**Warning:** The ordering of the C++ code matters: types used as function arguments or return types must be added before they are used in a function.

The full code for this example and more info on immutables and bits types can be found in [`deps/src/jlcxx/examples/types.cpp`](deps/src/jlcxx/examples/types.cpp) and [`test/types.jl`](test/types.jl).

### Checking for null

Values returned from C++ can be checked for being null using the `isnull` function.

## Inheritance
To encapsulate inheritance, types must first inherit from each other in C++, so a `static_cast` to the base type can work:

```c++
struct A
{
  virtual std::string message() const = 0;
  std::string data = "mydata";
};

struct B : A
{
  virtual std::string message() const
  {
    return "B";
  }
};
```

When adding the type, add the supertype as a second argument:
```c++
types.add_type<A>("A").method("message", &A::message);
types.add_type<B>("B", jlcxx::julia_type<A>());
```

The supertype is of type `jl_datatype_t*` and using the template variant of `jlcxx::julia_type` looks up the corresponding type here. There is also a variant taking a string for the type name and an optional Julia module name as second argument, which is useful for inheriting from a type defined in Julia, e.g:

```c++
mod.add_type<Teuchos::ParameterList>("ParameterList", jlcxx::julia_type("AbstractDict", "Base"))
```

The value returned by `add_type` also had a `dt()` method, useful in the case of template types:

```c++
auto multi_vector_base = mod.add_type<Parametric<TypeVar<1>>>("MultiVectorBase");
auto vector_base = mod.add_type<Parametric<TypeVar<1>>>("VectorBase", multi_vector_base.dt());
```

Since the concrete arguments given to `ccall` are the reference types, we need a way to convert `BRef` into `ARef`. To allow CxxWrap to figure out the correct static_cast to use, the hierarchy must be defined at compile time as follows:

```c++
namespace jlcxx
{
  template<> struct SuperType<B> { typedef A type; };
}
```

See the test at [`deps/src/jlcxx/examples/inheritance.cpp`](deps/src/jlcxx/examples/inheritance.cpp) and [`test/inheritance.jl`](test/inheritance.jl).

## Enum types

Enum types are converted to strongly-typed bits types on the Julia side. Consider the C++ enum:

```c++
enum CppEnum
{
  EnumValA,
  EnumValB
};
```

This is registered as follows:

```c++
namespace jlcxx
{
  template<> struct IsBits<CppEnum> : std::true_type {};
}

JLCXX_MODULE define_types_module(jlcxx::Module& types)
{
  types.add_bits<CppEnum>("CppEnum");
  types.set_const("EnumValA", EnumValA);
  types.set_const("EnumValB", EnumValB);
}
```

The enum constants will be available on the Julia side as `CppTypes.EnumValA` and `CppTypes.EnumValB`, both of type `CppTypes.CppEnum`. Wrapped C++ functions taking a `CppEnum` will only accept a value of type `CppTypes.CppEnum` in Julia.

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

There is also an `apply_combination` method to make applying all combinations of parameters shorter to write.

Full example and test including non-type parameters at: [`deps/src/jlcxx/examples/parametric.cpp`](deps/src/jlcxx/examples/parametric.cpp) and [`test/parametric.jl`](test/parametric.jl).

## Constructors and destructors
The default constructor and any manually added constructor using the `constructor` function will automatically create a Julia object that has a finalizer attached that calls delete to free the memory. To write a C++ function that returns a new object that can be garbage-collected in Julia, use the `jlcxx::create` function:
```c++
jlcxx::create<Class>(constructor_arg1, ...);
```
This will return the new C++ object wrapped in a `jl_value_t*` that has a finalizer.

## Call operator overload
Since Julia supports overloading the function call operator `()`, this can be used to wrap `operator()` by just omitting the method name:

```c++
struct CallOperator
{
  int operator()() const
  {
    return 43;
  }
};

// ...

types.add_type<CallOperator>("CallOperator").method(&CallOperator::operator());
```

Use in Julia:

```julia
call_op = CallOperator()
@test call_op() == 43
```

The C++ function does not even have to be `operator()`, but of course it is most logical use case.

## Automatic argument conversion
By default, overloaded signatures for wrapper methods are generated, so a method taking a `double` in C++ can be called with e.g. an `Int` in Julia. Wrapping a function like this:

```c++
mod.method("half_lambda", [](const double a) {return a*0.5;});
```

then yields the methods:

```julia
half_lambda(arg1::Int64)
half_lambda(arg1::Float64)
```

In some cases (e.g. when a template parameter depends on the number type) this is not desired, so the behavior can be disabled on a per-argument basis using the `StrictlyTypedNumber` type. Wrapping a function like this:

```c++
mod.method("strict_half", [](const jlcxx::StrictlyTypedNumber<double> a) {return a.value*0.5;});
```

will *only* yield the Julia method:

```julia
strict_half(arg1::Float64)
```

Note that in C++ the number value is accessed using the `value` member of `StrictlyTypedNumber`.

### Customization
The automatic overloading can be customized. For example, to allow passing an `Int64` where a `UInt64` is normally expected, the following method can be added:

```julia
CxxWrap.argument_overloads(t::Type{UInt64}) = [Int64]
```

## Smart pointers
Currently, `std::shared_ptr`, `std::unique_ptr` and `std::weak_ptr` are supported transparently. Returning one of these pointer types will return an object inheriting from `SmartPointer{T}`:

```c++
types.method("shared_world_factory", []()
{
  return std::shared_ptr<World>(new World("shared factory hello"));
});
```
The shared pointer can then be used in a function taking an object of type `World` like this (the module is named `CppTypes` here):

```julia
swf = CppTypes.shared_world_factory()
CppTypes.greet(swf)
```

Explicit dereferencing is also supported, using the `[]` operator:

```julia
CppTypes.greet(swf[])
```

### Adding a custom smart pointer
Suppose we have a "smart" pointer type defined as follows:
```c++
template<typename T>
struct MySmartPointer
{
  MySmartPointer(T* ptr) : m_ptr(ptr)
  {
  }

  MySmartPointer(std::shared_ptr<T> ptr) : m_ptr(ptr.get())
  {
  }

  T& operator*() const
  {
    return *m_ptr;
  }

  T* m_ptr;
};
```

Specializing in the `jlcxx` namespace:

```c++
namespace jlcxx
{
  template<typename T> struct IsSmartPointerType<cpp_types::MySmartPointer<T>> : std::true_type { };
  template<typename T> struct ConstructorPointerType<cpp_types::MySmartPointer<T>> { typedef std::shared_ptr<T> type; };
}
```

Here, the first line marks our type as a smart pointer, enabling automatic conversion from the pointer to its referenced type and adding the dereferencing pointer. If the type uses inheritance and the hierarchy is defined using `SuperType`, automatic conversion to the pointer or reference of the base type is also supported. The second line indicates that our smart pointer can be constructed from a `std::shared_ptr`, also adding auto-conversion for that case. This is useful for a relation as in `std::weak_ptr` and `std::shared_ptr`, for example.

## Exceptions
When directly adding a regular free C++ function as a method, it will be called directly using ccall and any exception will abort the Julia program. To avoid this, you can force wrapping it in an `std::functor` to intercept the exception automatically by setting the `force_convert` argument to `method` to true:
```c++
mod.method("test_exception", test_exception, true);
```
Member functions and lambdas are automatically wrapped in an `std::functor` and so any exceptions thrown there are always intercepted and converted to a Julia exception.

## Tuples

C++11 tuples can be converted to Julia tuples by including the `containers/tuple.hpp` header:
```c++
#include "jlcxx/jlcxx.hpp"
#include "jlcxx/tuple.hpp"

JLCXX_MODULE define_types_module(jlcxx::Module& containers)
{
  containers.method("test_tuple", []() { return std::make_tuple(1, 2., 3.f); });
}
```

Use in Julia:

```julia
using CxxWrap
using Base.Test

module Containers
  @wrapmodule(libcontainers)
  export test_tuple
end
using Containers

@test test_tuple() == (1,2.0,3.0f0)
```
## Working with arrays
### Reference native Julia arrays
The `ArrayRef` type is provided to work conveniently with array data from Julia. Defining a function like this in C++:
```c++
void test_array_set(jlcxx::ArrayRef<double> a, const int64_t i, const double v)
{
  a[i] = v;
}
```
This can be called from Julia as:
```julia
ta = [1.,2.]
test_array_set(ta, 0, 3.)
```
The `ArrayRef` type provides basic functionality:
* iterators
* `size`
* `[]` read-write accessor
* `push_back` for appending elements

### Const arrays
Sometimes, a function returns a const pointer that is an array, either of fixed size or with a size that can be determined from elsewhere in the API. Example:
```c++
const double* const_vector()
{
  static double d[] = {1., 2., 3};
  return d;
}
```

In this simple case, the most logical way to translate this would be as a tuple:
```c++
mymodule.method("const_ptr_arg", []() { return std::make_tuple(const_vector().ptr[0], const_vector().ptr[1], const_vector().ptr[2]); });
```

In the case of a larger blob of heap-allocated data it makes more sense to convert this to a `ConstArray`, which implements the read-only part of the Julia array interface, so it exposes the data safely to Julia in a way that can be used natively:
```c++
mymodule.method("const_vector", []() { return jlcxx::make_const_array(const_vector(), 3); });
```

For multi-dimensional arrays, the `make_const_array` function takes multiple sizes, e.g.:

```c++
const double* const_matrix()
{
  static double d[2][3] = {{1., 2., 3}, {4., 5., 6.}};
  return &d[0][0];
}

// ...module definition skipped...

mymodule.method("const_matrix", []() { return jlcxx::make_const_array(const_matrix(), 3, 2); });
```

Note that because of the column-major convention in Julia, the sizes are in reversed order from C++, so the Julia code:
```julia
display(const_matrix())
```

shows:

```
3x2 ConstArray{Float64,2}:
 1.0  4.0
 2.0  5.0
 3.0  6.0
```

### Mutable arrays

Replacing `make_const_array` in the examples above by `make_julia_array` creates a mutable, regular Julia array with memory owned by Julia.


## Calling Julia functions from C++
### Direct call to Julia
Directly calling Julia functions uses `jl_call` from `julia.h` but with a more convenient syntax and automatic argument conversion and boxing. Use a `JuliaFunction` to get a functor that can be invoked directly. Example for calling the `max` function from `Base`:

```c++
mymodule.method("julia_max", [](double a, double b)
{
  jlcxx::JuliaFunction max("max");
  return max(a, b);
});
```

Internally, the arguments and return value are boxed, making this method convenient but slower than calling a regular C function.

### Safe `cfunction`
The function `CxxWrap.safe_cfunction` provides a wrapper around `Base.cfunction` that checks the type of the function pointer. Example C++ function:
```c++
mymodule.method("call_safe_function", [](double(*f)(double,double))
{
  if(f(1.,2.) != 3.)
  {
    throw std::runtime_error("Incorrect callback result, expected 3");
  }
});
```
Use from Julia:
```julia
testf(x,y) = x+y
c_func = safe_cfunction(testf, Float64, (Float64,Float64))
MyModule.call_safe_function(c_func)
```

Using types different from the expected function pointer call will result in an error. This check incurs a runtime overhead, so the idea here is that the function is converted only once and then applied many times on the C++ side.

If the result of `safe_cfunction` needs to be stored before the calling signature is known, direct conversion of the created structure (type `SafeCFunction`) is also possible. It can then be converted later using `jlcxx::make_function_pointer`:
```c++
mymodule.method("call_safe_function", [](jlcxx::SafeCFunction f_data)
{
  auto f = jlcxx::make_function_pointer<double(double,double)>(f_data);
  if(f(1.,2.) != 3.)
  {
    throw std::runtime_error("Incorrect callback result, expected 3");
  }
});
```

This method of calling a Julia function is less convenient, but the call overhead should be no larger than calling a regular C function through its pointer.

## Adding Julia code to the module
Sometimes, you may want to write additional Julia code in the module that is built from C++. To do this, call the `wrapmodule` method inside an appropriately named Julia module:
```julia
module ExtendedTypes

using CxxWrap
@wrapmodule("libextended")
export ExtendedWorld, greet

end
```
Here, `ExtendedTypes` is a name that matches the module name passed to `create_module` on the C++ side. The `@wrapmodule` call works as before, but now the functions and types are defined in the existing `ExtendedTypes` module, and additional Julia code such as exports and macros can be defined.

It is also possible to replace the `@wrapmodule` call with a call to `@readmodule` and then separately call `@wraptypes` and `@wrapfunctions`. This allows using the types before the functions get called, which is useful for overloading the `argument_overloads` with types defined on the C++ side.

## Linking with the C++ library
The library (in [`deps/src/jlcxx`](deps/src/jlcxx)) is built using CMake, so it can be found from another CMake project using the following line in a `CMakeLists.txt`:

```cmake
find_package(CxxWrap)
```
The CMake variable `CxxWrap_DIR` should be set to the directory containing the `CxxWrapConfig.cmake`, typically `~/.julia/<Julia version>/CxxWrap/deps/usr/lib/cmake`. One can then link using:
```cmake
target_link_libraries(your_own_lib CxxWrap::jlcxx)
```

A complete `CMakeLists.txt` is at [`deps/src/examples/CMakeLists.txt`](deps/src/examples/CMakeLists.txt).

## Breaking changes for 0.7

* `JULIA_CPP_MODULE_BEGIN` and `JULIA_CPP_MODULE_END` no longer exists, define a function with return type `JLCXX_MODULE` in the global namespace instead. By default, the Julia side expects this function to be named `define_julia_module`, but another name can be chosen and passed as a second argument to `@wrapmodule`.

* `wrap_modules` is removed, replace `wrap_modules(lib_file_path)` with
  ```julia
  module Foo
    using CxxWrap
    @wrapmodule(lib_file_path)
  end
  ```

* `export_symbols` is removed, since all C++ modules are now wrapped in a corresponding module declared on the Julia side, so the regular Julia export
statement can be used.

* `safe_cfunction` is now a macro, just like cfunction became a macro in Julia

* Precompilation: add this function after the `@wrapmodule` macro:
  ```julia
  function __init__()
    @initcxx
  end
  ```
  