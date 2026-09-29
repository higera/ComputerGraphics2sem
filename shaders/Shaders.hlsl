cbuffer PassCB : register(b0)
{
    float4x4 gWorld;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float4   gEyePosW;
    float4   gRTSize;
};

cbuffer LightPassCB : register(b1)
{
    float4 gAmbientColor;
    uint   gLightOffset;
    uint3  gLightPassPad;
};

cbuffer MaterialCB : register(b2)
{
    float4 gBaseColor;
    float4 gSurfaceParams;
};

Texture2D    gDiffuseMap : register(t0);
SamplerState gSampler    : register(s0);

Texture2D gAlbedoSpecTex : register(t1);
Texture2D gNormalTex     : register(t2);
Texture2D gDepthTex      : register(t3);

#define LIGHT_DIRECTIONAL 0
#define LIGHT_POINT       1
#define LIGHT_SPOT        2

struct GpuLight
{
    float4 PositionRange;
    float4 DirectionSpot;
    float4 ColorIntensity;
    float4 Params;
};

StructuredBuffer<GpuLight> gLights : register(t4);

struct VSIn
{
    float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
    float2 TexC    : TEXCOORD;
};

struct GeoVSOut
{
    float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
    float2 TexC    : TEXCOORD;
};

GeoVSOut GeometryVS(VSIn vin)
{
    GeoVSOut vout;
    float4 posW  = mul(float4(vin.PosL, 1.f), gWorld);
    vout.PosW    = posW.xyz;
    vout.NormalW = mul(vin.NormalL, (float3x3)gWorld);
    vout.PosH    = mul(posW, gViewProj);
    vout.TexC    = vin.TexC;
    return vout;
}

struct GBufferOut
{
    float4 AlbedoSpec : SV_Target0;
    float4 Normal     : SV_Target1;
};

GBufferOut GeometryPS(GeoVSOut pin)
{
    GBufferOut gout;

    float4 texColor = gDiffuseMap.Sample(gSampler, pin.TexC);

    if (gSurfaceParams.z > 0.5f)
        clip(texColor.a - 0.5f);

    float3 albedo = texColor.rgb * gBaseColor.rgb;

    float3 N  = normalize(pin.NormalW);
    float3 V  = gEyePosW.xyz - pin.PosW;
    float3 Ng = cross(ddx(pin.PosW), ddy(pin.PosW));
    if (dot(Ng, V) < 0.f) Ng = -Ng;
    if (dot(N, Ng) < 0.f) N = -N;

    gout.AlbedoSpec = float4(albedo, gSurfaceParams.x);
    gout.Normal     = float4(N, gSurfaceParams.y);
    return gout;
}

struct Surface
{
    float3 PosW;
    float3 N;
    float3 Albedo;
    float  SpecInt;
    float  Shininess;
};

float3 ReconstructWorldPos(float2 pixel, float ndcDepth)
{
    float2 uv = pixel * gRTSize.zw;
    float4 clipPos = float4(uv * float2(2.f, -2.f) + float2(-1.f, 1.f), ndcDepth, 1.f);
    float4 worldPos = mul(clipPos, gInvViewProj);
    return worldPos.xyz / worldPos.w;
}

bool LoadSurface(float4 svPosition, out Surface s)
{
    int3 coords = int3((int2)svPosition.xy, 0);

    float depth = gDepthTex.Load(coords).r;

    float4 albedoSpec = gAlbedoSpecTex.Load(coords);
    float4 normalShin = gNormalTex.Load(coords);

    s.Albedo    = albedoSpec.rgb;
    s.SpecInt   = albedoSpec.a;
    s.N         = normalize(normalShin.xyz);
    s.Shininess = max(normalShin.w, 1.f);
    s.PosW      = ReconstructWorldPos(svPosition.xy, depth);

    return depth < 1.f;
}

