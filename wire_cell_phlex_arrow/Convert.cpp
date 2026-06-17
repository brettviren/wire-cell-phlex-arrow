#include "wire_cell_phlex_arrow/Convert.h"

#include "wire_cell_arrow/ArrowDepoSet.h"
#include "wire_cell_arrow/ArrowFrame.h"
#include "wire_cell_arrow/ArrowTensorSet.h"
#include "wire_cell_arrow/Converters.h"

#include <memory>
#include <stdexcept>
#include <string>

namespace {

// Look up a member table by reserved name; null if absent (companion tables
// may legitimately be missing — the facades treat null as empty).
std::shared_ptr<arrow::Table> member(const phlex_arrow::TableGroup& g, const std::string& name)
{
    auto it = g.members.find(name);
    return it == g.members.end() ? nullptr : it->second;
}

}  // namespace

namespace wire_cell_phlex_arrow {

// ---- write side ----

phlex_arrow::TableGroup to_table_group(const wcphlex::Frame& frame)
{
    auto res = WireCell::Arrow::to_arrow_sparse(frame.ptr);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(Frame): " + res.status().ToString());
    }
    const auto& ft = *res;
    return phlex_arrow::TableGroup{"wc.frame",
                                   {{"traces", ft.traces},
                                    {"frame_tags", ft.frame_tags},
                                    {"trace_tags", ft.trace_tags},
                                    {"cmm", ft.cmm}}};
}

phlex_arrow::TableGroup to_table_group(const wcphlex::DepoSet& deposet)
{
    auto res = WireCell::Arrow::to_arrow(deposet.ptr);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(DepoSet): " + res.status().ToString());
    }
    return phlex_arrow::TableGroup{"wc.deposet", {{"deposet", *res}}};
}

phlex_arrow::TableGroup to_table_group(const wcphlex::TensorSet& tensorset)
{
    auto res = WireCell::Arrow::to_arrow(tensorset.ptr);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(TensorSet): " + res.status().ToString());
    }
    return phlex_arrow::TableGroup{"wc.tensorset", {{"tensorset", *res}}};
}

// ---- read side ----

wcphlex::Frame frame_from_table_group(const phlex_arrow::TableGroup& group)
{
    WireCell::Arrow::FrameTables ft{member(group, "traces"),
                                    member(group, "frame_tags"),
                                    member(group, "trace_tags"),
                                    member(group, "cmm")};
    return wcphlex::Frame{std::make_shared<WireCell::Arrow::ArrowFrame>(std::move(ft))};
}

wcphlex::DepoSet deposet_from_table_group(const phlex_arrow::TableGroup& group)
{
    return wcphlex::DepoSet{
      std::make_shared<WireCell::Arrow::ArrowDepoSet>(member(group, "deposet"))};
}

wcphlex::TensorSet tensorset_from_table_group(const phlex_arrow::TableGroup& group)
{
    return wcphlex::TensorSet{
      std::make_shared<WireCell::Arrow::ArrowTensorSet>(member(group, "tensorset"))};
}

}  // namespace wire_cell_phlex_arrow
