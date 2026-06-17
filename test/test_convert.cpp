// Unit test for wire-cell-phlex-arrow Convert: wcphlex::Frame -> TableGroup
// and back via the ArrowFrame facade.
//
// Builds a SimpleFrame (traces + frame tag + trace tags + CMM), converts it to
// a wc.frame TableGroup, checks the type label and reserved member names, then
// round-trips it back to a wcphlex::Frame and verifies the scalars, trace
// charges, and tags survive.

#include "wire_cell_phlex_arrow/Convert.hpp"

#include "WireCellAux/SimpleFrame.h"
#include "WireCellAux/SimpleTrace.h"

#include <cmath>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

using WireCell::IFrame;
using WireCell::ITrace;
using WireCell::Aux::SimpleFrame;
using WireCell::Aux::SimpleTrace;

static int fail(const std::string& msg)
{
    std::cerr << "FAIL: " << msg << "\n";
    return 1;
}

int main()
{
    // ---- build a frame ----
    ITrace::vector traces{
      std::make_shared<SimpleTrace>(10, 0, std::vector<float>{1, 2, 3}),
      std::make_shared<SimpleTrace>(20, 5, std::vector<float>{4, 5}),
    };
    WireCell::Waveform::ChannelMaskMap cmm;
    cmm["bad"][5] = {{10, 20}, {30, 40}};

    const double ftime = 1.25e-3, ftick = 0.5;
    auto sf = std::make_shared<SimpleFrame>(99, ftime, traces, ftick, cmm);
    sf->tag_frame("solid");
    sf->tag_traces("loose", IFrame::trace_list_t{0, 1}, IFrame::trace_summary_t{1.5, 2.5});

    wcphlex::Frame frame{IFrame::pointer(sf)};

    // ---- write side: to TableGroup ----
    auto group = wire_cell_phlex_arrow::to_table_group(frame);

    if (group.type != "wc.frame") return fail("group.type != wc.frame: " + group.type);
    for (const auto* name : {"traces", "frame_tags", "trace_tags", "cmm"}) {
        if (!group.members.count(name)) return fail(std::string("missing member ") + name);
        if (!group.members.at(name)) return fail(std::string("null member ") + name);
    }
    if (group.members.at("traces")->num_rows() != 2) return fail("traces rows != 2");

    // ---- read side: round-trip via facade ----
    auto rt = wire_cell_phlex_arrow::frame_from_table_group(group);
    if (!rt.ptr) return fail("round-trip frame is null");

    if (rt.ptr->ident() != 99) return fail("ident != 99");
    if (std::abs(rt.ptr->time() - ftime) > 1e-12) return fail("time mismatch");
    if (std::abs(rt.ptr->tick() - ftick) > 1e-12) return fail("tick mismatch");

    auto rt_traces = rt.ptr->traces();
    if (!rt_traces || rt_traces->size() != 2) return fail("round-trip trace count != 2");

    const auto& q0 = rt_traces->at(0)->charge();
    if (q0.size() != 3 || q0[0] != 1 || q0[2] != 3) return fail("trace 0 charge mismatch");
    if (rt_traces->at(0)->channel() != 10) return fail("trace 0 channel != 10");
    if (rt_traces->at(1)->tbin() != 5) return fail("trace 1 tbin != 5");

    const auto& ftags = rt.ptr->frame_tags();
    if (std::find(ftags.begin(), ftags.end(), "solid") == ftags.end())
        return fail("frame tag 'solid' missing");

    const auto& ttags = rt.ptr->trace_tags();
    if (std::find(ttags.begin(), ttags.end(), "loose") == ttags.end())
        return fail("trace tag 'loose' missing");

    std::cout << "OK: Frame -> wc.frame TableGroup -> Frame round-trip\n";
    return 0;
}
