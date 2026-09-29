cbuffer PassCB : register(b0)
{
    float4x4 gWorld;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float4   gEyePosW;
    float4   gRTSize;
};

cbuffer MaterialCB : register(b2)
{
    float4 gBaseColor;
    float4 gSurfaceParams;
};

Texture2D    gDiffuseMap : register(t0);
SamplerState gSampler    : register(s0);

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

static const float kAlphaCutoff = 0.5f;

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

cbuffer CascadeCB : register(b4)
{
    float4x4 gCascadeViewProj;
};

struct ShadowVSOut
{
    float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};

ShadowVSOut ShadowVS(VSIn vin)
{
    ShadowVSOut vout;
    float4 posW = mul(float4(vin.PosL, 1.f), gWorld);
    vout.PosH = mul(posW, gCascadeViewProj);
    vout.TexC = vin.TexC;
    return vout;
}

void ShadowAlphaPS(ShadowVSOut pin)
{
    clip(gDiffuseMap.Sample(gSampler, pin.TexC).a - kAlphaCutoff);
}

struct GBufferOut
{
    float4 AlbedoSpec : SV_Target0;
    float4 Normal     : SV_Target1;
    float  Depth      : SV_Target2;
};

GBufferOut GeometryPS(GeoVSOut pin)
{
    GBufferOut gout;

    float4 texColor = gDiffuseMap.Sample(gSampler, pin.TexC);
    if (gSurfaceParams.z > 0.5f)
        clip(texColor.a - kAlphaCutoff);

    float3 albedo  = texColor.rgb * gBaseColor.rgb;
    float  specInt = gSurfaceParams.x;
    float  shiny   = gSurfaceParams.y;

    gout.AlbedoSpec = float4(albedo, specInt);
    gout.Normal     = float4(normalize(pin.NormalW), shiny);
    gout.Depth      = pin.PosH.z;
    return gout;
}

struct GpuLight
{
    float4 PositionRange;
    float4 DirectionSpot;
    float4 ColorIntensity;
    float4 Params;
};

#define MAX_LIGHTS 32

cbuffer LightCB : register(b1)
{
    float4   gAmbientColor;
    float4   gLightCount;
    GpuLight gLights[MAX_LIGHTS];
};

Texture2D gAlbedoSpecTex : register(t1);
Texture2D gNormalTex     : register(t2);
Texture2D gDepthTex      : register(t3);

#define CASCADE_COUNT   4
#define SHADOW_MAP_SIZE 2048.0

cbuffer ShadowCB : register(b3)
{
    float4x4 gLightViewProj[CASCADE_COUNT];
    float4   gCascadeSplits;
    float4   gTexelWorld;
    float4   gShadowParams;
};

Texture2DArray<float>  gShadowMap     : register(t4);
SamplerComparisonState gShadowSampler : register(s1);

int GetCascadeIndex(float viewZ)
{
    int c = 0;
    [unroll]
    for (int i = 0; i < CASCADE_COUNT; ++i)
        if (viewZ > gCascadeSplits[i]) c = i + 1;
    return c;
}

float SampleCascade(int c, float3 posW, float3 N, float3 L)
{
    float texelWorld = gTexelWorld[c];
    float NdotL      = saturate(dot(N, L));
    float tanTheta   = min(sqrt(1.f - NdotL * NdotL) / max(NdotL, 0.05f), 3.f);

    float normalOffset = texelWorld * 1.5f;
    float slopeBias    = texelWorld * (1.f + 1.5f * tanTheta);
    float3 biasedPos   = posW + N * normalOffset + L * slopeBias;

    float4 lightPos = mul(float4(biasedPos, 1.f), gLightViewProj[c]);
    float2 uv       = lightPos.xy * float2(0.5f, -0.5f) + 0.5f;
    float  depth    = lightPos.z;

    if (gShadowParams.y < 0.5f)
    {
        if (any(uv < 0.f) || any(uv > 1.f))
            return 1.f;
        int2  texel  = (int2)(uv * SHADOW_MAP_SIZE);
        float stored = gShadowMap.Load(int4(texel, c, 0));
        return depth <= stored ? 1.f : 0.f;
    }

    const float texelUV = 1.f / SHADOW_MAP_SIZE;
    float lit = 0.f;
    [unroll]
    for (int y = -1; y <= 1; ++y)
    {
        [unroll]
        for (int x = -1; x <= 1; ++x)
        {
            float2 offset = float2(x, y) * texelUV;
            lit += gShadowMap.SampleCmpLevelZero(gShadowSampler, float3(uv + offset, c), depth);
        }
    }
    return lit / 9.f;
}

