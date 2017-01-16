#!ctest -S
if(NOT CTEST_SOURCE_DIRECTORY)
   get_filename_component(CTEST_SOURCE_DIRECTORY "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
endif()
get_filename_component(PROJECT_DIRECTORY "${CTEST_SOURCE_DIRECTORY}" DIRECTORY)

macro(read_argument name)
   if(NOT ${name})
      if(DEFINED ENV{${name}})
         set(${name} "$ENV{${name}}")
      elseif(${ARGC} GREATER 1)
         set(${name} "${ARGV1}")
      endif()
   endif()
   #message(STATUS "argument ${name}: '${${name}}'")
endmacro()

# Dashboard Model
################################################################################
read_argument(dashboard_model "Experimental")
if(${dashboard_model} STREQUAL "Continuous")
   set(is_continuous TRUE)
elseif(${dashboard_model} STREQUAL "Experimental")
   set(is_experimental TRUE)
elseif(${dashboard_model} STREQUAL "Nightly")
   set(is_nightly TRUE)
else()
   message(FATAL_ERROR "Unknown dashboard_model '${dashboard_model}'. Please use one of Experimental, Continuous, Nightly.")
endif()

# Set build variables from environment variables
################################################################################
read_argument(target_architecture)
read_argument(skip_tests FALSE)
read_argument(subset)
read_argument(CXXFLAGS "")

# Set CMAKE_BUILD_TYPE from environment variable
################################################################################
set(appveyor $ENV{APPVEYOR})
if(appveyor)
   set(build_type "$ENV{CONFIGURATION}")
   if(NOT build_type)
      set(build_type "Release")
   endif()
else()
   read_argument(build_type "Release")
endif()

# better make sure we get english output (this is vital for the implicit_type_conversion_failures tests)
################################################################################
set(ENV{LANG} "en_US")

# determine the git branch we're testing
################################################################################
file(READ "${PROJECT_DIRECTORY}/.git/HEAD" git_branch)
string(STRIP "${git_branch}" git_branch)
# -> ref: refs/heads/foobar
string(REGEX REPLACE "^.*/" "" git_branch "${git_branch}")
# -> foobar
if(git_branch MATCHES "^[0-9a-f]+$")
   # it's a hash -> make it short
   string(SUBSTRING "${git_branch}" 0 7 git_branch)
elseif(git_branch MATCHES "^gh-[0-9]+")
   # it's a feature branch referencing a GitHub issue number -> make it short
   string(REGEX MATCH "^gh-[0-9]+" git_branch "${git_branch}")
endif()

# determine the (short) hostname of the build machine
################################################################################
set(travis_os $ENV{TRAVIS_OS_NAME})
if(travis_os)
   set(CTEST_SITE "Travis CI")
elseif(appveyor)
   set(CTEST_SITE "AppVeyor CI")
else()
   execute_process(COMMAND hostname -s RESULT_VARIABLE ok OUTPUT_VARIABLE CTEST_SITE ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
   if(NOT ok EQUAL 0)
      execute_process(COMMAND hostname OUTPUT_VARIABLE CTEST_SITE ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
   endif()
endif()

# collect system information for the "Build Name" (and build setup, e.g. -j)
################################################################################
find_program(UNAME uname)
if(UNAME)
   execute_process(COMMAND ${UNAME} -s OUTPUT_VARIABLE arch OUTPUT_STRIP_TRAILING_WHITESPACE)
   string(TOLOWER "${arch}" arch)
   execute_process(COMMAND ${UNAME} -m OUTPUT_VARIABLE chip OUTPUT_STRIP_TRAILING_WHITESPACE)
   string(TOLOWER "${chip}" chip)
   string(REPLACE "x86_64" "amd64" chip "${chip}")
else()
   find_program(CMD cmd)
   if(CMD)
      execute_process(COMMAND cmd /D /Q /C ver OUTPUT_VARIABLE arch OUTPUT_STRIP_TRAILING_WHITESPACE)
      string(REGEX REPLACE "^.*Windows[^0-9]*([.0-9]+).*$" "Windows \\1" arch "${arch}")
   else()
      string(TOLOWER "$ENV{TARGET_PLATFORM}" arch)
      if(arch)
         if("$ENV{WindowsSDKVersionOverride}")
            set(arch "${arch} SDK $ENV{WindowsSDKVersionOverride}")
         endif()
      else()
         string(TOLOWER "${CMAKE_SYSTEM_NAME}" arch)
      endif()
   endif()
   execute_process(COMMAND
      reg query "HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0" /v Identifier
      OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE processorId)
   if("${processorId}" MATCHES "(Intel|AMD)64")
      set(chip "amd64")
   elseif("${processorId}" MATCHES "x86")
      set(chip "x86")
   else()
      set(chip "unknown")
   endif()
endif()

# determine a short description of the OS we're running on
################################################################################
if(arch STREQUAL "linux")
   execute_process(COMMAND lsb_release -d COMMAND cut -f2 OUTPUT_VARIABLE os_ident)
   string(REGEX REPLACE "\\(.*\\)" "" os_ident "${os_ident}") # shorten the Distribution string, stripping everything in parens
   string(REPLACE "Scientific Linux SL" "SL" os_ident "${os_ident}")
   string(REPLACE " release" "" os_ident "${os_ident}")
   string(REPLACE " GNU/Linux" "" os_ident "${os_ident}")
   string(REPLACE "openSUSE" "Suse" os_ident "${os_ident}")
   string(REPLACE " User Edition" "" os_ident "${os_ident}")
   string(STRIP "${os_ident}" os_ident)
elseif(arch STREQUAL "darwin")
   set(os_ident "OSX")
else()
   set(os_ident "${arch}")
   string(REPLACE "Windows" "Win" os_ident "${os_ident}")
endif()

# Determine the processor count (number_of_processors)
################################################################################
read_argument(number_of_processors)
if(NOT number_of_processors)
   if("${arch}" MATCHES "[Ww]indows" OR "${arch}" MATCHES "win7" OR "${arch}" MATCHES "mingw" OR "${arch}" MATCHES "msys")
      execute_process(COMMAND
         reg query "HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor"
         OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
      string(REGEX REPLACE "[^0-9]+" "," number_of_processors "${number_of_processors}")
      string(REGEX REPLACE "^.*," "" number_of_processors "${number_of_processors}")
      math(EXPR number_of_processors "1 + ${number_of_processors}")
   elseif("${arch}" STREQUAL "darwin")
      execute_process(COMMAND sysctl -n hw.ncpu OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
   else()
      execute_process(COMMAND grep -c processor /proc/cpuinfo OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
   endif()
endif()

# Determine the compiler version string
################################################################################
set(compiler)
macro(extract_msvc_compiler_info CL)
   if(CL)
      execute_process(COMMAND ${CL} /nologo -EP "${PROJECT_DIRECTORY}/cmake/msvc_version.c" OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE COMPILER_VERSION)
      string(STRIP "${COMPILER_VERSION}" COMPILER_VERSION)
      if("${CL}" MATCHES "amd64")
         set(COMPILER_VERSION "${COMPILER_VERSION} amd64")
      elseif("${CL}" MATCHES "ia64")
         set(COMPILER_VERSION "${COMPILER_VERSION} ia64")
      else()
         set(COMPILER_VERSION "${COMPILER_VERSION} x86")
      endif()
      set(compiler "MSVC")
   else()
      message(FATAL_ERROR "unknown compiler")
   endif()
endmacro()
macro(extract_gnuc_compiler_info CXX)
   execute_process(COMMAND "${CXX}" --version OUTPUT_VARIABLE COMPILER_VERSION_COMPLETE ERROR_VARIABLE COMPILER_VERSION_COMPLETE OUTPUT_STRIP_TRAILING_WHITESPACE)
   string(REPLACE "\n" ";" COMPILER_VERSION "${COMPILER_VERSION_COMPLETE}")
   list(GET COMPILER_VERSION 0 COMPILER_VERSION)
   string(REPLACE "Open64 Compiler Suite: Version" "Open64" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REPLACE "icpc" "ICC" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REPLACE "gxx" "GCC" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REPLACE "g++" "GCC" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REPLACE ".exe" "" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REPLACE " version" "" COMPILER_VERSION "${COMPILER_VERSION}")
   if(COMPILER_VERSION MATCHES "based on LLVM ")
      # e.g. "Apple LLVM version 6.0 (clang-600.0.57) (based on LLVM 3.5svn)"
      string(REGEX REPLACE ".*based on LLVM" "clang" COMPILER_VERSION "${COMPILER_VERSION}")
      string(REPLACE ")" "" COMPILER_VERSION "${COMPILER_VERSION}")
   endif()
   string(REGEX REPLACE " \\([^()]*\\)" "" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REGEX REPLACE " \\[.*\\]" "" COMPILER_VERSION "${COMPILER_VERSION}")
   string(REGEX REPLACE "GCC-[0-9](\\.[0-9])?" "GCC" COMPILER_VERSION "${COMPILER_VERSION}")
   string(STRIP "${COMPILER_VERSION}" COMPILER_VERSION)
   if(COMPILER_VERSION_COMPLETE MATCHES "Free Software Foundation, Inc." AND NOT COMPILER_VERSION MATCHES "GCC")
      # it's GCC but without "GCC" in the COMPILER_VERSION string - fix it up
      string(REPLACE "cxx" "GCC" COMPILER_VERSION "${COMPILER_VERSION}")
      string(REPLACE "c++" "GCC" COMPILER_VERSION "${COMPILER_VERSION}")
      if(NOT COMPILER_VERSION MATCHES "GCC")
         set(COMPILER_VERSION "GCC (${COMPILER_VERSION})")
      endif()
   endif()
   if(COMPILER_VERSION MATCHES "clang")
      set(compiler "clang")
   elseif(COMPILER_VERSION MATCHES "ICC")
      set(compiler "ICC")
   elseif(COMPILER_VERSION MATCHES "Open64")
      set(compiler "Open64")
   elseif(COMPILER_VERSION MATCHES "GCC")
      if(WIN32)
         set(compiler "MinGW")
      else()
         set(compiler "GCC")
      endif()
   endif()
endmacro()
if("${arch}" MATCHES "[Ww]indows" OR "${arch}" MATCHES "win7" OR "${arch}" MATCHES "msys")
   find_program(CL cl)
   extract_msvc_compiler_info(${CL})
elseif(arch MATCHES "mingw")
   if("$ENV{CXX}" MATCHES "g\\+\\+" OR "$ENV{CXX}" MATCHES "gxx")
      set(GXX "$ENV{CXX}")
   else()
      find_program(GXX NAMES "g++" "gxx")
   endif()
   if(GXX)
      extract_gnuc_compiler_info("${GXX}")
   else()
      find_program(CL cl)
      extract_msvc_compiler_info(${CL})
   endif()
else()
   set(CXX "$ENV{CXX}")
   if(NOT CXX)
      unset(CXX)
      find_program(CXX NAMES c++ g++ clang++ icpc)
      if(NOT CXX)
         message(FATAL_ERROR "No C++ compiler found (arch: ${arch})")
      endif()
   endif()
   extract_gnuc_compiler_info("${CXX}")
endif()

# Build the CTEST_BUILD_NAME string
################################################################################
if(DEFINED target_architecture)
   set(tmp ${target_architecture})
else()
   execute_process(
      COMMAND cmake
      "-Darch=${arch}"
      "-DCMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}"
      -P ${PROJECT_DIRECTORY}/cmake/print_target_architecture.cmake
      OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE tmp)
   string(REPLACE "-- " "" tmp "${tmp}")
endif()
if(build_type STREQUAL "Release")
   set(build_type_short "Rel")
elseif(build_type STREQUAL "Debug")
   set(build_type_short "Deb")
elseif(build_type STREQUAL "RelWithDebInfo")
   set(build_type_short "RDI")
elseif(build_type STREQUAL "RelWithDebug")
   set(build_type_short "RWD")
elseif(build_type STREQUAL "None")
   set(build_type_short "Non")
else()
   set(build_type_short "${build_type}")
endif()
string(STRIP "${git_branch} ${COMPILER_VERSION} ${CXXFLAGS} ${build_type_short} ${tmp} ${chip} ${os_ident}" CTEST_BUILD_NAME)
if(DEFINED subset)
   set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME} ${subset}")
endif()

string(REPLACE "  " " " CTEST_BUILD_NAME "${CTEST_BUILD_NAME}")

# work around CDash limitations:
string(REPLACE "/" "_" CTEST_BUILD_NAME "${CTEST_BUILD_NAME}")
string(REPLACE "+" "x" CTEST_BUILD_NAME "${CTEST_BUILD_NAME}")

# Determine build directory
################################################################################
string(REGEX REPLACE "[][ ():, ]" "" CTEST_BINARY_DIRECTORY "${CTEST_BUILD_NAME}")
set(CTEST_BINARY_DIRECTORY "${PROJECT_DIRECTORY}/build-${dashboard_model}/${CTEST_BINARY_DIRECTORY}")

# Give user feedback
################################################################################
#message("src:        ${PROJECT_DIRECTORY}")
#message("obj:        ${CTEST_BINARY_DIRECTORY}")
message("build name: ${CTEST_BUILD_NAME}")
message("site:       ${CTEST_SITE}")
message("model:      ${dashboard_model}")

Set(CTEST_START_WITH_EMPTY_BINARY_DIRECTORY_ONCE TRUE)

list(APPEND CTEST_NOTES_FILES "${PROJECT_DIRECTORY}/.git/HEAD")
if(EXISTS "${PROJECT_DIRECTORY}/.git/refs/heads/${git_branch}")
   list(APPEND CTEST_NOTES_FILES "${PROJECT_DIRECTORY}/.git/refs/heads/${git_branch}")
endif()

include(${CTEST_SOURCE_DIRECTORY}/CTestConfig.cmake)
ctest_read_custom_files(${CTEST_SOURCE_DIRECTORY})
if(WIN32)
   set(MAKE_ARGS "-k")
else()
   set(MAKE_ARGS "-j${number_of_processors} -l${number_of_processors} -k")
endif()

if(WIN32)
   if("${compiler}" STREQUAL "MSVC")
      find_program(NINJA ninja)
      find_program(JOM jom)
      if(NINJA)
         set(CTEST_CMAKE_GENERATOR "Ninja")
         set(CMAKE_MAKE_PROGRAM "${NINJA}")
         set(MAKE_ARGS "-k50")
      elseif(JOM)
         set(CTEST_CMAKE_GENERATOR "NMake Makefiles JOM")
         set(CMAKE_MAKE_PROGRAM "${JOM}")
      else()
         set(CTEST_CMAKE_GENERATOR "NMake Makefiles")
         set(CMAKE_MAKE_PROGRAM "nmake")
         set(MAKE_ARGS "-I")
      endif()
   elseif("${compiler}" STREQUAL "MinGW")
      set(CTEST_CMAKE_GENERATOR "MSYS Makefiles")
      set(CMAKE_MAKE_PROGRAM "make")
   else()
      message(FATAL_ERROR "unknown cmake generator required (compiler: ${compiler})")
   endif()
else()
   set(CTEST_CMAKE_GENERATOR "Unix Makefiles")
   set(CMAKE_MAKE_PROGRAM "make")
endif()

set(configure_options "-DCTEST_USE_LAUNCHERS=${CTEST_USE_LAUNCHERS}")
list(APPEND configure_options "-DCMAKE_BUILD_TYPE=${build_type}")
list(APPEND configure_options "-DBUILD_TESTING=TRUE")
list(APPEND configure_options "-DBUILD_EXAMPLES=FALSE")
list(APPEND configure_options "-DUSE_CCACHE=ON")
if(DEFINED target_architecture)
   list(APPEND configure_options "-DTARGET_ARCHITECTURE=${target_architecture}")
endif()

if("${COMPILER_VERSION}" MATCHES "(GCC|Open64).*4\\.[012345678]\\."
      OR "${COMPILER_VERSION}" MATCHES "clang 3\\.[0123456]")
   message(FATAL_ERROR "Compiler too old for C++14 (${COMPILER_VERSION})")
endif()

macro(go)
   # SubProjects currently don't improve the overview but rather make the dashboard more cumbersume to navigate
   #set_property(GLOBAL PROPERTY SubProject "master: ${compiler}")
   set_property(GLOBAL PROPERTY Label other)
   CTEST_START (${dashboard_model})
   set(res 0)
   if(NOT is_experimental)
      CTEST_UPDATE (SOURCE "${PROJECT_DIRECTORY}" RETURN_VALUE res)
      if(res GREATER 0)
         ctest_submit(PARTS Update)
      endif()
   endif()

   # enter the following section for Continuous builds only if the CTEST_UPDATE above found changes
   if(NOT is_continuous OR res GREATER 0)
      CTEST_CONFIGURE (BUILD "${CTEST_BINARY_DIRECTORY}"
         SOURCE "${PROJECT_DIRECTORY}"
         OPTIONS "${configure_options}"
         APPEND
         RETURN_VALUE res)
      list(APPEND CTEST_NOTES_FILES
         #"${CTEST_BINARY_DIRECTORY}/CMakeFiles/CMakeOutput.log"
         "${CTEST_BINARY_DIRECTORY}/CMakeFiles/CMakeError.log"
         )
      ctest_submit(PARTS Notes Configure)
      unset(CTEST_NOTES_FILES) # less clutter in ctest -V output
      if(res EQUAL 0)
         set(test_results 0)
         if(FALSE AND travis_os) # disable this branch for now, testing subsets on travis
            set(CTEST_BUILD_COMMAND "${CMAKE_MAKE_PROGRAM} ${MAKE_ARGS}")
            ctest_build(
               BUILD "${CTEST_BINARY_DIRECTORY}"
               APPEND
               RETURN_VALUE res)
            ctest_submit(PARTS Build)
            ctest_test(
               BUILD "${CTEST_BINARY_DIRECTORY}"
               APPEND
               RETURN_VALUE test_results
               PARALLEL_LEVEL ${number_of_processors})
            ctest_submit(PARTS Test)
         else()
            if("${subset}" STREQUAL "sse")
               set(label_list other NoSIMD SSE)
            elseif("${subset}" STREQUAL "avx")
               set(label_list AVX AVX2)
            elseif("${subset}" STREQUAL "avx512")
               set(label_list MIC KNL AVX512)
            else()
               set(label_list other NoSIMD SSE AVX AVX2 MIC KNL AVX512)
            endif()
            foreach(label ${label_list})
               set_property(GLOBAL PROPERTY Label ${label})
               set(CTEST_BUILD_TARGET "${label}")
               set(CTEST_BUILD_COMMAND "${CMAKE_MAKE_PROGRAM} ${MAKE_ARGS} ${CTEST_BUILD_TARGET}")
               ctest_build(
                  BUILD "${CTEST_BINARY_DIRECTORY}"
                  APPEND
                  RETURN_VALUE res)
               ctest_submit(PARTS Build)
               if(res EQUAL 0 AND NOT skip_tests)
                  execute_process(
                     COMMAND ${CMAKE_CTEST_COMMAND} -N -L "^${label}$"
                     WORKING_DIRECTORY "${CTEST_BINARY_DIRECTORY}"
                     OUTPUT_VARIABLE tmp
                     OUTPUT_STRIP_TRAILING_WHITESPACE)
                  if(tmp MATCHES "Total Tests: 0")
                     message("No tests were defined. Skipping tests.")
                  else()
                     ctest_test(
                        BUILD "${CTEST_BINARY_DIRECTORY}"
                        APPEND
                        RETURN_VALUE res
                        PARALLEL_LEVEL ${number_of_processors}
                        INCLUDE_LABEL "^${label}$")
                     ctest_submit(PARTS Test)
                     if(NOT res EQUAL 0)
                        message("ctest_test returned non-zero result: ${res}")
                        set(test_results ${res})
                     endif()
                  endif()
               endif()
            endforeach()
         endif()
      endif()
   endif()
endmacro()

if(is_continuous)
   while(${CTEST_ELAPSED_TIME} LESS 64800)
      set(START_TIME ${CTEST_ELAPSED_TIME})
      go()
      ctest_sleep(${START_TIME} 1200 ${CTEST_ELAPSED_TIME})
   endwhile()
else()
   if(EXISTS "${CTEST_BINARY_DIRECTORY}")
      CTEST_EMPTY_BINARY_DIRECTORY(${CTEST_BINARY_DIRECTORY})
   endif()
   go()
   if(NOT test_results EQUAL 0)
      message(FATAL_ERROR "One or more tests failed.")
   endif()
endif()
