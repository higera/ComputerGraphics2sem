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

Texture2D    gDiffuseMap    : register(t0);
Texture2D    gNormalMap     : register(t9);
Texture2D    gMetalRoughMap : register(t10);
SamplerState gSampler : register(s0);

static const float kAlphaCutoff = 0.5f;

#define NORMAL_MAP_FLIP_Y 0

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
    float4 Material   : SV_Target3;
};

float3x3 CotangentFrame(float3 N, float3 posW, float2 uv)
{
    float3 dp1  = ddx(posW);
    float3 dp2  = ddy(posW);
    float2 duv1 = ddx(uv);
    float2 duv2 = ddy(uv);

    float3 dp2perp = cross(dp2, N);
    float3 dp1perp = cross(N, dp1);
    float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    float invMax = rsqrt(max(max(dot(T, T), dot(B, B)), 1e-20f));
    return float3x3(T * invMax, B * invMax, N);
}

GBufferOut GeometryPS(GeoVSOut pin)
{
    GBufferOut gout;

    float4 texColor = gDiffuseMap.Sample(gSampler, pin.TexC);
    if (gSurfaceParams.w > 0.5f)
        clip(texColor.a - kAlphaCutoff);

    float3 albedo = texColor.rgb * gBaseColor.rgb;

    float3 N  = normalize(pin.NormalW);
    float3 tn = gNormalMap.Sample(gSampler, pin.TexC).xyz * 2.f - 1.f;
#if NORMAL_MAP_FLIP_Y
    tn.y = -tn.y;
#endif
    N = normalize(mul(normalize(tn), CotangentFrame(N, pin.PosW, pin.TexC)));

    float3 mr        = gMetalRoughMap.Sample(gSampler, pin.TexC).rgb;
    float  metallic  = saturate(gSurfaceParams.x * mr.r);
    float  roughness = saturate(gSurfaceParams.y * mr.g);

    gout.AlbedoSpec = float4(albedo, 1.f);
    gout.Normal     = float4(N, 0.f);
    gout.Depth      = pin.PosH.z;
    gout.Material   = float4(metallic, roughness, gSurfaceParams.z, 1.f);
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
    float4   gPbrDebug;
    float4   gLightCount;
    GpuLight gLights[MAX_LIGHTS];
};

Texture2D gAlbedoSpecTex : register(t1);
Texture2D gNormalTex     : register(t2);
Texture2D gDepthTex      : register(t3);
Texture2D gMaterialTex   : register(t4);

#define CASCADE_COUNT   4
#define SHADOW_MAP_SIZE 2048.0

cbuffer ShadowCB : register(b3)
{
    float4x4 gLightViewProj[CASCADE_COUNT];
    float4   gCascadeSplits;
    float4   gTexelWorld;
    float4   gShadowParams;
};

Texture2DArray<float>  gShadowMap     : register(t5);
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

TextureCube irradianceMap : register(t6);
TextureCube prefilterMap  : register(t7);
Texture2D   brdfLUT       : register(t8);

SamplerState irradianceMapSampler : register(s2);
SamplerState brdfLUTSampler       : register(s3);
#define prefilterMapSampler irradianceMapSampler

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

static const float PI = 3.14159265359f;

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a      = roughness * roughness;
    float a2     = a * a;
    float NdotH  = max(dot(N, H), 0.f);
    float NdotH2 = NdotH * NdotH;

    float denom = NdotH2 * (a2 - 1.f) + 1.f;
    return a2 / (PI * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float k)
{
    return NdotV / (NdotV * (1.f - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float k = (roughness + 1.f) * (roughness + 1.f) / 8.f;
    float NdotV = max(dot(N, V), 0.f);
    float NdotL = max(dot(N, L), 0.f);
    return GeometrySchlickGGX(NdotV, k) * GeometrySchlickGGX(NdotL, k);
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.f - F0) * pow(clamp(1.f - cosTheta, 0.f, 1.f), 5.f);
}

float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
    return F0 + (max((1.f - roughness).xxx, F0) - F0) * pow(clamp(1.f - cosTheta, 0.f, 1.f), 5.f);
}

