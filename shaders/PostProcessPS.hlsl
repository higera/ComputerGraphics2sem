cbuffer PostCB : register(b0)
{
    float4 gRTSize;
    float4 gVignette;
    float4 gChroma;
    float4 gFlags;
    float4 gToneParams;
    float4 gDepthParams;
};

Texture2D gAlbedoSpecTex : register(t0);
Texture2D gNormalTex     : register(t1);
Texture2D gDepthTex      : register(t2);
Texture2D gSceneColor    : register(t3);

SamplerState gLinearClamp : register(s0);

struct FSOut
{
    float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};

float3 ToneMapACES(float3 x)
{
    const float a = 2.51f, b = 0.03f, c = 2.43f, d = 0.59f, e = 0.14f;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

float LinearizeDepth(float ndcDepth)
{
    float n = gDepthParams.x, f = gDepthParams.y;
    return n * f / (f - ndcDepth * (f - n));
}

float4 PostProcessPS(FSOut pin) : SV_TARGET
{
    float2 uv = pin.TexC;
    int3 coords = int3((int2)pin.PosH.xy, 0);

    if (gFlags.w > 0.5f)
    {
        if (gFlags.w < 1.5f)
            return float4(gAlbedoSpecTex.Load(coords).rgb, 1.f);
        if (gFlags.w < 2.5f)
            return float4(normalize(gNormalTex.Load(coords).xyz) * 0.5f + 0.5f, 1.f);
        float ndc = gDepthTex.Load(coords).r;
        if (ndc >= 1.f)
            return float4(1.f, 1.f, 1.f, 1.f);
        return float4(saturate(LinearizeDepth(ndc) / gDepthParams.z).xxx, 1.f);
    }

    float3 color;
    if (gFlags.y > 0.5f)
    {
        float2 off = (uv - 0.5f) * gChroma.x;
        color.r = gSceneColor.Sample(gLinearClamp, uv + off).r;
        color.g = gSceneColor.Sample(gLinearClamp, uv).g;
        color.b = gSceneColor.Sample(gLinearClamp, uv - off).b;
    }
    else
    {
        color = gSceneColor.Sample(gLinearClamp, uv).rgb;
    }

    if (gFlags.x > 0.5f)
    {
        float  aspect = gRTSize.x * gRTSize.w;
        float2 d2  = (uv - 0.5f) * float2(aspect, 1.f);
        float  d   = length(d2) / length(float2(0.5f * aspect, 0.5f));
        float  vig = smoothstep(gVignette.y, 1.f, d);
        color *= 1.f - vig * gVignette.x;
    }

    color *= gToneParams.x;
    color = (gFlags.z > 0.5f) ? ToneMapACES(color) : saturate(color);

    color = pow(color, 1.f / 2.2f);
    return float4(color, 1.f);
}
