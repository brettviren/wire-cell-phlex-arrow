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
//   wc.tracksegmentset members: tracksegmentset
//   wc.blobs   members: blobs

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

/// Convert a track segment set to a single-member wc.tracksegmentset TableGroup.
phlex_arrow::TableGroup to_table_group(const wcphlex::TrackSegmentSet& segset);

/// Convert a vector of IBlobSet to a single-member wc.blobs TableGroup.
phlex_arrow::TableGroup to_table_group(const wcphlex::BlobSets& blobs);

/// Convert a 3D-imaging ICluster to the SAME wc.blobs TableGroup, extracting its
/// 'b' (IBlob) nodes with their solved/filled charge.
phlex_arrow::TableGroup to_table_group(const wcphlex::Cluster& cluster);

// ---- read side: TableGroup -> WCT wrapper (Arrow-backed facade) ----

/// Reconstruct a frame from a wc.frame TableGroup using the ArrowFrame facade.
wcphlex::Frame frame_from_table_group(const phlex_arrow::TableGroup& group);

/// Reconstruct a deposet from a wc.deposet TableGroup (ArrowDepoSet facade).
wcphlex::DepoSet deposet_from_table_group(const phlex_arrow::TableGroup& group);

/// Reconstruct a tensorset from a wc.tensorset TableGroup (ArrowTensorSet).
wcphlex::TensorSet tensorset_from_table_group(const phlex_arrow::TableGroup& group);

/// Reconstruct a track segment set from a wc.tracksegmentset TableGroup
/// (ArrowTrackSegmentSet facade).
wcphlex::TrackSegmentSet tracksegmentset_from_table_group(const phlex_arrow::TableGroup& group);

// ---- edep bridge: edep.observables -> WCT track segments ----

/// Build a track segment set from the 'segments' member (edep.segments schema,
/// owned by the edep-arrow package) of an edep.observables TableGroup.
///
/// ZERO-COPY: the needed columns are projected, renamed to the
/// wc.tracksegment.* names and re-stamped with the wc.tracksegmentset schema
/// metadata -- the underlying Arrow arrays are shared, not copied.  A missing
/// pdg column (pre-v2 edep.segments tables) is filled with zeros.  Extra edep
/// columns (sd, n_photons, contributors) are dropped from the projection.
wcphlex::TrackSegmentSet tracksegmentset_from_observables(const phlex_arrow::TableGroup& group);

}  // namespace wire_cell_phlex_arrow

#endif  // WIRE_CELL_PHLEX_ARROW_CONVERT_H
