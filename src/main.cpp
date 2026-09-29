#include "App.h"
#include <windows.h>
#include <exception>
#include <string>

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR, int nCmdShow)
{
    try
    {
        App app;

        if (!app.Initialize(hInstance, nCmdShow))
            return 0;

        return app.Run();
    }
    catch (const std::exception& e)
    {
        std::string msg = e.what();
        int len = MultiByteToWideChar(CP_ACP, 0, msg.c_str(), (int)msg.size(), nullptr, 0);
        std::wstring wmsg(len, L'\0');
        MultiByteToWideChar(CP_ACP, 0, msg.c_str(), (int)msg.size(), wmsg.data(), len);
        MessageBoxW(nullptr, wmsg.c_str(), L"Ошибка", MB_OK | MB_ICONERROR);
        return -1;
    }
}
