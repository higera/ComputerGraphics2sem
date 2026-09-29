#include "Particle.hlsli"

#define MAX_PARTICLES 65536

ConsumeStructuredBuffer<Particle> gConsume : register(u0);
AppendStructuredBuffer<Particle>  gAppend  : register(u1);

cbuffer SimCB : register(b0)
{
    float  gDt;
    uint   gEmitCount;
    uint   gSeed;
    float  gFloorY;
    float3 gEmitterPos;
    float  gEmitSpeed;
    float3 gGravity;
    float  gRestitution;
};

cbuffer CountCB : register(b1)
{
    uint gAliveCount;
};

uint Hash(uint v)
{
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float Random01(inout uint state)
{
    state = Hash(state);
    return (state & 0x00FFFFFFu) / 16777216.0f;
}

[numthreads(64, 1, 1)]
void SimulateCS(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= gAliveCount)
        return;

    Particle p = gConsume.Consume();

    p.Lifetime -= gDt;
    if (p.Lifetime <= 0.0f)
        return;

    p.Velocity += gGravity * gDt;
    p.Position += p.Velocity * gDt;

    if (p.Position.y < gFloorY)
    {
        p.Position.y = gFloorY;
        p.Velocity.y = -p.Velocity.y * gRestitution;
        p.Velocity.xz *= 0.7f;
    }

    gAppend.Append(p);
}

[numthreads(64, 1, 1)]
void EmitCS(uint3 id : SV_DispatchThreadID)
{
    uint room = MAX_PARTICLES - gAliveCount;
    if (id.x >= min(gEmitCount, room))
        return;

    uint rng = Hash(id.x + gSeed * 9781u);

    float azimuth = Random01(rng) * 6.2831853f;
    float tilt    = Random01(rng) * 0.45f;
    float3 dir = float3(sin(tilt) * cos(azimuth), cos(tilt), sin(tilt) * sin(azimuth));

    Particle p;
    p.Position = gEmitterPos + float3(Random01(rng) - 0.5f, 0.0f, Random01(rng) - 0.5f) * 0.1f;
    p.Velocity = dir * gEmitSpeed * (0.6f + 0.4f * Random01(rng));
    p.Size     = 0.03f + 0.04f * Random01(rng);
    p.Lifetime = 2.5f + 2.0f * Random01(rng);
    gAppend.Append(p);
}
