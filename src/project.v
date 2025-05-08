/*
 * Copyright (c) 2025 Anton Maurovic
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`define RGB [5:0] // RrGgBb order

module tt_um_algofoogle_fun_vga_clock (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  localparam kClouds        = 64;
  localparam kGrassTop      = 384;
  localparam kDarkGrassTop  = 390;
  localparam kDirtShadow    = kGrassTop + 24;
  localparam kDirtTop       = kDirtShadow + 6;
  localparam kPlayerWidth   = 32;
  localparam kPlayerHeight  = 32;
  localparam kPlayerRadius1 = 16;
  localparam kPlayerRadius2 = 13;
  localparam kRangeX        = 640 - kPlayerWidth;
  localparam kRangeY        = kGrassTop - kPlayerHeight;
  localparam kSpeedX        = 9;
  localparam kInitialVelY   = 21;
  localparam kPulseFadeRate = 5;

  wire reset = ~rst_n;
  wire clock_adj_hrs        = ui_in[0];
  wire clock_adj_min        = ui_in[1];
  wire clock_adj_sec        = ui_in[2];
  wire pmod_select          = ui_in[3]; // 0=Tiny VGA, 1=Matt's VGA Clock.
  wire show_clock           = ui_in[4];
  wire video_timing_mode    = ui_in[7];
  wire hsync;
  wire vsync;
  wire [1:0] rr,gg,bb;
  wire [9:0] h,v;
  wire hmax,vmax, hblank,vblank;
  wire frame_end = hmax & vmax;
  wire visible; // Whether the display is in the visible region, or blanking region.

  // Tiny VGA PMOD wiring, with 'visible' used for blanking:
  assign uo_out =
    pmod_select ? {rr, gg, bb, vsync, hsync} :
                  {hsync, {3{visible}} & {bb[0], gg[0], rr[0]}, vsync, {3{visible}} & {bb[1], gg[1], rr[1]}};

  assign uio_out = {
    3'b000, // Unused.
    visible,
    vblank,
    hblank,
    vmax,
    hmax
  };
  assign uio_oe  = 8'b0001_1111; // Top 3 bidir pins are inputs, rest are outputs.

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[6:0], uio_in, 1'b0};

  vga_sync vga_sync(
    .clk      (clk),
    .reset    (reset),
    .mode     (video_timing_mode),
    .o_hsync  (hsync),
    .o_vsync  (vsync),
    .o_hpos   (h),
    .o_vpos   (v),
    .o_hmax   (hmax),
    .o_vmax   (vmax),
    .o_hblank (hblank),
    .o_vblank (vblank),
    .o_visible(visible)
  );

  reg signed [7:0] ydelta;
  reg ydir;
  reg signed [11:0] pxm, pym;
  // Player position:
  wire [9:0] px = pxm[11:2];//, py;
  wire [9:0] py = pym[9:0];
  reg dx; // 0=left, 1=right

  reg [10:0] product_comp;
  reg product_comp_dir;
  reg [3:0] t;

  wire hit_right_edge = px >= kRangeX;
  wire hit_left_edge = px <= 0;

  // X direction control:
  always @(posedge clk) begin
    if (reset) dx <= 1;
    else if (hit_right_edge) dx <= 0;
    else if (hit_left_edge) dx <= 1;
  end

  wire ground_bounce = ydelta < 0 && pym[11:8]==0 && pym[7:0] <= {-ydelta};

  // Ball inner glow:
  always @(posedge clk) begin
    if (reset)
      product_comp <= 10;
    else if (frame_end)
      if (ground_bounce || hit_right_edge || hit_left_edge)
        // Pulse when we hit the ground or an edge:
        product_comp <= 220;
      else if (product_comp >= kPulseFadeRate)
        product_comp <= product_comp - kPulseFadeRate;
  end

  // X position control:
  always @(posedge clk) begin
    if (reset) begin
      pxm <= 0;
      ydelta <= kInitialVelY;
      ydir <= 0;
      pym <= 0;
      t <= 0;
    end else if (frame_end) begin
      // Update for next frame:
      t <= t + 1;

      pxm <= dx ? pxm + kSpeedX : pxm - kSpeedX;

      if (ground_bounce) begin
        // Bounce on the ground.
        pym <= 0;
        ydelta <= 17 + {5'd0,px[2:0]}; // Makes the next bounce velocity (hence height) look a little random.
      end else begin
        pym <= pym + {{4{ydelta[7]}}, ydelta};
        ydelta <= ydelta - 1;
      end

    end
  end

  localparam `RGB zenith        = 6'b00_01_11; // Light blue.
  localparam `RGB sky           = 6'b01_10_11; // Bright blue.
  localparam `RGB grass         = 6'b01_10_00; // Lively green.
  localparam `RGB bright_grass  = 6'b01_11_00; // Bright green.
  localparam `RGB dark_grass1   = 6'b00_10_00; // Dark green.
  localparam `RGB dark_grass2   = 6'b00_01_00; // Darker green.
  localparam `RGB dirt_shadow   = 6'b01_00_00; // Dark brown.
  localparam `RGB dirt          = 6'b10_01_00; // Medium brown.
  localparam `RGB player_heart  = 6'b11_01_00; // Bright red.
  localparam `RGB player_ring   = 6'b10_00_00; // Red.
  localparam `RGB shadow        = 6'b00_00_00; // Black.
  localparam `RGB sheen         = 6'b11_11_10; // Very light yellow.
  localparam `RGB white         = 6'b11_11_11; // White.


  wire signed [9:0] pxo = h-(kPlayerWidth/2)-px;
  wire signed [4:0] psubx = pxo[4:0];
  wire signed [9:0] pyo = v-(kPlayerHeight/2)+py-kGrassTop;
  wire signed [4:0] psuby = pyo[4:0];
  wire signed [10:0] product = psubx*psubx + psuby*psuby;

  wire in_player_box =
    (h >= px) && (h < px+kPlayerWidth) &&
    (v >= kGrassTop-py-kPlayerHeight) && (v < kGrassTop-py);
  wire [9:0] hpx = h-px;
  wire [9:0] vpy = v+py;
  // wire in_player_sheen  = ((h-px) < 16) && ((kGrassTop-v-py-kPlayerHeight+16) < 16) && (hpx[3:1]==3'b101) && (vpy[3:1]==3'b101);//^py[3]^v[3]);
  reg player_sheen_shape;
  always @(*) begin
    case ({hpx[1:0],vpy[1:0]})
      4'd0:     player_sheen_shape = 0;
      4'd3:     player_sheen_shape = 0;
      4'd12:    player_sheen_shape = 0;
      4'd15:    player_sheen_shape = 0;
      default:  player_sheen_shape = 1;
    endcase
  end
  wire in_player_sheen = ((h-px) < 16) && ((kGrassTop-v-py-kPlayerHeight+16) < 16) && (hpx[4:2]==3'b010) && (vpy[4:2]==3'b010) && player_sheen_shape;

  wire in_player_ring  = in_player_box && (product < (kPlayerRadius1*kPlayerRadius1-15) );
  wire in_player_heart = in_player_box && (product < product_comp); //(kPlayerRadius2*kPlayerRadius2-15) );
  wire `RGB player_heart_color =
    product_comp > 210  ? 6'b11_11_11 :
    product_comp > 200  ? 6'b11_11_01 :
    product_comp > 180  ? 6'b11_10_00 :
    product_comp > 140  ? 6'b11_01_00 :
                          6'b11_00_00;

  wire in_grass       = (v >= kGrassTop);
  wire in_dark_grass  = (v >= kDarkGrassTop);
  wire in_dirt        = (v >= kDirtTop);
  wire in_dirt_shadow = (v >= kDirtShadow);
  wire in_clouds      = (v <  kClouds);

  wire `RGB clock_rgb, clock_shadow_rgb;

  wire [3:0] clock_sec_u;
  wire [2:0] clock_sec_d;
  wire [3:0] clock_min_u;
  wire [2:0] clock_min_d;
  wire [3:0] clock_hrs_u;
  wire [1:0] clock_hrs_d;
  wire [2:0] clock_color_offset;

  clock_logic matt_venn_clock (
    .clk          (clk),
    .reset        (reset),
    .adj_hrs      (clock_adj_hrs),
    .adj_min      (clock_adj_min),
    .adj_sec      (clock_adj_sec),
    .but_clk_en   (frame_end),
    .sec_u        (clock_sec_u),
    .sec_d        (clock_sec_d),
    .min_u        (clock_min_u),
    .min_d        (clock_min_d),
    .hrs_u        (clock_hrs_u),
    .hrs_d        (clock_hrs_d),
    .color_offset (clock_color_offset)
  );

  vga_clock_gen matt_venn_vga (
    .clk          (clk),
    .reset        (reset),
    .x_px         (h),   // X position for actual pixel.
    .y_px         (v),   // Y position for actual pixel.
    .activevideo  (visible),
    .sec_u        (clock_sec_u),
    .sec_d        (clock_sec_d),
    .min_u        (clock_min_u),
    .min_d        (clock_min_d),
    .hrs_u        (clock_hrs_u),
    .hrs_d        (clock_hrs_d),
    .color_offset (clock_color_offset),
    .rrggbb       (clock_rgb)
  );

  // Used for creating a shadow under clock digits:
  vga_clock_gen matt_venn_vga_shadow (
    .clk          (clk),
    .reset        (reset),
    .x_px         (h-4),   // X position for actual pixel, offset by 16 for shadow.
    .y_px         (v-4),   // Y position for actual pixel, offset by 16 for shadow.
    .activevideo  (visible),
    .sec_u        (clock_sec_u),
    .sec_d        (clock_sec_d),
    .min_u        (clock_min_u),
    .min_d        (clock_min_d),
    .hrs_u        (clock_hrs_u),
    .hrs_d        (clock_hrs_d),
    .color_offset (clock_color_offset),
    .rrggbb       (clock_shadow_rgb)
  );

  wire [9:0] ht = h+{6'd0,t};
  wire [9:0] htslow = h+{7'd0,t[3:1]};

  wire in_clock       = show_clock && (clock_rgb != 0);
  wire in_clock_shade = show_clock && (clock_shadow_rgb != 0);
  wire in_clock_sheen = in_clock & !in_clock_shade;
  wire frizz          = ((ht[1:0]^v[1:0]) != v[3:2]);
  wire frizz2         = ((ht[2:0]^v[2:0]) != v[3:1]);
  wire frizz3         = ((htslow[1:0]^v[1:0]) != v[3:2]);
  wire haze           = h[0]^v[0];
  wire hazet          = ht[0]^v[0];
  wire hazets         = htslow[0]^v[0];
  // wire clouds_blend   = ( (!frizz) && (ht[2]^v[2] || (v[5]==0)) || ((v[6:2]==0) && hazet));
  wire clouds_blend   = ( (!frizz3) && (htslow[2]^v[2] || (v[5]==0)) || ((v[6:2]==0) && hazets));
  wire db1            = (((v-5)&10'b10000)==0);
  wire dirt_blend     = ((hazet && !db1) || (hazet && (ht[2]^v[2]) && db1)) && (v<435);

  wire `RGB rgb =
    in_player_sheen ? white :
    in_dirt         ? (dirt_blend ? dirt_shadow : dirt ) :
    in_dirt_shadow  ? dirt_shadow :
    in_dark_grass   ? (frizz ? dark_grass1 : dark_grass2) :
    in_grass        ? (frizz2 ? grass : bright_grass) :
    in_player_heart ? player_heart_color :
    in_player_ring  ? player_ring :
    in_clock_sheen  ? (haze ? clock_rgb : sheen) :
    in_clock        ? clock_rgb :
    in_clock_shade  ? shadow :
    in_clouds       ? ( clouds_blend ? zenith : sky) :
                      sky;

  assign {rr,gg,bb} = rgb;

endmodule

