// PHLEX plugin: register the edep -> WCT track-segment bridge node.
//
// One transform phlex_arrow::TableGroup (type edep.observables, member
// 'segments' per the edep-arrow schema package) -> wcphlex::TrackSegmentSet,
// via the zero-copy column projection in tracksegmentset_from_observables().
// This is the seam between the edep-sim side of the full chain and the WCT
// sampling/simulation side (xerosere ddm-69y.5).
//
// Config keys:
//   input_creator (string, optional): creator (module label) of the input
//                 observables TableGroup.  Default "edep_observables".
//   input_layer   (string, required): Phlex layer of the input products.
//   input_suffix  (string, optional): input product suffix.  Default
//                 "observables".
//
// The output product suffix is "tracksegmentset" and its creator is this
// algorithm, so downstream consumers (eg wcph_tracksegmentset_to_deposet)
// route on (this module's label, layer, "tracksegmentset").

#include "wire_cell_phlex_arrow/Convert.hpp"

#include "phlex_arrow_common/ConvertNode.hpp"
#include "phlex_arrow_common/PhlexTypes.hpp"

#include "phlex/module.hpp"

#include <string>

using namespace phlex;

PHLEX_REGISTER_ALGORITHMS(m, config)
{
    const auto creator = config.get<std::string>("input_creator", "edep_observables");
    const auto layer = config.get<std::string>("input_layer");
    const auto suffix = config.get<std::string>("input_suffix", "observables");

    const product_selector in{.creator = creator,
                           .layer = layer,
                           .suffix = phlex_arrow::identifier{suffix}};

    phlex_arrow::register_convert(
      m, "edep_segments_to_tracksegmentset",
      [](phlex_arrow::TableGroup const& g) {
          return wire_cell_phlex_arrow::tracksegmentset_from_observables(g);
      },
      in, "tracksegmentset");
}
