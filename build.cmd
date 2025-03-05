@echo off
setlocal EnableDelayedExpansion

REM
REM Architectures
REM

if "%PROCESSOR_ARCHITECTURE%" equ "AMD64" (
  set HOST_ARCH=x64
) else if "%PROCESSOR_ARCHITECTURE%" equ "ARM64" (
  set HOST_ARCH=arm64
)

if "%1" equ "x64" (
  set TARGET_ARCH=x64
) else if "%1" equ "arm64" (
  set TARGET_ARCH=arm64
) else if "%1" neq "" (
  echo Unknown target "%1" architecture!
  exit /b 1
) else (
  set TARGET_ARCH=%HOST_ARCH%
)

REM
REM Library Versions
REM

set NINJA_VERSION=1.12.1

set ZLIB_VERSION=1.3.1
set SNAPPY_VERSION=1.2.1
set ZSTD_VERSION=1.5.7

REM
REM Output Folder
REM

set OUTPUT=%~dp0leveldb-%TARGET_ARCH%
if not exist %OUTPUT% mkdir %OUTPUT%

REM
REM Temporary Folders
REM

set DOWNLOAD=%~dp0download
set SOURCE=%~dp0source
set BUILD=%~dp0build-%TARGET_ARCH%
set DEPEND=%~dp0depend-%TARGET_ARCH%

if not exist %DOWNLOAD% mkdir %DOWNLOAD% || exit /b 1
if not exist %SOURCE%   mkdir %SOURCE%   || exit /b 1
if not exist %BUILD%    mkdir %BUILD%    || exit /b 1
if not exist %DEPEND%   mkdir %DEPEND%   || exit /b 1

cd %~dp0
set PATH=%DOWNLOAD%;%PATH%

REM
REM Dependencies
REM

where.exe /Q curl.exe || (
        echo "ERROR: curl.exe was not found."
        exit /B 1
)

where.exe /Q tar.exe || (
        echo "ERROR: tar.exe was not found."
        exit /B 1
)

where.exe /Q git.exe || (
        echo "ERROR: git.exe was not found."
        exit /B 1
)

where.exe /Q cmake.exe || (
        echo "ERROR: cmake.exe was not found."
        exit /B 1
)

where /Q ninja.exe || (
  echo Downloading ninja
  pushd %DOWNLOAD%
  if "%HOST_ARCH%" equ "x64" (
    curl.exe -Lsfo ninja-win.zip "https://github.com/ninja-build/ninja/releases/download/v%NINJA_VERSION%/ninja-win.zip" || exit /b 1
  ) else if "%HOST_ARCH%" equ "arm64" (
    curl.exe -Lsfo ninja-win.zip "https://github.com/ninja-build/ninja/releases/download/v%NINJA_VERSION%/ninja-winarm64.zip" || exit /b 1
  )
  tar.exe -xf ninja-win.zip || exit /b 1
  popd
)
ninja.exe --version || exit /b 1

call :get "https://github.com/madler/zlib/releases/download/v%ZLIB_VERSION%/zlib-%ZLIB_VERSION%.tar.gz"         || exit /b 1
call :get "https://github.com/google/snappy/archive/refs/tags/%SNAPPY_VERSION%.tar.gz" %SNAPPY_VERSION%.tar.gz  || exit /b 1
call :get "https://github.com/facebook/zstd/releases/download/v%ZSTD_VERSION%/zstd-%ZSTD_VERSION%.tar.gz"       || exit /b 1
call :clone leveldb "https://github.com/Mojang/leveldb.git" main                                                || exit /b 1

rem
rem apply patches
rem 

call git apply -p1 --directory=source/leveldb patches/leveldb.patch || exit /b 1

rem
rem MSVC Environment
rem

where /q cl.exe || (
  for /f "tokens=*" %%i in ('"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath') do set VS=%%i
  if "!VS!" equ "" (
    echo ERROR: Visual Studio installation not found
    exit /b 1
  )

  call "!VS!\Common7\Tools\VsDevCmd.bat" -arch=%TARGET_ARCH% -host_arch=%HOST_ARCH% -startdir=none -no_logo || exit /b 1
)

rem
rem Build Flags
rem

set CMAKE_COMMON_ARGS=-Wno-dev                          ^
  -G Ninja                                              ^
  -D CMAKE_BUILD_TYPE="Release"                         ^
  -D CMAKE_POLICY_DEFAULT_CMP0074=NEW                   ^
  -D CMAKE_POLICY_DEFAULT_CMP0091=NEW                   ^
  -D CMAKE_POLICY_DEFAULT_CMP0092=NEW                   ^
  -D CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded

REM
REM zlib
REM

cmake.exe %CMAKE_COMMON_ARGS%                           ^
  -S %SOURCE%\zlib-%ZLIB_VERSION%                       ^
  -B %BUILD%\zlib-%ZLIB_VERSION%                        ^
  -D CMAKE_INSTALL_PREFIX=%DEPEND%                      ^
  -D BUILD_SHARED_LIBS=OFF                              ^
  || exit /b 1
ninja.exe -C %BUILD%\zlib-%ZLIB_VERSION% install || exit /b 1

del %DEPEND%\lib\zlib.lib 1>nul 2>nul

REM
REM snappy
REM