float ShadowFactor(float3 posW, float3 N, float3 L, float viewZ)
{
    int c = GetCascadeIndex(viewZ);
    if (c >= CASCADE_COUNT)
        return 1.f;

    float lit = SampleCascade(c, posW, N, L);

    float splitStart = (c == 0) ? 0.f : gCascadeSplits[c - 1];
    float splitEnd   = gCascadeSplits[c];
    float band       = max((splitEnd - splitStart) * gShadowParams.z, 1e-3f);
    float t          = saturate((splitEnd - viewZ) / band);
    if (t < 1.f)
    {
        float next = (c + 1 < CASCADE_COUNT) ? SampleCascade(c + 1, posW, N, L) : 1.f;
        lit = lerp(next, lit, t);
    }
    return lit;
}

struct QuadVSOut
{
    float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};

QuadVSOut LightingVS(uint id : SV_VertexID)
{
    QuadVSOut vout;
    vout.TexC = float2((id << 1) & 2, id & 2);
    vout.PosH = float4(vout.TexC * float2(2.f, -2.f) + float2(-1.f, 1.f), 0.f, 1.f);
    return vout;
}

float3 ReconstructWorldPos(float2 uv, float ndcDepth, out float viewZ)
{
    float4 clipPos  = float4(uv * float2(2.f, -2.f) + float2(-1.f, 1.f), ndcDepth, 1.f);
    float4 worldPos = mul(clipPos, gInvViewProj);
    viewZ = 1.f / worldPos.w;
    return worldPos.xyz / worldPos.w;
}

float4 LightingPS(QuadVSOut pin) : SV_TARGET
{
    int3 coords = int3((int2)pin.PosH.xy, 0);

    float4 albedoSpec = gAlbedoSpecTex.Load(coords);
    float3 albedo  = pow(albedoSpec.rgb, 2.2f);
    float  specInt = albedoSpec.a;

    float4 normalSample = gNormalTex.Load(coords);
    float3 N = normalize(normalSample.xyz);
    float  shininess = max(normalSample.a, 1.f);

    float ndcDepth = gDepthTex.Load(coords).r;

    if (ndcDepth >= 1.f)
        return float4(0.f, 0.f, 0.f, 1.f);

    float2 uv = pin.PosH.xy * gRTSize.zw;
    float  viewZ;
    float3 posW = ReconstructWorldPos(uv, ndcDepth, viewZ);
    float3 V    = normalize(gEyePosW.xyz - posW);

    float3 finalColor = gAmbientColor.rgb * albedo;

    int lightCount = (int)gLightCount.x;
    for (int i = 0; i < lightCount; ++i)
    {
        GpuLight light = gLights[i];
        float  type       = light.Params.x;
        float3 lightColor = light.ColorIntensity.rgb;
        float  intensity  = light.ColorIntensity.a;
        float3 L;
        float  attenuation = 1.f;

        if (type < 0.5f)
        {
            L = normalize(-light.DirectionSpot.xyz);
            if (light.Params.z > 0.5f)
                attenuation = ShadowFactor(posW, N, L, viewZ);
        }
        else if (type < 1.5f)
        {
            float3 toLight = light.PositionRange.xyz - posW;
            float  dist  = length(toLight);
            float  range = light.PositionRange.w;
            if (dist >= range) continue;
            L = toLight / dist;
            float t = dist / range;
            attenuation = saturate(1.f - t * t);
        }
        else
        {
            float3 toLight = light.PositionRange.xyz - posW;
            float  dist  = length(toLight);
            float  range = light.PositionRange.w;
            if (dist >= range) continue;
            L = toLight / dist;

            float cosOuter = light.DirectionSpot.w;
            float cosInner = light.Params.y;
            float cosAngle = dot(-L, normalize(light.DirectionSpot.xyz));
            if (cosAngle <= cosOuter) continue;

            float denom      = max(cosInner - cosOuter, 1e-4f);
            float spotFactor = saturate((cosAngle - cosOuter) / denom);
            float t = dist / range;
            attenuation = saturate(1.f - t * t) * spotFactor;
        }

        float  NdotL = max(dot(N, L), 0.f);
        float3 H     = normalize(L + V);
        float  NdotH = max(dot(N, H), 0.f);
        float  spec  = specInt * pow(NdotH, shininess) * (NdotL > 0.f ? 1.f : 0.f);

        finalColor += (albedo * NdotL + spec) * lightColor * intensity * attenuation;
    }

    if (gShadowParams.x > 0.5f)
    {
        static const float3 kCascadeColors[CASCADE_COUNT + 1] =
        {
            float3(1.0f, 0.4f, 0.4f),
            float3(0.4f, 1.0f, 0.4f),
            float3(0.4f, 0.5f, 1.0f),
            float3(1.0f, 1.0f, 0.4f),
            float3(1.0f, 1.0f, 1.0f)
        };
        finalColor *= kCascadeColors[GetCascadeIndex(viewZ)];
    }

    return float4(pow(saturate(finalColor), 1.f / 2.2f), 1.f);
}
