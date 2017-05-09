#ifndef CXXWRAP_EXPORT_HPP
#define CXXWRAP_EXPORT_HPP

#ifdef _WIN32
  #ifdef CXXWRAP_EXPORTS
      #define CXXWRAP_API __declspec(dllexport)
  #else
      #define CXXWRAP_API __declspec(dllimport)
  #endif
#else
   #define CXXWRAP_API
#endif

#define CXXWRAP_VERSION_MAJOR 0
#define CXXWRAP_VERSION_MINOR 1
#define CXXWRAP_VERSION_PATCH 1

#endif
