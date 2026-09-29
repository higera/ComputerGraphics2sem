#include "D3D12Context.h"
#include "RenderingSystem.h"

D3D12Context::D3D12Context() = default;
D3D12Context::~D3D12Context() { Shutdown(); }

bool D3D12Context::Initialize(HWND hwnd, uint32_t width, uint32_t height)
{
    m_renderer = std::make_unique<RenderingSystem>();
    return m_renderer->Initialize(hwnd, width, height);
}

void D3D12Context::Shutdown()
{
    if (m_renderer)
    {
        m_renderer->Shutdown();
        m_renderer.reset();
    }
}

void D3D12Context::OnResize(uint32_t width, uint32_t height)
{
    if (m_renderer)
        m_renderer->OnResize(width, height);
}

void D3D12Context::Draw(float dt)
{
    if (m_renderer)
        m_renderer->Draw(dt);
}

void D3D12Context::SetCamera(const DirectX::XMFLOAT3& eyePos, float yaw, float pitch)
{
    if (m_renderer)
        m_renderer->SetCamera(eyePos, yaw, pitch);
}

void D3D12Context::RotateSun(float deltaAzimuth, float deltaHeight)
{
    if (m_renderer)
        m_renderer->RotateSun(deltaAzimuth, deltaHeight);
}

void D3D12Context::ToggleCascadeDebug()  { if (m_renderer) m_renderer->ToggleCascadeDebug(); }
void D3D12Context::TogglePcf()           { if (m_renderer) m_renderer->TogglePcf(); }
void D3D12Context::ToggleShadowCulling() { if (m_renderer) m_renderer->ToggleShadowCulling(); }
void D3D12Context::CycleSplitLambda()    { if (m_renderer) m_renderer->CycleSplitLambda(); }
bool D3D12Context::CascadeDebugOn() const  { return m_renderer ? m_renderer->CascadeDebugOn() : false; }
bool D3D12Context::PcfOn() const           { return m_renderer ? m_renderer->PcfOn() : false; }
bool D3D12Context::ShadowCullingOn() const { return m_renderer ? m_renderer->ShadowCullingOn() : false; }
float D3D12Context::GetSplitLambda() const { return m_renderer ? m_renderer->GetSplitLambda() : 0.f; }
DirectX::XMFLOAT4 D3D12Context::GetCascadeSplits() const { return m_renderer ? m_renderer->GetCascadeSplits() : DirectX::XMFLOAT4{}; }
uint32_t D3D12Context::ShadowDrawCalls() const { return m_renderer ? m_renderer->ShadowDrawCalls() : 0; }

void D3D12Context::ToggleEmitter()               { if (m_renderer) m_renderer->ToggleEmitter(); }
void D3D12Context::TogglePauseParticles()        { if (m_renderer) m_renderer->TogglePauseParticles(); }
void D3D12Context::ScaleEmitRate(float factor)   { if (m_renderer) m_renderer->ScaleEmitRate(factor); }
bool D3D12Context::EmitterOn() const             { return m_renderer ? m_renderer->EmitterOn() : false; }
bool D3D12Context::ParticlesPaused() const       { return m_renderer ? m_renderer->ParticlesPaused() : false; }
float D3D12Context::EmitRate() const             { return m_renderer ? m_renderer->EmitRate() : 0.f; }
uint32_t D3D12Context::AliveParticles() const    { return m_renderer ? m_renderer->AliveParticles() : 0; }

void D3D12Context::SetPostEffects(bool vignette, bool chroma, bool toneMapping, int debugView)
{
    if (m_renderer)
        m_renderer->SetPostEffects(vignette, chroma, toneMapping, debugView);
}
