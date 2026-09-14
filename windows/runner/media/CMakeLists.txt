cmake_minimum_required(VERSION 3.14)
project(media_session LANGUAGES CXX)

# Deliberately NOT apply_standard_settings().
#
# That function sets `_HAS_EXCEPTIONS=0` and `/W4 /WX`. C++/WinRT throws
# `winrt::hresult_error`, and its projection headers do not survive either
# setting — so this translation unit gets its own, and the boundary in
# media_session.h is kept free of standard-library types so the two exception
# regimes never share an object across a call.
add_library(media_session STATIC "media_session.cpp")

target_compile_features(media_session PUBLIC cxx_std_17)
target_compile_options(media_session PRIVATE /EHsc /W4)
target_compile_definitions(media_session PRIVATE "NOMINMAX")
target_compile_definitions(media_session PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")

# The C++/WinRT projection and the Windows Runtime import library. Both ship
# with the Windows SDK, so there is nothing to fetch and no include directory
# to add — vcvars puts the SDK's cppwinrt headers on INCLUDE already.
target_link_libraries(media_session PRIVATE "windowsapp.lib")

target_include_directories(media_session
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
