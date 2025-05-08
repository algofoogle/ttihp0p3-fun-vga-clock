`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/

// `define DUMP_VCD

module tb ();

  //NOTE: DON'T write VCD file, because it'd be huge!
`ifdef DUMP_VCD
  // Dump the signals to a VCD file. You can view it with gtkwave.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end
`endif

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  // Specific outputs for this design:
  // RrGgBb and H/Vsync pin ordering is per Tiny VGA PMOD
  // (https://tinytapeout.com/specs/pinouts/#vga-output)
  wire [1:0] rr   = {uo_out[0],uo_out[4]};
  wire [1:0] gg   = {uo_out[1],uo_out[5]};
  wire [1:0] bb   = {uo_out[2],uo_out[6]};
  wire [5:0] rgb  = {rr,gg,bb}; // Just used by cocotb test bench for convenient checks.
  wire hsync      = uo_out[7];
  wire vsync      = uo_out[3];
  wire hmax       = uio_out[0];
  wire vmax       = uio_out[1];
  wire hblank     = uio_out[2];
  wire vblank     = uio_out[3];
  wire visible    = uio_out[4];

  // Specific inputs for this design:
  reg mode;
  reg adj_hrs;
  reg adj_min;
  reg adj_sec;
  reg show_clock;
  reg pmod_select;
  assign ui_in[7] = mode;
  assign ui_in[4] = show_clock;
  assign ui_in[3] = pmod_select;
  assign ui_in[2] = adj_hrs;
  assign ui_in[1] = adj_min;
  assign ui_in[0] = adj_sec;

  // Replace tt_um_example with your module name:
  tt_um_algofoogle_vga user_project (
      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule
