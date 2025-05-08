// Adapted from Matt Venn's VGA clock:
// https://github.com/mattvenn/tt08-vga-clock/blob/main/src/vga_clock.v

`default_nettype none

module clock_logic #(
    parameter CORE_CLOCK = 25_000_000
) (
    input wire clk,
    input wire reset,
    input wire adj_hrs,
    input wire adj_min,
    input wire adj_sec,
    input wire but_clk_en,  // Pulses (e.g. on frame end) to throttle button update rate.
    output reg [3:0] sec_u,
    output reg [2:0] sec_d,
    output reg [3:0] min_u,
    output reg [2:0] min_d,
    output reg [3:0] hrs_u,
    output reg [1:0] hrs_d,
    output reg [2:0] color_offset // Used to cycle through colour ramp, as 'minutes' increments.
);
    reg [24:0] sec_counter; // Enough to hold CORE_CLOCK counts.

    wire adj_sec_pulse, adj_min_pulse, adj_hrs_pulse;

    always @(posedge clk) begin
        if(reset) begin
            sec_u <= 0;
            sec_d <= 0;
            min_u <= 0;
            min_d <= 0;
            hrs_u <= 0;
            hrs_d <= 0;
            sec_counter <= 0;
            color_offset <= 0;
        end else begin
            if(sec_u == 10) begin
                sec_u <= 0;
                sec_d <= sec_d + 1;
            end
            if(sec_d == 6) begin
                sec_d <= 0;
                min_u <= min_u + 1;
                color_offset <= color_offset + 1;
            end
            if(min_u == 10) begin
                min_u <= 0;
                min_d <= min_d + 1;
            end
            if(min_d == 6) begin
                min_d <= 0;
                hrs_u <= hrs_u + 1;
            end
            if(hrs_u == 10) begin
                hrs_u <= 0;
                hrs_d <= hrs_d + 1;
            end
            if(hrs_d == 2 && hrs_u == 4) begin
                hrs_u <= 0;
                hrs_d <= 0;
            end

            // second counter
            sec_counter <= sec_counter + 1;
            if(sec_counter + 1 == CORE_CLOCK) begin
                sec_u <= sec_u + 1;
                sec_counter <= 0;
            end

            // adjustment buttons
            if(adj_sec_pulse)
                sec_u <= sec_u + 1;
            if(adj_min_pulse) begin
                min_u <= min_u + 1;
                color_offset <= color_offset + 1;
            end
            if(adj_hrs_pulse)
                hrs_u <= hrs_u + 1;
        end
    end

    localparam MAX_BUT_RATE = 16;
    localparam DEC_COUNT = 1;
    localparam MIN_COUNT = 2;
    button_pulse #(.MIN_COUNT(MIN_COUNT), .DEC_COUNT(DEC_COUNT), .MAX_COUNT(MAX_BUT_RATE)) 
        pulse_sec (.clk(clk), .clk_en(but_clk_en), .button(adj_sec), .pulse(adj_sec_pulse), .reset(reset));
    button_pulse #(.MIN_COUNT(MIN_COUNT), .DEC_COUNT(DEC_COUNT), .MAX_COUNT(MAX_BUT_RATE)) 
        pulse_min (.clk(clk), .clk_en(but_clk_en), .button(adj_min), .pulse(adj_min_pulse), .reset(reset));
    button_pulse #(.MIN_COUNT(MIN_COUNT), .DEC_COUNT(DEC_COUNT), .MAX_COUNT(MAX_BUT_RATE)) 
        pulse_hrs (.clk(clk), .clk_en(but_clk_en), .button(adj_hrs), .pulse(adj_hrs_pulse), .reset(reset));


endmodule


module vga_clock_gen (
    input clk,
    input reset,
    input [9:0] x_px,   // X position for actual pixel.
    input [9:0] y_px,   // Y position for actual pixel.
    input activevideo,
    input [3:0] sec_u,
    input [2:0] sec_d,
    input [3:0] min_u,
    input [2:0] min_d,
    input [3:0] hrs_u,
    input [1:0] hrs_d,
    input [2:0] color_offset, // Used to cycle through colour ramp, as 'minutes' increments.
    output wire [5:0] rrggbb
);
    // these units are expressed in "blocks"
    localparam OFFSET_Y_BLK = 0;
    localparam OFFSET_X_BLK = 1;
    localparam NUM_CHARS = 8;
    localparam FONT_W = 4;
    localparam FONT_H = 5;
    localparam COLON = 10;
    localparam BLANK = 11;
    localparam COL_INDEX_W = $clog2(FONT_W);

    wire [FONT_W-1:0] font_out;
    wire [5:0] font_addr;
    wire [5:0] digit_index;
    wire [5:0] color;
    wire [3:0] number;
    wire [COL_INDEX_W-1:0] col_index;
    reg [COL_INDEX_W-1:0] col_index_q;

    wire px_clk = clk;

    // blocks are 16 x 16 px. total width = 8 * blocks of 4 =  512. 
    /* verilator lint_off WIDTH */
    wire [5:0] x_block = (x_px -64) >> 4;
    wire [5:0] y_block = (y_px -200) >> 4;
    /* verilator lint_on WIDTH */
    reg [5:0] x_block_q;
    reg [5:0] y_block_q;

    fontROM #(.data_width(FONT_W)) font_0 (.clk(px_clk), .addr(font_addr), .dout(font_out));

    digit #(.FONT_W(FONT_W), .FONT_H(FONT_H), .NUM_BLOCKS(NUM_CHARS*FONT_W)) digit_0 (.clk(px_clk), .x_block(x_block), .number(number), .digit_index(digit_index), .col_index(col_index), .color(color), .color_offset(color_offset));

    /* verilator lint_off WIDTH */
    assign number     = x_block < FONT_W * 1 ? hrs_d :
                        x_block < FONT_W * 2 ? hrs_u :
                        x_block < FONT_W * 3 ? COLON :
                        x_block < FONT_W * 4 ? min_d :
                        x_block < FONT_W * 5 ? min_u :
                        x_block < FONT_W * 6 ? COLON :
                        x_block < FONT_W * 7 ? sec_d :
                        x_block < FONT_W * 8 ? sec_u :
                        BLANK;
    /* verilator lint_on WIDTH */
   
    reg draw;
    assign rrggbb = activevideo && draw ? color : 6'b0;
    assign font_addr = digit_index + y_block;
    always @(posedge px_clk) begin
        if(reset) begin
            draw <= 0;
            x_block_q <= 0;
            y_block_q <= 0;
        end else begin
            x_block_q <= x_block;
            y_block_q <= y_block;
        end
        col_index_q <= col_index;
        if(x_block_q < FONT_W * NUM_CHARS && y_block_q < FONT_H)
            draw <= font_out[(FONT_W - 1) - col_index_q];
        else
            draw <= 0;
    
    end
endmodule


module button_pulse 
#(
    parameter MAX_COUNT = 8,    // max wait before issue next pulse
    parameter DEC_COUNT = 2,    // every pulse, decrement comparitor by this amount
    parameter MIN_COUNT = 1     // until reaches this wait time
)(
    input wire clk,
    input wire clk_en,
    input wire button,
    input wire reset,
    output wire pulse
);

    reg [$clog2(MAX_COUNT-1):0] comp;
    reg [$clog2(MAX_COUNT-1):0] count;

    assign pulse = (clk_en && button && count == 0);

    always @(posedge clk)
        if(reset) begin
            comp <= MAX_COUNT - 1;
            count <= 0;
        end else
        if(clk_en) begin
            if(button)
                count <= count + 1;

            // if button is held, increase pulse rate by reducing comp
            if(count == 0 && comp > (MIN_COUNT + DEC_COUNT)) begin
                comp <= comp - DEC_COUNT;
            end

            // reset counter
            if(count == comp)
                count <= 0;

            // if button is released, set count and comp to default
            if(!button) begin
                count <= 0;
                comp <= MAX_COUNT - 1;
            end
        end

endmodule


module digit #(
    parameter FONT_W = 3,
    parameter FONT_H = 5,
    parameter NUM_BLOCKS = 20
) (
    input wire clk,
    input wire [5:0] x_block,
    // input wire [5:0] y_block,
    input wire [3:0] number,      // the number to display: [0->9: ]
    input wire [2:0] color_offset, // shift through the colours
    output reg [5:0] digit_index,
    output reg [5:0] color,
    output reg [$clog2(FONT_W)-1:0] col_index
);

    localparam COL_INDEX_W = $clog2(FONT_W); 

    wire [3:0] char = x_block[5:2];
    wire [4:0] color_hash = char + {1'd0, color_offset};
    always @(posedge clk) begin
        /* verilator lint_off WIDTH */
        case (number) // This is number*5:
            4'd0    : digit_index <= 6'h00;
            4'd1    : digit_index <= 6'h05;
            4'd2    : digit_index <= 6'h0a;
            4'd3    : digit_index <= 6'h0f;
            4'd4    : digit_index <= 6'h14;
            4'd5    : digit_index <= 6'h19;
            4'd6    : digit_index <= 6'h1e;
            4'd7    : digit_index <= 6'h23;
            4'd8    : digit_index <= 6'h28;
            4'd9    : digit_index <= 6'h2d;
            4'd10   : digit_index <= 6'h32;
            4'd11   : digit_index <= 6'h37;
            default : digit_index <= 0;
        endcase
        col_index <= x_block < NUM_BLOCKS ? x_block[1:0] : 3;
        case (color_hash[2:0])
            3'd0    : color <= 6'b110000;
            3'd1    : color <= 6'b111000;
            3'd2    : color <= 6'b111100;
            3'd3    : color <= 6'b001000;
            3'd4    : color <= 6'b000011;
            3'd5    : color <= 6'b100010;
            3'd6    : color <= 6'b010010;
            3'd7    : color <= 6'b100001;
        endcase
        /* verilator lint_on WIDTH */
    end
   
endmodule


// Font ROM for numbers 0-9, 4x5 pixels, but really only 3x5.
module fontROM 
#(
    parameter addr_width = 6,
    parameter data_width = 4
)
(
    input wire                  clk,
    input wire [addr_width-1:0] addr,
    output reg [data_width-1:0] dout
);

    always @(posedge clk)
        begin
            case (addr)
                6'd0    : dout <= 4'b1110;
                6'd1    : dout <= 4'b1010;
                6'd2    : dout <= 4'b1010;
                6'd3    : dout <= 4'b1010;
                6'd4    : dout <= 4'b1110;
                6'd5    : dout <= 4'b1100;
                6'd6    : dout <= 4'b0100;
                6'd7    : dout <= 4'b0100;
                6'd8    : dout <= 4'b0100;
                6'd9    : dout <= 4'b1110;
                6'd10   : dout <= 4'b1110;
                6'd11   : dout <= 4'b0010;
                6'd12   : dout <= 4'b1110;
                6'd13   : dout <= 4'b1000;
                6'd14   : dout <= 4'b1110;
                6'd15   : dout <= 4'b1110;
                6'd16   : dout <= 4'b0010;
                6'd17   : dout <= 4'b1110;
                6'd18   : dout <= 4'b0010;
                6'd19   : dout <= 4'b1110;
                6'd20   : dout <= 4'b1010;
                6'd21   : dout <= 4'b1010;
                6'd22   : dout <= 4'b1110;
                6'd23   : dout <= 4'b0010;
                6'd24   : dout <= 4'b0010;
                6'd25   : dout <= 4'b1110;
                6'd26   : dout <= 4'b1000;
                6'd27   : dout <= 4'b1110;
                6'd28   : dout <= 4'b0010;
                6'd29   : dout <= 4'b1110;
                6'd30   : dout <= 4'b1000;
                6'd31   : dout <= 4'b1000;
                6'd32   : dout <= 4'b1110;
                6'd33   : dout <= 4'b1010;
                6'd34   : dout <= 4'b1110;
                6'd35   : dout <= 4'b1110;
                6'd36   : dout <= 4'b0010;
                6'd37   : dout <= 4'b0100;
                6'd38   : dout <= 4'b1000;
                6'd39   : dout <= 4'b1000;
                6'd40   : dout <= 4'b1110;
                6'd41   : dout <= 4'b1010;
                6'd42   : dout <= 4'b1110;
                6'd43   : dout <= 4'b1010;
                6'd44   : dout <= 4'b1110;
                6'd45   : dout <= 4'b1110;
                6'd46   : dout <= 4'b1010;
                6'd47   : dout <= 4'b1110;
                6'd48   : dout <= 4'b0010;
                6'd49   : dout <= 4'b0010;
                6'd50   : dout <= 4'b0000;
                6'd51   : dout <= 4'b0100;
                6'd52   : dout <= 4'b0000;
                6'd53   : dout <= 4'b0100;
                6'd54   : dout <= 4'b0000;
                6'd55   : dout <= 4'b0000;
                6'd56   : dout <= 4'b0000;
                6'd57   : dout <= 4'b0000;
                6'd58   : dout <= 4'b0000;
                6'd59   : dout <= 4'b0000;
                default : dout <= 4'b1110;
            endcase
        end

endmodule
