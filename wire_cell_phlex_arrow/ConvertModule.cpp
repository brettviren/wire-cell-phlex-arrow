// PHLEX plugin: register WCT->Arrow convert nodes.
//
// Each configured WCT type gets one write-side transform wcphlex::<T> ->
// phlex_arrow::TableGroup, wired by the generic register_convert() helper from
// phlex-arrow-common.  The resulting TableGroup products are what a
// phlex-arrow-* output module (e.g. phlex-arrow-hdf) persists.
//
// Config keys:
//   types         (array of strings, optional): which of {frame,deposet,
//                 tensorset} to convert.  Default: all three.
//   input_creator (string, optional):  creator of the input WCT products.
//                 Default "input".
//   input_layer   (string, required):  Phlex layer of the input products.
//
// For each type the input product suffix and the output product suffix are the
// type name itself (e.g. "frame" -> "frame"); routing is unambiguous because
// the output's creator is this algorithm.

#include "wire_cell_phlex_arrow/Convert.hpp"

#include "phlex_arrow_common/ConvertNode.hpp"

#include "phlex/module.hpp"

#include <string>
#include <vector>

using namespace phlex;

PHLEX_REGISTER_ALGORITHMS(m, config)
{
    const auto creator = config.get<std::string>("input_creator", "input");
    const auto layer = config.get<std::string>("input_layer");
    auto types = config.get<std::vector<std::string>>("types", {"frame", "deposet", "tensorset"});

    for (const auto& type : types) {
        const std::string name = "wc_" + type + "_to_arrow";
        // identifier's std::string ctor is explicit, so build the suffix
        // optional explicitly (creator/layer accept strings via their setters).
        const product_query in{.creator = creator,
                               .layer = layer,
                               .suffix = phlex::experimental::identifier{type}};

        if (type == "frame") {
            phlex_arrow::register_convert(
              m, name,
              [](wcphlex::Frame const& f) { return wire_cell_phlex_arrow::to_table_group(f); },
              in, type);
        }
        else if (type == "deposet") {
            phlex_arrow::register_convert(
              m, name,
              [](wcphlex::DepoSet const& d) { return wire_cell_phlex_arrow::to_table_group(d); },
              in, type);
        }
        else if (type == "tensorset") {
            phlex_arrow::register_convert(
              m, name,
              [](wcphlex::TensorSet const& t) { return wire_cell_phlex_arrow::to_table_group(t); },
              in, type);
        }
        else {
            throw std::runtime_error("wire-cell-phlex-arrow: unknown convert type '" + type + "'");
        }
    }
}
