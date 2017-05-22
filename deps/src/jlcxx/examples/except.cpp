#include <iostream>
#include <stdexcept>
#include <julia.h>

#ifdef _WIN32
  #define jlcxx_EXCEPT_EXPORT __declspec(dllexport)
#else
  #define jlcxx_EXCEPT_EXPORT
#endif

extern "C" jlcxx_EXCEPT_EXPORT int internalthrow(int i);

int internalthrow(int i)
{
  try
  {
    if (i > 0)
    {
      throw std::runtime_error("positive number not allowed");
    }
    return -i;
  }
  catch (const std::runtime_error& e)
  {
    jl_error(e.what());
    return 0;
  }
}
