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
    void RotateSun(float deltaAzimuth, float deltaHeight);

    void ToggleCascadeDebug();
    void TogglePcf();
    void ToggleShadowCulling();
    void CycleSplitLambda();
    bool CascadeDebugOn() const;
    bool PcfOn() const;
    bool ShadowCullingOn() const;
    float GetSplitLambda() const;
    DirectX::XMFLOAT4 GetCascadeSplits() const;
    uint32_t ShadowDrawCalls() const;

    void ToggleEmitter();
    void TogglePauseParticles();
    void ScaleEmitRate(float factor);
    bool EmitterOn() const;
    bool ParticlesPaused() const;
    float EmitRate() const;
    uint32_t AliveParticles() const;

private:
    std::unique_ptr<RenderingSystem> m_renderer;
};