cmake.exe %CMAKE_COMMON_ARGS%                           ^
  -S %SOURCE%\snappy-%SNAPPY_VERSION%                   ^
  -B %BUILD%\snappy-%SNAPPY_VERSION%                    ^
  -D BUILD_SHARED_LIBS=OFF                              ^
  -D SNAPPY_BUILD_TESTS=OFF                             ^
  -D SNAPPY_BUILD_BENCHMARKS=OFF                        ^
  -D SNAPPY_FUZZING_BUILD=OFF                           ^
  -D SNAPPY_REQUIRE_AVX=OFF                             ^
  -D SNAPPY_REQUIRE_AVX2=OFF                            ^
  -D SNAPPY_INSTALL=ON                                  ^
  -D CMAKE_INSTALL_PREFIX=%DEPEND%                      ^
  -D BUILD_SHARED_LIBS=OFF                              ^
  || exit /b 1
ninja.exe -C %BUILD%\snappy-%SNAPPY_VERSION% install || exit /b 1

REM
REM zstd
REM

cmake.exe %CMAKE_COMMON_ARGS%                           ^
  -S %SOURCE%\zstd-%ZSTD_VERSION%\build\cmake           ^
  -B %BUILD%\zstd-%ZSTD_VERSION%                        ^
  -D CMAKE_INSTALL_PREFIX=%DEPEND%                      ^
  -D BUILD_SHARED_LIBS=OFF                              ^
  -D ZSTD_BUILD_STATIC=ON                               ^
  -D ZSTD_BUILD_SHARED=OFF                              ^
  -D ZSTD_BUILD_PROGRAMS=OFF                            ^
  -D ZSTD_BUILD_CONTRIB=OFF                             ^
  -D ZSTD_BUILD_TESTS=OFF                               ^
  -D ZSTD_LEGACY_SUPPORT=ON                             ^
  -D ZSTD_MULTITHREAD_SUPPORT=ON                        ^
  -D ZSTD_USE_STATIC_RUNTIME=ON                         ^
  || exit /b 1
ninja.exe -C %BUILD%\zstd-%ZSTD_VERSION% install || exit /b 1

REM
REM leveldb
REM

set LEVELDB_FLAGS=-LIBPATH:%DEPEND%\lib zlibstatic.lib snappy.lib zstd_static.lib

cmake.exe %CMAKE_COMMON_ARGS%                           ^
  -S %SOURCE%\leveldb                                   ^
  -B %BUILD%\leveldb                                    ^
  -D CMAKE_INSTALL_PREFIX=%OUTPUT%                      ^
  -D CMAKE_PREFIX_PATH=%DEPEND%                         ^
  -D CMAKE_STATIC_LINKER_FLAGS="%LEVELDB_FLAGS%"        ^
  -D LEVELDB_BUILD_TESTS=OFF                            ^
  -D LEVELDB_BUILD_BENCHMARKS=OFF                       ^
  -D LEVELDB_INSTALL=ON                                 ^
  -D LEVELDB_DISABLE_RTTI=OFF                           ^
  -D LEVELDB_SUPPORT_LEGACY_ZLIB_ENUM=ON                ^
  || exit /b 1
ninja.exe -C %BUILD%\leveldb install || exit /b 1

rem
rem GitHub Actions
rem

if "%GITHUB_WORKFLOW%" neq "" (

  for /F "tokens=*" %%D in ('date /t') do (set LDATE=%%D & goto :dateok)
  :dateok
  set OUTPUT_DATE=%LDATE:~10,4%-%LDATE:~4,2%-%LDATE:~7,2%
  
  echo OUTPUT_DATE=!OUTPUT_DATE!>>%GITHUB_OUTPUT%

  echo Creating leveldb-%TARGET_ARCH%-!OUTPUT_DATE!.zip
  7z.exe a -y -r -mx=9 leveldb-%TARGET_ARCH%-!OUTPUT_DATE!.zip leveldb-%TARGET_ARCH% || exit /b 1
)

rem
rem done!
rem

goto :eof

REM
REM call :get "https://..." [optional-filename.tar.gz] [unpack folder]
REM

:get
if "%2" equ "" (
  set ARCHIVE=%DOWNLOAD%\%~nx1
  set DNAME=%~nx1
) else (
  set ARCHIVE=%DOWNLOAD%\%2
  set DNAME=%2
)
if not exist %ARCHIVE% (
  echo Downloading %DNAME%
  curl.exe --retry 5 --retry-all-errors -sfLo %ARCHIVE% %1 || exit /b 1
)
for %%N in ("%ARCHIVE%") do set NAME=%%~nN
if exist %NAME% (
  echo Removing %NAME%
  rd /s /q %NAME%
)
echo Unpacking %DNAME%
if "%3" equ "" (
  pushd %SOURCE%
) else (
  if not exist "%3" mkdir "%3"
  pushd %3
)
tar.exe -xf %ARCHIVE%
popd
goto :eof

REM
REM call :clone "https://..." branch-name
REM

:clone
pushd %SOURCE%
if exist %1 (
  echo Updating %1
  pushd %1
  call git clean --quiet -fdx
  call git fetch --quiet --no-tags origin %3:refs/remotes/origin/%3 || exit /b 1
  call git reset --quiet --hard origin/%3 || exit /b 1
  popd
) else (
  echo Cloning %1
  call git clone --quiet --branch %3 --no-tags --depth 1 %2 %1 || exit /b 1
)
popd
goto :eof