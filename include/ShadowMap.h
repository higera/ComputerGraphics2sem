#pragma once

#include <wrl.h>
#include <d3d12.h>
#include <DirectXMath.h>
#include <cstdint>
#include "Frustum.h"

struct alignas(16) ShadowConstants
{
    DirectX::XMFLOAT4X4 LightViewProj[4];
    DirectX::XMFLOAT4   CascadeSplits;
    DirectX::XMFLOAT4   TexelWorldSize;
    DirectX::XMFLOAT4   Params;
};

class ShadowMap
{
public:
    static constexpr uint32_t CascadeCount = 4;
    static constexpr uint32_t Size = 2048;

    void Initialize(ID3D12Device* device, D3D12_CPU_DESCRIPTOR_HANDLE srvDest);
    void Shutdown();

    void TransitionToWrite(ID3D12GraphicsCommandList* cmdList);
    void TransitionToRead(ID3D12GraphicsCommandList* cmdList);

    void UpdateCascades(const DirectX::XMFLOAT4X4& view, float fovY, float aspect,
                        float camNear, float shadowFar, const DirectX::XMFLOAT3& lightDir);

    void SetSplitLambda(float lambda) { m_lambda = lambda; }
    float GetSplitLambda() const { return m_lambda; }

    void SetDebugParams(bool showCascades, bool usePcf);

    Frustum GetCascadeFrustum(uint32_t cascade) const { return Frustum::FromViewProj(m_lightViewProjCpu[cascade]); }

    const ShadowConstants& GetConstants() const { return m_constants; }
    D3D12_GPU_VIRTUAL_ADDRESS GetConstantsGpuAddress() const { return m_constantBuffer->GetGPUVirtualAddress(); }

    D3D12_CPU_DESCRIPTOR_HANDLE GetDsv(uint32_t cascade) const;
    ID3D12Resource* GetResource() const { return m_resource.Get(); }

    DXGI_FORMAT GetDsvFormat() const { return DXGI_FORMAT_D32_FLOAT; }
    DXGI_FORMAT GetSrvFormat() const { return DXGI_FORMAT_R32_FLOAT; }

private:
    Microsoft::WRL::ComPtr<ID3D12Resource> m_resource;
    Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> m_dsvHeap;
    uint32_t m_dsvDescriptorSize = 0;

    ShadowConstants m_constants{};
    DirectX::XMFLOAT4X4 m_lightViewProjCpu[CascadeCount]{};
    float m_lambda = 0.75f;
    Microsoft::WRL::ComPtr<ID3D12Resource> m_constantBuffer;
    uint8_t* m_mappedConstants = nullptr;
};
