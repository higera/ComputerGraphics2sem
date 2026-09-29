cmake_minimum_required(VERSION 3.20)
project(dx12_textures_winapi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 1. Исходники (.cpp) — все из папки src
add_executable(dx12_textures
        src/main.cpp
        src/App.cpp
        src/Window.cpp
        src/Input.cpp
        src/D3D12Context.cpp
        src/GBuffer.cpp
        src/RenderingSystem.cpp
        src/Frustum.cpp
        src/Octree.cpp
        src/ShadowMap.cpp
)

# 2. Заголовки (.h) — ищем в папке include
target_include_directories(dx12_textures PRIVATE include)

# 3. Макросы Windows
target_compile_definitions(dx12_textures PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)

# 4. Исходники в UTF-8 (русские комментарии и строки).
#    Без /utf-8 MSVC на русской Windows читает их как CP1251, и L"Ошибка" превращается в мусор.
if (MSVC)
    target_compile_options(dx12_textures PRIVATE /utf-8)
endif()

# 5. Это GUI приложение (точка входа wWinMain, без консоли)
set_target_properties(dx12_textures PROPERTIES WIN32_EXECUTABLE TRUE)

# MinGW не знает wWinMain без этого флага
if (MINGW)
    target_link_options(dx12_textures PRIVATE -municode)
endif()

# 6. Библиотеки.
#    ИСПРАВЛЕНО: windowscodecs, ole32, dxguid, uuid раньше подключались только через
#    #pragma comment в App.cpp — это работает лишь в MSVC.
target_link_libraries(dx12_textures PRIVATE
        user32
        gdi32
        dxgi
        d3d12
        d3dcompiler
        dxguid
        windowscodecs
        ole32
        uuid
)

# 7. Рабочая папка при запуске из Visual Studio = корень проекта (там лежат shaders/ и sponza/).
#    В CLion: Run/Debug Configurations -> Working directory = $ProjectFileDir$
#    (впрочем, ResolveAssetPath и так ищет файлы в ../ и ../../).
set_target_properties(dx12_textures PROPERTIES
        VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
