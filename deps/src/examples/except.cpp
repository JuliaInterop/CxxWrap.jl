#include <iostream>
#include <stdexcept>
#include <julia.h>

extern "C" __declspec(dllexport) int internalthrow(int i);

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
