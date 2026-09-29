#pragma once
#include "Frustum.h"
#include <vector>
#include <cstdint>

class Octree
{
public:
    struct Node
    {
        AABB Bounds;
        std::vector<uint32_t> Objects;
        int Children[8] = { -1,-1,-1,-1,-1,-1,-1,-1 };

        bool IsLeaf() const
        {
            for (int c : Children) if (c != -1) return false;
            return true;
        }
    };

    void Build(const std::vector<AABB>& worldBounds,
               const AABB& sceneBounds,
               int maxDepth = 6,
               int minPerLeaf = 8);

    uint32_t QueryVisible(const Frustum& frustum, std::vector<uint32_t>& out) const;

    size_t NodeCount() const { return m_nodes.size(); }
    size_t ObjectCount() const { return m_objectBounds.size(); }

private:
    void Subdivide(int idx, const std::vector<AABB>& bounds,
                   int depth, int maxDepth, int minPerLeaf);
    void QueryNode(int idx, const Frustum& f, std::vector<uint32_t>& out, uint32_t& tests) const;

    std::vector<Node> m_nodes;
    std::vector<AABB> m_objectBounds;
};