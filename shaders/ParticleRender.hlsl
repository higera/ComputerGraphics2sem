cbuffer PassCB : register(b0)
{
    float4x4 gWorld;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float4   gEyePosW;
    float4   gRTSize;
};

struct VSIn
{
    float3 Position : POSITION;
    float  Size     : SIZE;
    float3 Velocity : VELOCITY;
    float  Lifetime : LIFETIME;
};

struct VSOut
{
    float3 Position : POSITION;
    float  Size     : SIZE;
    float  Lifetime : LIFETIME;
};

struct GSOut
{
    float4 PosH  : SV_POSITION;
    float2 UV    : TEXCOORD;
    float3 Color : COLOR;
};

VSOut ParticleVS(VSIn vin)
{
    VSOut vout;
    vout.Position = vin.Position;
    vout.Size     = vin.Size;
    vout.Lifetime = vin.Lifetime;
    return vout;
}

[maxvertexcount(4)]
void ParticleGS(point VSOut input[1], inout TriangleStream<GSOut> stream)
{
    const VSOut p = input[0];

    float3 toEye = normalize(gEyePosW.xyz - p.Position);
    float3 right = cross(toEye, float3(0.0f, 1.0f, 0.0f));
    right = (dot(right, right) < 1e-6f) ? float3(1.0f, 0.0f, 0.0f) : normalize(right);
    float3 up = cross(right, toEye);

    float  heat  = saturate(p.Lifetime / 4.0f);
    float3 color = lerp(float3(0.55f, 0.06f, 0.0f), float3(1.0f, 0.78f, 0.25f), heat);

    const float  h = p.Size * 0.5f;
    const float2 corners[4] = { float2(-1, -1), float2(-1, 1), float2(1, -1), float2(1, 1) };

    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float3 worldPos = p.Position + (right * corners[i].x + up * corners[i].y) * h;

        GSOut v;
        v.PosH  = mul(float4(worldPos, 1.0f), gViewProj);
        v.UV    = corners[i];
        v.Color = color;
        stream.Append(v);
    }
}

float4 ParticlePS(GSOut pin) : SV_Target
{
    float r2 = dot(pin.UV, pin.UV);
    clip(1.0f - r2);

    float shade = 1.0f - 0.35f * r2;
    return float4(pin.Color * shade, 1.0f);
}
