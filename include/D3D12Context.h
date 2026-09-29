#pragma once
#include <windows.h>
#include <DirectXMath.h>
#include <cstdint>
#include <memory>

class RenderingSystem;

class D3D12Context
{
public:
    D3D12Context();
    ~D3D12Context();

    bool Initialize(HWND hwnd, uint32_t width, uint32_t height);
    void Shutdown();

    void OnResize(uint32_t width, uint32_t height);
    void Draw(float dt);
    void SetCamera(const DirectX::XMFLOAT3& eyePos, float yaw, float pitch);

    void ToggleSceneMode();
    void ToggleFrustumCulling();
    void ToggleOctreeCulling();
    void ToggleInstancing();
    bool FrustumCullingOn() const;
    bool OctreeCullingOn() const;
    bool ScatterModeOn() const;
    uint32_t ScatterVisibleCount() const;
    uint32_t ScatterTotalCount() const;
    bool InstancingOn() const;
    float LastCullMicroseconds() const;
    uint32_t LastAabbTests() const;
    uint32_t LastDrawCalls() const;

private:
    std::unique_ptr<RenderingSystem> m_renderer;
};