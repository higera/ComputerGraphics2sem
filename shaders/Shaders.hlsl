cbuffer PassCB : register(b0)
{
    float4x4 gWorld;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float4   gEyePosW;
    float4   gRTSize;
    float4   gTessParams;
    float4   gDispParams;
};

cbuffer MaterialCB : register(b2)
{
    float4 gBaseColor;
    float4 gSurfaceParams;
};

Texture2D    gDiffuseMap : register(t0);
Texture2D    gNormalMap  : register(t4);
Texture2D    gDispMap    : register(t5);
SamplerState gSampler    : register(s0);

struct VSIn
{
    float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
    float2 TexC    : TEXCOORD;
};

struct VSOut
{
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
    float2 TexC    : TEXCOORD;
};

struct GeoVSOut
{
    float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
    float2 TexC    : TEXCOORD;
};

VSOut GeometryVS(VSIn vin)
{
    VSOut vout;
    vout.PosW    = mul(float4(vin.PosL, 1.f), gWorld).xyz;
    vout.NormalW = mul(vin.NormalL, (float3x3)gWorld);
    vout.TexC    = vin.TexC;
    return vout;
}

float CalcTessFactor(float3 posW)
{
    float d = distance(posW, gEyePosW.xyz);
    float s = saturate((gTessParams.y - d) / max(gTessParams.y - gTessParams.x, 1e-4f));
    return lerp(gTessParams.z, gTessParams.w, s);
}

struct PatchTess
{
    float EdgeTess[3] : SV_TessFactor;
    float InsideTess  : SV_InsideTessFactor;
};

PatchTess PatchConstantHS(InputPatch<VSOut, 3> patch)
{
    PatchTess pt;

    pt.EdgeTess[0] = CalcTessFactor(0.5f * (patch[1].PosW + patch[2].PosW));
    pt.EdgeTess[1] = CalcTessFactor(0.5f * (patch[2].PosW + patch[0].PosW));
    pt.EdgeTess[2] = CalcTessFactor(0.5f * (patch[0].PosW + patch[1].PosW));

    pt.InsideTess = (pt.EdgeTess[0] + pt.EdgeTess[1] + pt.EdgeTess[2]) / 3.f;
    return pt;
}

[domain("tri")]
[partitioning("fractional_odd")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("PatchConstantHS")]
[maxtessfactor(64.0f)]
VSOut GeometryHS(InputPatch<VSOut, 3> patch, uint i : SV_OutputControlPointID)
{
    return patch[i];
}

[domain("tri")]
GeoVSOut GeometryDS(PatchTess patchTess, float3 bary : SV_DomainLocation, const OutputPatch<VSOut, 3> tri)
{
    GeoVSOut dout;

    float3 posW    = bary.x * tri[0].PosW    + bary.y * tri[1].PosW    + bary.z * tri[2].PosW;
    float3 normalW = normalize(bary.x * tri[0].NormalW + bary.y * tri[1].NormalW + bary.z * tri[2].NormalW);
    float2 uv      = bary.x * tri[0].TexC    + bary.y * tri[1].TexC    + bary.z * tri[2].TexC;

    float height = gDispMap.SampleLevel(gSampler, uv, 0.f).r;

    posW += normalW * ((height - gDispParams.y) * gDispParams.x);

    dout.PosW    = posW;
    dout.NormalW = normalW;
    dout.TexC    = uv;
    dout.PosH    = mul(float4(posW, 1.f), gViewProj);
    return dout;
}

struct GBufferOut
{
    float4 AlbedoSpec : SV_Target0;
    float4 Normal     : SV_Target1;
    float  Depth      : SV_Target2;
};

float3 ApplyNormalMap(float3 N, float3 posW, float2 uv)
{
    float3 nTS = gNormalMap.Sample(gSampler, uv).xyz * 2.f - 1.f;

    float3 dp1  = ddx(posW);
    float3 dp2  = ddy(posW);
    float2 duv1 = ddx(uv);
    float2 duv2 = ddy(uv);

    float3 dp2perp = cross(dp2, N);
    float3 dp1perp = cross(N, dp1);
    float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    float invMax = rsqrt(max(max(dot(T, T), dot(B, B)), 1e-20f));
    float3x3 TBN = float3x3(T * invMax, B * invMax, N);

    return normalize(mul(nTS, TBN));
}

GBufferOut GeometryPS(GeoVSOut pin)
{
    GBufferOut gout;

    float3 albedo  = gDiffuseMap.Sample(gSampler, pin.TexC).rgb * gBaseColor.rgb;
    float  specInt = gSurfaceParams.x;
    float  shiny   = gSurfaceParams.y;

    float3 N = normalize(pin.NormalW);
    if (gDispParams.z > 0.5f)
        N = ApplyNormalMap(N, pin.PosW, pin.TexC);

    gout.AlbedoSpec = float4(albedo, specInt);
    gout.Normal     = float4(N, shiny);
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

float3 ReconstructWorldPos(float2 uv, float ndcDepth)
{
    float4 clipPos  = float4(uv * float2(2.f, -2.f) + float2(-1.f, 1.f), ndcDepth, 1.f);
    float4 worldPos = mul(clipPos, gInvViewProj);
    return worldPos.xyz / worldPos.w;
}

float4 LightingPS(QuadVSOut pin) : SV_TARGET
{
    int3 coords = int3((int2)pin.PosH.xy, 0);

    float4 albedoSpec = gAlbedoSpecTex.Load(coords);
    float3 albedo  = albedoSpec.rgb;
    float  specInt = albedoSpec.a;

    float4 normalSample = gNormalTex.Load(coords);
    float3 N = normalize(normalSample.xyz);
    float  shininess = max(normalSample.a, 1.f);

    float ndcDepth = gDepthTex.Load(coords).r;

    if (ndcDepth >= 1.f)
        return float4(0.f, 0.f, 0.f, 1.f);

    float2 uv   = pin.PosH.xy * gRTSize.zw;
    float3 posW = ReconstructWorldPos(uv, ndcDepth);
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

    return float4(finalColor, 1.f);
}
