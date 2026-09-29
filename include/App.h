#pragma once
#include <windows.h>
#include <cstdint>
#include <memory>
#include <DirectXMath.h>
#include "D3D12Context.h"

class Window;
class Input;

class App
{
public:
    App();
    ~App();

    bool Initialize(HINSTANCE hInstance, int nCmdShow);
    int Run();
    LRESULT HandleWindowMessage(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

private:
    void Update(float dt);

    std::unique_ptr<Window> m_window;
    std::unique_ptr<Input> m_input;
    std::unique_ptr<D3D12Context> m_dx12;

    bool m_exitRequested = false;
    uint64_t m_prevTick = 0;
    double m_secondsPerTick = 0.0;

    float m_camYaw = DirectX::XM_PI;
    float m_camPitch = -0.1f;
    DirectX::XMFLOAT3 m_camPos{ 0.5f, 3.5f, 10.f };

    POINT m_savedCursorPos{ 0, 0 };
    bool m_justEnteredRmbLook = false;
};
