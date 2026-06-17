# wire-cell-phlex-arrow tests.

add_executable(test_convert test_convert.cpp)
target_link_libraries(test_convert PRIVATE
  wire_cell_phlex_arrow
  WireCell::Aux
  Arrow::arrow_shared
  ${WCPA_RUNTIME_LIBS})
add_test(NAME convert COMMAND test_convert)