float4 LightingPS(QuadVSOut pin) : SV_TARGET
{
    int3 coords = int3((int2)pin.PosH.xy, 0);

    float2 uv       = pin.PosH.xy * gRTSize.zw;
    float  ndcDepth = gDepthTex.Load(coords).r;

    if (ndcDepth >= 1.f)
    {
        float  unusedZ;
        float3 farPos = ReconstructWorldPos(uv, 1.f, unusedZ);
        float3 dir    = normalize(farPos - gEyePosW.xyz);
        return float4(prefilterMap.SampleLevel(prefilterMapSampler, dir, 0.f).rgb, 1.f);
    }

    float3 albedo = pow(gAlbedoSpecTex.Load(coords).rgb, 2.2f);
    float3 N      = normalize(gNormalTex.Load(coords).xyz);

    float3 material  = gMaterialTex.Load(coords).rgb;
    float  metallic  = material.r;
    float  roughness = material.g;
    float  ao        = material.b;

    if (gPbrDebug.x > 2.5f)      { metallic = 0.f; roughness = 0.1f; }
    else if (gPbrDebug.x > 1.5f) { metallic = 0.f; roughness = 1.f; }
    else if (gPbrDebug.x > 0.5f) { metallic = 1.f; roughness = 0.15f; }
    roughness = clamp(roughness, 0.05f, 1.f);

    float  viewZ;
    float3 posW = ReconstructWorldPos(uv, ndcDepth, viewZ);
    float3 V    = normalize(gEyePosW.xyz - posW);
    float  NdotV = max(dot(N, V), 0.f);

    float3 F0 = lerp(float3(0.04f, 0.04f, 0.04f), albedo, metallic);

    float3 Lo = float3(0.f, 0.f, 0.f);

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

        float3 radiance = lightColor * intensity * attenuation;

        float3 H     = normalize(V + L);
        float  NdotL = max(dot(N, L), 0.f);

        float  D = DistributionGGX(N, H, roughness);
        float  G = GeometrySmith(N, V, L, roughness);
        float3 F = FresnelSchlick(max(dot(H, V), 0.f), F0);

        float3 specular = (D * G * F) / (4.f * NdotV * NdotL + 0.0001f);

        float3 kS = F;
        float3 kD = (1.f - kS) * (1.f - metallic);

        Lo += (kD * albedo / PI + specular) * radiance * NdotL;
    }

    float3 R = reflect(-V, N);

    float3 F  = FresnelSchlickRoughness(NdotV, F0, roughness);
    float3 kS = F;
    float3 kD = (1.f - kS) * (1.f - metallic);

    float3 irradiance = irradianceMap.Sample(irradianceMapSampler, N).rgb;
    float3 diffuse    = irradiance * albedo;

    uint envW, envH, envLevels;
    prefilterMap.GetDimensions(0, envW, envH, envLevels);
    float MAX_REFLECTION_LOD = (float)(envLevels - 1);

    float3 prefilteredColor = prefilterMap.SampleLevel(prefilterMapSampler, R, roughness * MAX_REFLECTION_LOD).rgb;
    float2 brdf             = brdfLUT.Sample(brdfLUTSampler, float2(NdotV, roughness)).rg;
    float3 specularIbl      = prefilteredColor * (F * brdf.x + brdf.y);

    float3 ambient = (kD * diffuse + specularIbl) * ao;

    float3 finalColor = Lo * gPbrDebug.z + ambient * gPbrDebug.y;

    if (gShadowParams.x > 0.5f)
    {
        static const float3 kCascadeColors[CASCADE_COUNT + 1] =
        {
            float3(1.0f, 0.4f, 0.4f), float3(0.4f, 1.0f, 0.4f), float3(0.4f, 0.5f, 1.0f),
            float3(1.0f, 1.0f, 0.4f), float3(1.0f, 1.0f, 1.0f)
        };
        finalColor *= kCascadeColors[GetCascadeIndex(viewZ)];
    }

    return float4(finalColor, 1.f);
}
