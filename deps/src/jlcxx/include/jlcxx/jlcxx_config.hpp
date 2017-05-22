#ifndef JLCXX_EXPORT_HPP
#define JLCXX_EXPORT_HPP

#ifdef _WIN32
  #ifdef JLCXX_EXPORTS
      #define JLCXX_API __declspec(dllexport)
  #else
      #define JLCXX_API __declspec(dllimport)
  #endif
#else
   #define JLCXX_API
#endif

#define JLCXX_VERSION_MAJOR 0
#define JLCXX_VERSION_MINOR 1
#define JLCXX_VERSION_PATCH 1

#endif