float3 EvaluateLight(GpuLight light, Surface s)
{
    float3 L;
    float  attenuation = 1.f;
    int    type = (int)light.Params.x;

    if (type == LIGHT_DIRECTIONAL)
    {
        L = normalize(-light.DirectionSpot.xyz);
    }
    else
    {
        float3 toLight = light.PositionRange.xyz - s.PosW;
        float  dist    = length(toLight);
        float  range   = light.PositionRange.w;
        if (dist >= range)
            return float3(0.f, 0.f, 0.f);

        L = toLight / dist;
        float t = dist / range;
        attenuation = saturate(1.f - t * t);
        attenuation *= attenuation;

        if (type == LIGHT_SPOT)
        {
            float cosOuter = light.DirectionSpot.w;
            float cosInner = light.Params.y;
            float cosAngle = dot(-L, normalize(light.DirectionSpot.xyz));
            attenuation *= smoothstep(cosOuter, max(cosInner, cosOuter + 1e-4f), cosAngle);
        }
    }

    float3 V = normalize(gEyePosW.xyz - s.PosW);
    float3 H = normalize(L + V);
    float  NdotL = saturate(dot(s.N, L));
    float  spec  = s.SpecInt * pow(saturate(dot(s.N, H)), s.Shininess) * (NdotL > 0.f);

    return (s.Albedo * NdotL + spec) * light.ColorIntensity.rgb * light.ColorIntensity.a * attenuation;
}

struct FullscreenVSOut
{
    float4 PosH : SV_POSITION;
    nointerpolation uint LightIndex : LIGHTINDEX;
};

FullscreenVSOut FullscreenVS(uint id : SV_VertexID, uint instance : SV_InstanceID)
{
    FullscreenVSOut vout;
    float2 uv = float2((id << 1) & 2, id & 2);
    vout.PosH = float4(uv * float2(2.f, -2.f) + float2(-1.f, 1.f), 0.f, 1.f);
    vout.LightIndex = gLightOffset + instance;
    return vout;
}

float4 AmbientPS(FullscreenVSOut pin) : SV_TARGET
{
    Surface s;
    if (!LoadSurface(pin.PosH, s))
        return float4(0.f, 0.f, 0.f, 1.f);
    return float4(gAmbientColor.rgb * s.Albedo, 1.f);
}

float4 DirectionalPS(FullscreenVSOut pin) : SV_TARGET
{
    Surface s;
    if (!LoadSurface(pin.PosH, s))
        discard;
    return float4(EvaluateLight(gLights[pin.LightIndex], s), 1.f);
}

struct VolumeVSOut
{
    float4 PosH : SV_POSITION;
    nointerpolation uint LightIndex : LIGHTINDEX;
};

VolumeVSOut LightVolumeVS(float3 PosL : POSITION, uint instance : SV_InstanceID)
{
    VolumeVSOut vout;
    vout.LightIndex = gLightOffset + instance;

    GpuLight light = gLights[vout.LightIndex];
    float3 center = light.PositionRange.xyz;
    float  range  = light.PositionRange.w;

    float3 posW;
    if ((int)light.Params.x == LIGHT_SPOT)
    {
        float3 fwd   = normalize(light.DirectionSpot.xyz);
        float3 up    = abs(fwd.y) < 0.99f ? float3(0.f, 1.f, 0.f) : float3(1.f, 0.f, 0.f);
        float3 right = normalize(cross(up, fwd));
        up = cross(fwd, right);

        float cosOuter = light.DirectionSpot.w;
        float radius   = range * sqrt(saturate(1.f - cosOuter * cosOuter)) / cosOuter;

        posW = center + right * (PosL.x * radius) + up * (PosL.y * radius) + fwd * (PosL.z * range);
    }
    else
    {
        posW = center + PosL * range;
    }

    vout.PosH = mul(float4(posW, 1.f), gViewProj);
    return vout;
}

float4 LightVolumePS(VolumeVSOut pin) : SV_TARGET
{
    Surface s;
    if (!LoadSurface(pin.PosH, s))
        discard;
    return float4(EvaluateLight(gLights[pin.LightIndex], s), 1.f);
}
