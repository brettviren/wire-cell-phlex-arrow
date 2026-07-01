// PHLEX plugin: register Arrow->WCT convert nodes (the read direction).
//
// Each configured type gets one transform phlex_arrow::TableGroup ->
// wcphlex::<T>, reconstructing the WCT object from the Arrow tables via the
// facades (wire_cell_phlex_arrow::<T>_from_table_group).  This is the consumer
// that gives a read SOURCE (e.g. phlex_arrow_hdf_source, which emits
// TableGroup products) something to demand, so the source actually runs.
//
// Config keys:
//   types         (array of strings, optional): which of {frame,deposet,
//                 tensorset} to convert.  Default: all three.
//   input_creator (string, optional):  creator of the input TableGroup products
//                 (the read source's output_creator).  Default "input".
//   input_layer   (string, required):  Phlex layer of the input products.
//
// For each type the input (TableGroup) suffix and the output (wcphlex) suffix
// are the type name itself; the output product's creator is this algorithm, so
// a downstream consumer routes on (this-algorithm, layer, type).

#include "wire_cell_phlex_arrow/Convert.hpp"

#include "phlex_arrow_common/ConvertNode.hpp"
#include "phlex_arrow_common/PhlexTypes.hpp"

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
        const std::string name = "wc_" + type + "_from_arrow";
        const product_selector in{.creator = creator,
                               .layer = layer,
                               .suffix = phlex_arrow::identifier{type}};

        if (type == "frame") {
            phlex_arrow::register_convert(
              m, name,
              [](phlex_arrow::TableGroup const& g) {
                  return wire_cell_phlex_arrow::frame_from_table_group(g);
              },
              in, type);
        }
        else if (type == "deposet") {
            phlex_arrow::register_convert(
              m, name,
              [](phlex_arrow::TableGroup const& g) {
                  return wire_cell_phlex_arrow::deposet_from_table_group(g);
              },
              in, type);
        }
        else if (type == "tensorset") {
            phlex_arrow::register_convert(
              m, name,
              [](phlex_arrow::TableGroup const& g) {
                  return wire_cell_phlex_arrow::tensorset_from_table_group(g);
              },
              in, type);
        }
        else {
            throw std::runtime_error("wire-cell-phlex-arrow: unknown convert type '" + type + "'");
        }
    }
}
