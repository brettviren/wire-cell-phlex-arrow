#ifndef WIRE_CELL_PHLEX_ARROW_CONVERT_H
#define WIRE_CELL_PHLEX_ARROW_CONVERT_H

// WCT <-> Arrow conversion for Phlex products.
//
// This is the N-axis (domain) glue for Wire-Cell Toolkit: it bridges the
// WCT product wrappers (wcphlex::Frame/DepoSet/TensorSet, from wire-cell-phlex)
// and the uniform Phlex Arrow product (phlex_arrow::TableGroup, from
// phlex-arrow-common) by calling the pure converters/facades in
// wire-cell-arrow.
//
// to_table_group():   wcphlex::<T> -> TableGroup   (write side)
// <T>_from_table_group(): TableGroup -> wcphlex::<T> (read side, via facade)
//
// The TableGroup `type` and reserved member names are the domain conventions
// (owned here, documented below); arrow-hdf and phlex-arrow-common are
// agnostic to them.
//
//   wc.frame    members: traces, frame_tags, trace_tags, cmm
//   wc.deposet  members: deposet
//   wc.tensorset members: tensorset

#include "phlex_arrow_common/TableGroup.hpp"

#include "wire_cell_phlex/Data.hpp"

namespace wire_cell_phlex_arrow {

// ---- write side: WCT wrapper -> TableGroup ----

/// Convert a frame to a wc.frame TableGroup (sparse traces + companion tables).
phlex_arrow::TableGroup to_table_group(const wcphlex::Frame& frame);

/// Convert a deposet to a single-member wc.deposet TableGroup.
phlex_arrow::TableGroup to_table_group(const wcphlex::DepoSet& deposet);

/// Convert a tensorset to a single-member wc.tensorset TableGroup.
phlex_arrow::TableGroup to_table_group(const wcphlex::TensorSet& tensorset);

// ---- read side: TableGroup -> WCT wrapper (Arrow-backed facade) ----

/// Reconstruct a frame from a wc.frame TableGroup using the ArrowFrame facade.
wcphlex::Frame frame_from_table_group(const phlex_arrow::TableGroup& group);

/// Reconstruct a deposet from a wc.deposet TableGroup (ArrowDepoSet facade).
wcphlex::DepoSet deposet_from_table_group(const phlex_arrow::TableGroup& group);

/// Reconstruct a tensorset from a wc.tensorset TableGroup (ArrowTensorSet).
wcphlex::TensorSet tensorset_from_table_group(const phlex_arrow::TableGroup& group);

}  // namespace wire_cell_phlex_arrow

#endif  // WIRE_CELL_PHLEX_ARROW_CONVERT_H
