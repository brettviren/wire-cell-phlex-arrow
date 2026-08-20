#include "wire_cell_phlex_arrow/Convert.hpp"

#include "wire_cell_arrow/ArrowDepoSet.hpp"
#include "wire_cell_arrow/ArrowFrame.hpp"
#include "wire_cell_arrow/ArrowTensorSet.hpp"
#include "wire_cell_arrow/ArrowTrackSegmentSet.hpp"
#include "wire_cell_arrow/Converters.hpp"

#include "edep_arrow/Schema.hpp"

#include <utility>
#include <vector>

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

phlex_arrow::TableGroup to_table_group(const wcphlex::TrackSegmentSet& segset)
{
    auto res = WireCell::Arrow::to_arrow(segset.ptr);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(TrackSegmentSet): " + res.status().ToString());
    }
    return phlex_arrow::TableGroup{"wc.tracksegmentset", {{"tracksegmentset", *res}}};
}

phlex_arrow::TableGroup to_table_group(const wcphlex::TensorSet& tensorset)
{
    auto res = WireCell::Arrow::to_arrow(tensorset.ptr);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(TensorSet): " + res.status().ToString());
    }
    return phlex_arrow::TableGroup{"wc.tensorset", {{"tensorset", *res}}};
}

phlex_arrow::TableGroup to_table_group(const wcphlex::BlobSets& blobs)
{
    auto res = WireCell::Arrow::to_arrow(blobs.items);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(BlobSets): " + res.status().ToString());
    }
    return phlex_arrow::TableGroup{"wc.blobs", {{"blobs", *res}}};
}

phlex_arrow::TableGroup to_table_group(const wcphlex::Cluster& cluster)
{
    auto res = WireCell::Arrow::to_arrow(cluster.ptr);
    if (!res.ok()) {
        throw std::runtime_error("to_table_group(Cluster): " + res.status().ToString());
    }
    return phlex_arrow::TableGroup{"wc.blobs", {{"blobs", *res}}};
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

wcphlex::TrackSegmentSet tracksegmentset_from_table_group(const phlex_arrow::TableGroup& group)
{
    return wcphlex::TrackSegmentSet{
      std::make_shared<WireCell::Arrow::ArrowTrackSegmentSet>(member(group, "tracksegmentset"))};
}

wcphlex::TrackSegmentSet tracksegmentset_from_observables(const phlex_arrow::TableGroup& group)
{
    auto table = member(group, edep_arrow::kSegmentsMember);
    if (!table) {
        throw std::runtime_error(
          "tracksegmentset_from_observables: TableGroup (type '" + group.type +
          "') lacks the '" + std::string(edep_arrow::kSegmentsMember) + "' member");
    }
    edep_arrow::require_readable(*table->schema(), edep_arrow::kSegmentsSchema,
                                 "tracksegmentset_from_observables");

    // edep.segments column -> wc.tracksegment column.  The edep names/semantics
    // are the edep-arrow schema contract; the wc names follow
    // WireCell::Arrow::tracksegment_schema().
    static const std::vector<std::pair<std::string, std::string>> mapping{
      {"start_x", "wc.tracksegment.start_x"},
      {"start_y", "wc.tracksegment.start_y"},
      {"start_z", "wc.tracksegment.start_z"},
      {"start_t", "wc.tracksegment.start_t"},
      {"stop_x", "wc.tracksegment.stop_x"},
      {"stop_y", "wc.tracksegment.stop_y"},
      {"stop_z", "wc.tracksegment.stop_z"},
      {"stop_t", "wc.tracksegment.stop_t"},
      {"energy_deposit", "wc.tracksegment.energy"},
      {"secondary_deposit", "wc.tracksegment.secondary"},
      {"n_electrons", "wc.tracksegment.n_electrons"},
      {"track_length", "wc.tracksegment.track_length"},
      {"primary_id", "wc.tracksegment.id"},
      {"pdg", "wc.tracksegment.pdg"},
    };

    // pdg is additive in edep.segments: absent in pre-v2 tables -> zeros.
    if (table->schema()->GetFieldIndex("pdg") < 0) {
        arrow::Int32Builder pdg_b;
        auto st = pdg_b.AppendEmptyValues(table->num_rows());
        std::shared_ptr<arrow::Array> zeros;
        if (st.ok()) st = pdg_b.Finish(&zeros);
        if (!st.ok()) {
            throw std::runtime_error("tracksegmentset_from_observables: pdg fill: " +
                                     st.ToString());
        }
        auto res = table->AddColumn(table->num_columns(),
                                    arrow::field("pdg", arrow::int32(), false),
                                    std::make_shared<arrow::ChunkedArray>(zeros));
        if (!res.ok()) {
            throw std::runtime_error("tracksegmentset_from_observables: pdg column: " +
                                     res.status().ToString());
        }
        table = *res;
    }

    // Project the needed columns (zero-copy) ...
    std::vector<int> indices;
    std::vector<std::string> names;
    for (const auto& [from, to] : mapping) {
        const int index = table->schema()->GetFieldIndex(from);
        if (index < 0) {
            throw std::runtime_error("tracksegmentset_from_observables: missing column '" +
                                     from + "'");
        }
        indices.push_back(index);
        names.push_back(to);
    }
    auto sel = table->SelectColumns(indices);
    if (!sel.ok()) {
        throw std::runtime_error("tracksegmentset_from_observables: SelectColumns: " +
                                 sel.status().ToString());
    }
    // ... rename to the wc.tracksegment.* names (shares the arrays) ...
    auto ren = (*sel)->RenameColumns(names);
    if (!ren.ok()) {
        throw std::runtime_error("tracksegmentset_from_observables: RenameColumns: " +
                                 ren.status().ToString());
    }
    // ... and re-stamp with the wc.tracksegmentset schema metadata.  The set
    // ident is not carried by edep.observables; 0 until an event ident is
    // plumbed through.
    auto stamped = (*ren)->ReplaceSchemaMetadata(
      WireCell::Arrow::tracksegmentset_schema(0)->metadata());

    return wcphlex::TrackSegmentSet{
      std::make_shared<WireCell::Arrow::ArrowTrackSegmentSet>(stamped)};
}

wcphlex::TensorSet tensorset_from_table_group(const phlex_arrow::TableGroup& group)
{
    return wcphlex::TensorSet{
      std::make_shared<WireCell::Arrow::ArrowTensorSet>(member(group, "tensorset"))};
}

}  // namespace wire_cell_phlex_arrow
