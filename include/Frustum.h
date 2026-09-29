#pragma once
#include <DirectXMath.h>
#include "AABB.h"

struct Plane
{
    DirectX::XMFLOAT4 P;
};

struct Frustum
{
    Plane Planes[6];

    static Frustum FromViewProj(const DirectX::XMFLOAT4X4& viewProj);

    bool Intersects(const AABB& aabb, bool skipNear = false) const;
};