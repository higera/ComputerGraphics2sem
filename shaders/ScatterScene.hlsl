cbuffer ViewCB : register(b0)
{
    float4x4 gViewProj;
    float4   gEyePosW;
    float4   gLightDir;
};

cbuffer InstanceCB : register(b1)
{
    float4x4 gWorld;
};

StructuredBuffer<float4x4> gInstanceWorlds : register(t1);

Texture2D    gDiffuseMap : register(t0);
SamplerState gSampler    : register(s0);

struct VSIn
{
    float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
    float2 TexC    : TEXCOORD;
};

struct VSOut
{
    float4 PosH    : SV_POSITION;
    float3 NormalW : NORMAL;
    float2 TexC    : TEXCOORD;
};

VSOut TransformVertex(VSIn vin, float4x4 world)
{
    VSOut vout;
    float4 posW  = mul(float4(vin.PosL, 1.0), world);
    vout.PosH    = mul(posW, gViewProj);
    vout.NormalW = normalize(mul(vin.NormalL, (float3x3)world));
    vout.TexC    = vin.TexC;
    return vout;
}

VSOut VS(VSIn vin)
{
    return TransformVertex(vin, gWorld);
}

VSOut VSInstanced(VSIn vin, uint instanceId : SV_InstanceID)
{
    return TransformVertex(vin, gInstanceWorlds[instanceId]);
}

float4 PS(VSOut pin) : SV_TARGET
{
    float3 albedo = gDiffuseMap.Sample(gSampler, pin.TexC).rgb;
    float3 N      = normalize(pin.NormalW);
    float3 L      = normalize(-gLightDir.xyz);
    float  ndotl  = saturate(dot(N, L));
    float3 color  = albedo * (0.3 + 0.7 * ndotl);
    return float4(color, 1.0);
}
