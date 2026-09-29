#pragma once

#include <wrl.h>
#include <d3d12.h>
#include <DirectXMath.h>
#include <cstdint>
#include <string>

struct Particle
{
    DirectX::XMFLOAT3 Position;
    float             Size;
    DirectX::XMFLOAT3 Velocity;
    float             Lifetime;
};
static_assert(sizeof(Particle) == 32, "Particle должна совпадать с HLSL-структурой");

class ParticleSystem
{
public:
    static constexpr uint32_t MaxParticles = 65536;

    void Initialize(ID3D12Device* device, ID3D12CommandQueue* queue, const std::wstring& computeShaderPath);
    void Shutdown();

    DirectX::XMFLOAT3 EmitterPos{ 2.0f, 0.02f, 0.0f };
    float             EmitRate = 4000.0f;
    float             EmitSpeed = 5.0f;
    DirectX::XMFLOAT3 Gravity{ 0.0f, -9.8f, 0.0f };
    float             FloorY = 0.02f;
    float             Restitution = 0.45f;
    bool              EmitterEnabled = true;
    bool              Paused = false;

    uint32_t ReadAliveCount() const;

    void Simulate(ID3D12GraphicsCommandList* cmdList, float dt);

    ID3D12DescriptorHeap* GetUavHeap() const { return m_uavHeap.Get(); }
    D3D12_GPU_DESCRIPTOR_HANDLE GetUavTable() const;

    void ResetAppendCounter(ID3D12GraphicsCommandList* cmdList);

    void CopyConsumeCount(ID3D12GraphicsCommandList* cmdList);

    void PrepareDraw(ID3D12GraphicsCommandList* cmdList);

    void FinishFrame(ID3D12GraphicsCommandList* cmdList);

    D3D12_VERTEX_BUFFER_VIEW GetVertexBufferView() const;
    ID3D12Resource* GetIndirectArgs() const { return m_args.Get(); }
    ID3D12CommandSignature* GetDrawSignature() const { return m_drawSignature.Get(); }

    ID3D12Resource* GetBuffer(uint32_t i) const { return m_buffers[i].Get(); }
    uint32_t CounterOffset() const { return m_counterOffset; }
    uint32_t AppendIndex() const { return 1u - m_consumeIndex; }

private:
    void Transition(ID3D12GraphicsCommandList* cmdList, ID3D12Resource* resource,
                    D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after);

private:
    Microsoft::WRL::ComPtr<ID3D12Resource> m_buffers[2];
    uint32_t m_counterOffset = 0;
    uint32_t m_consumeIndex = 0;

    Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> m_uavHeap;
    uint32_t m_descriptorSize = 0;

    Microsoft::WRL::ComPtr<ID3D12Resource> m_args;
    Microsoft::WRL::ComPtr<ID3D12CommandSignature> m_drawSignature;
    Microsoft::WRL::ComPtr<ID3D12Resource> m_countBuffer;
    Microsoft::WRL::ComPtr<ID3D12RootSignature> m_computeRootSig;
    Microsoft::WRL::ComPtr<ID3D12PipelineState> m_simulatePSO;
    Microsoft::WRL::ComPtr<ID3D12PipelineState> m_emitPSO;
    float    m_emitAccum = 0.0f;
    uint32_t m_frameIndex = 0;
    Microsoft::WRL::ComPtr<ID3D12Resource> m_zeroUpload;
    Microsoft::WRL::ComPtr<ID3D12Resource> m_argsInitUpload;
    Microsoft::WRL::ComPtr<ID3D12Resource> m_readback;
};
