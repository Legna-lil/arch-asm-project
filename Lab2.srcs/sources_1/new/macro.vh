// macro.vh - opcode definitions
`ifndef MACRO_VH
`define MACRO_VH

`define OP_R_TYPE 7'b0110011
`define OP_I_TYPE 7'b0010011
`define OP_LOAD   7'b0000011
`define OP_STORE  7'b0100011
`define OP_BRANCH 7'b1100011
`define OP_AUIPC  7'b0010111
`define OP_JAL    7'b1101111

`endif
