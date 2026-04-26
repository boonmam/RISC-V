`timescale 1ns / 1ps

module PMOD_SERIAL #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int SPI_DIV     = 20
)(
    input  logic clk,
    input  logic rst,

    output logic rst_n,
    output logic cs_n,
    output logic sclk,
    output logic mosi,

    output logic DCEN,
    output logic VCCEN,
    output logic PMODEN
);

    localparam int WAIT_20US_CYCLES  = CLK_FREQ_HZ / 50_000;
    localparam int WAIT_1MS_CYCLES   = CLK_FREQ_HZ / 1_000;
    localparam int WAIT_2MS_CYCLES   = CLK_FREQ_HZ / 500;
    localparam int WAIT_50MS_CYCLES  = CLK_FREQ_HZ / 20;
    localparam int WAIT_100MS_CYCLES = CLK_FREQ_HZ / 10;

    localparam int INIT_LEN      = 41;
    localparam int CLEAR_LEN     = 5;
    localparam int LINE_LEN      = 8;
    localparam int NUM_EDGES     = 12;

    localparam logic [7:0] CMD_DISPLAYOFF    = 8'hAE;
    localparam logic [7:0] CMD_DISPLAYON     = 8'hAF;
    localparam logic [7:0] CMD_CLEARWINDOW   = 8'h25;
    localparam logic [7:0] CMD_DRAWLINE      = 8'h21;

    typedef enum logic [4:0] {
        ST_RESET,
        ST_ENABLE_PMOD,
        ST_WAIT_PMOD,
        ST_ASSERT_OLED_RESET,
        ST_WAIT_RESET_LOW,
        ST_RELEASE_OLED_RESET,
        ST_WAIT_RESET_HIGH,
        ST_SEND_INIT,
        ST_SEND_CLEAR,
        ST_ENABLE_VCC,
        ST_WAIT_VCC,
        ST_SEND_DISPLAY_ON,
        ST_WAIT_AFTER_ON,
        ST_ANIM_CLEAR,
        ST_DRAW_CUBE,
        ST_FRAME_WAIT
    } state_t;

    typedef enum logic [1:0] {
        SPI_IDLE,
        SPI_CLK_LOW,
        SPI_CLK_HIGH,
        SPI_DONE
    } spi_state_t;

    state_t     state;
    spi_state_t spi_state;

    logic [31:0] wait_counter;

    logic [7:0] byte_index;
    logic [3:0] edge_index;
    logic [2:0] frame_index;
    logic [2:0] color_index;

    logic [7:0] tx_data;

    logic [7:0]  spi_shift;
    logic [2:0]  spi_bit_index;
    logic [15:0] spi_div_counter;

    logic spi_start;
    logic spi_busy;
    logic spi_done;

    // ------------------------------------------------------------
    // SSD1331 initialization byte ROM
    // ------------------------------------------------------------
    function automatic logic [7:0] init_byte(input logic [7:0] index);
        begin
            case (index)
                8'd0:  init_byte = 8'hFD; // Command lock
                8'd1:  init_byte = 8'h12;
                8'd2:  init_byte = 8'hFD;
                8'd3:  init_byte = 8'hB1;
                8'd4:  init_byte = CMD_DISPLAYOFF;

                8'd5:  init_byte = 8'hA0; // Remap / color depth
                8'd6:  init_byte = 8'h72;

                8'd7:  init_byte = 8'hA1; // Display start line
                8'd8:  init_byte = 8'h00;

                8'd9:  init_byte = 8'hA2; // Display offset
                8'd10: init_byte = 8'h00;

                8'd11: init_byte = 8'hA4; // Normal display

                8'd12: init_byte = 8'hA8; // Multiplex ratio
                8'd13: init_byte = 8'h3F;

                8'd14: init_byte = 8'hAD; // Master config
                8'd15: init_byte = 8'h8E;

                8'd16: init_byte = 8'hB0; // Power save mode
                8'd17: init_byte = 8'h0B;

                8'd18: init_byte = 8'hB1; // Phase length
                8'd19: init_byte = 8'h31;

                8'd20: init_byte = 8'hB3; // Display clock divider
                8'd21: init_byte = 8'hF0;

                8'd22: init_byte = 8'h8A; // Precharge A
                8'd23: init_byte = 8'h64;

                8'd24: init_byte = 8'h8B; // Precharge B
                8'd25: init_byte = 8'h78;

                8'd26: init_byte = 8'h8C; // Precharge C
                8'd27: init_byte = 8'h64;

                8'd28: init_byte = 8'hBB; // Precharge level
                8'd29: init_byte = 8'h3A;

                8'd30: init_byte = 8'hBE; // VCOMH
                8'd31: init_byte = 8'h3E;

                8'd32: init_byte = 8'h87; // Master current
                8'd33: init_byte = 8'h06;

                8'd34: init_byte = 8'h81; // Contrast A
                8'd35: init_byte = 8'h91;

                8'd36: init_byte = 8'h82; // Contrast B
                8'd37: init_byte = 8'h50;

                8'd38: init_byte = 8'h83; // Contrast C
                8'd39: init_byte = 8'h7D;

                8'd40: init_byte = 8'h2E; // Disable scrolling

                default: init_byte = 8'h00;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Clear full OLED screen
    //
    // Command format:
    // 0x25, x0, y0, x1, y1
    // ------------------------------------------------------------
    function automatic logic [7:0] clear_byte(input logic [7:0] index);
        begin
            case (index)
                8'd0: clear_byte = CMD_CLEARWINDOW;
                8'd1: clear_byte = 8'd0;
                8'd2: clear_byte = 8'd0;
                8'd3: clear_byte = 8'd95;
                8'd4: clear_byte = 8'd63;
                default: clear_byte = 8'h00;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Color table
    // ------------------------------------------------------------
    function automatic logic [7:0] color_r(input logic [2:0] c);
        begin
            case (c)
                3'd0: color_r = 8'hFF;
                3'd1: color_r = 8'hFF;
                3'd2: color_r = 8'h00;
                3'd3: color_r = 8'h00;
                3'd4: color_r = 8'h00;
                3'd5: color_r = 8'h80;
                3'd6: color_r = 8'hFF;
                3'd7: color_r = 8'hFF;
                default: color_r = 8'hFF;
            endcase
        end
    endfunction

    function automatic logic [7:0] color_g(input logic [2:0] c);
        begin
            case (c)
                3'd0: color_g = 8'h00;
                3'd1: color_g = 8'h80;
                3'd2: color_g = 8'hFF;
                3'd3: color_g = 8'hFF;
                3'd4: color_g = 8'h80;
                3'd5: color_g = 8'h00;
                3'd6: color_g = 8'h00;
                3'd7: color_g = 8'hFF;
                default: color_g = 8'hFF;
            endcase
        end
    endfunction

    function automatic logic [7:0] color_b(input logic [2:0] c);
        begin
            case (c)
                3'd0: color_b = 8'h00;
                3'd1: color_b = 8'h00;
                3'd2: color_b = 8'h00;
                3'd3: color_b = 8'h80;
                3'd4: color_b = 8'hFF;
                3'd5: color_b = 8'hFF;
                3'd6: color_b = 8'hFF;
                3'd7: color_b = 8'hFF;
                default: color_b = 8'hFF;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Cube edge table
    //
    // Front square: vertices 0, 1, 2, 3
    // Back square:  vertices 4, 5, 6, 7
    //
    // Edges:
    // 0-1, 1-2, 2-3, 3-0
    // 4-5, 5-6, 6-7, 7-4
    // 0-4, 1-5, 2-6, 3-7
    // ------------------------------------------------------------
    function automatic logic [2:0] edge_v0(input logic [3:0] edge_id);
        begin
            case (edge_id)
                4'd0:  edge_v0 = 3'd0;
                4'd1:  edge_v0 = 3'd1;
                4'd2:  edge_v0 = 3'd2;
                4'd3:  edge_v0 = 3'd3;
                4'd4:  edge_v0 = 3'd4;
                4'd5:  edge_v0 = 3'd5;
                4'd6:  edge_v0 = 3'd6;
                4'd7:  edge_v0 = 3'd7;
                4'd8:  edge_v0 = 3'd0;
                4'd9:  edge_v0 = 3'd1;
                4'd10: edge_v0 = 3'd2;
                4'd11: edge_v0 = 3'd3;
                default: edge_v0 = 3'd0;
            endcase
        end
    endfunction

    function automatic logic [2:0] edge_v1(input logic [3:0] edge_id);
        begin
            case (edge_id)
                4'd0:  edge_v1 = 3'd1;
                4'd1:  edge_v1 = 3'd2;
                4'd2:  edge_v1 = 3'd3;
                4'd3:  edge_v1 = 3'd0;
                4'd4:  edge_v1 = 3'd5;
                4'd5:  edge_v1 = 3'd6;
                4'd6:  edge_v1 = 3'd7;
                4'd7:  edge_v1 = 3'd4;
                4'd8:  edge_v1 = 3'd4;
                4'd9:  edge_v1 = 3'd5;
                4'd10: edge_v1 = 3'd6;
                4'd11: edge_v1 = 3'd7;
                default: edge_v1 = 3'd0;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Precomputed cube vertex X coordinates
    // 8 animation frames, 8 vertices per frame
    // ------------------------------------------------------------
    function automatic logic [7:0] cube_x(
        input logic [2:0] frame,
        input logic [2:0] vertex
    );
        begin
            case (frame)
                3'd0: begin
                    case (vertex)
                        3'd0: cube_x = 8'd28;
                        3'd1: cube_x = 8'd68;
                        3'd2: cube_x = 8'd68;
                        3'd3: cube_x = 8'd28;
                        3'd4: cube_x = 8'd38;
                        3'd5: cube_x = 8'd78;
                        3'd6: cube_x = 8'd78;
                        3'd7: cube_x = 8'd38;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd1: begin
                    case (vertex)
                        3'd0: cube_x = 8'd26;
                        3'd1: cube_x = 8'd62;
                        3'd2: cube_x = 8'd70;
                        3'd3: cube_x = 8'd34;
                        3'd4: cube_x = 8'd42;
                        3'd5: cube_x = 8'd76;
                        3'd6: cube_x = 8'd68;
                        3'd7: cube_x = 8'd36;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd2: begin
                    case (vertex)
                        3'd0: cube_x = 8'd30;
                        3'd1: cube_x = 8'd58;
                        3'd2: cube_x = 8'd74;
                        3'd3: cube_x = 8'd46;
                        3'd4: cube_x = 8'd38;
                        3'd5: cube_x = 8'd72;
                        3'd6: cube_x = 8'd66;
                        3'd7: cube_x = 8'd32;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd3: begin
                    case (vertex)
                        3'd0: cube_x = 8'd36;
                        3'd1: cube_x = 8'd58;
                        3'd2: cube_x = 8'd72;
                        3'd3: cube_x = 8'd50;
                        3'd4: cube_x = 8'd30;
                        3'd5: cube_x = 8'd66;
                        3'd6: cube_x = 8'd80;
                        3'd7: cube_x = 8'd44;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd4: begin
                    case (vertex)
                        3'd0: cube_x = 8'd38;
                        3'd1: cube_x = 8'd78;
                        3'd2: cube_x = 8'd78;
                        3'd3: cube_x = 8'd38;
                        3'd4: cube_x = 8'd28;
                        3'd5: cube_x = 8'd68;
                        3'd6: cube_x = 8'd68;
                        3'd7: cube_x = 8'd28;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd5: begin
                    case (vertex)
                        3'd0: cube_x = 8'd42;
                        3'd1: cube_x = 8'd76;
                        3'd2: cube_x = 8'd68;
                        3'd3: cube_x = 8'd36;
                        3'd4: cube_x = 8'd26;
                        3'd5: cube_x = 8'd62;
                        3'd6: cube_x = 8'd70;
                        3'd7: cube_x = 8'd34;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd6: begin
                    case (vertex)
                        3'd0: cube_x = 8'd38;
                        3'd1: cube_x = 8'd72;
                        3'd2: cube_x = 8'd66;
                        3'd3: cube_x = 8'd32;
                        3'd4: cube_x = 8'd30;
                        3'd5: cube_x = 8'd58;
                        3'd6: cube_x = 8'd74;
                        3'd7: cube_x = 8'd46;
                        default: cube_x = 8'd0;
                    endcase
                end

                3'd7: begin
                    case (vertex)
                        3'd0: cube_x = 8'd30;
                        3'd1: cube_x = 8'd66;
                        3'd2: cube_x = 8'd80;
                        3'd3: cube_x = 8'd44;
                        3'd4: cube_x = 8'd36;
                        3'd5: cube_x = 8'd58;
                        3'd6: cube_x = 8'd72;
                        3'd7: cube_x = 8'd50;
                        default: cube_x = 8'd0;
                    endcase
                end

                default: cube_x = 8'd48;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Precomputed cube vertex Y coordinates
    // ------------------------------------------------------------
    function automatic logic [7:0] cube_y(
        input logic [2:0] frame,
        input logic [2:0] vertex
    );
        begin
            case (frame)
                3'd0: begin
                    case (vertex)
                        3'd0: cube_y = 8'd16;
                        3'd1: cube_y = 8'd16;
                        3'd2: cube_y = 8'd56;
                        3'd3: cube_y = 8'd56;
                        3'd4: cube_y = 8'd8;
                        3'd5: cube_y = 8'd8;
                        3'd6: cube_y = 8'd48;
                        3'd7: cube_y = 8'd48;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd1: begin
                    case (vertex)
                        3'd0: cube_y = 8'd18;
                        3'd1: cube_y = 8'd12;
                        3'd2: cube_y = 8'd50;
                        3'd3: cube_y = 8'd58;
                        3'd4: cube_y = 8'd10;
                        3'd5: cube_y = 8'd18;
                        3'd6: cube_y = 8'd56;
                        3'd7: cube_y = 8'd46;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd2: begin
                    case (vertex)
                        3'd0: cube_y = 8'd20;
                        3'd1: cube_y = 8'd10;
                        3'd2: cube_y = 8'd44;
                        3'd3: cube_y = 8'd58;
                        3'd4: cube_y = 8'd8;
                        3'd5: cube_y = 8'd22;
                        3'd6: cube_y = 8'd58;
                        3'd7: cube_y = 8'd44;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd3: begin
                    case (vertex)
                        3'd0: cube_y = 8'd22;
                        3'd1: cube_y = 8'd12;
                        3'd2: cube_y = 8'd38;
                        3'd3: cube_y = 8'd56;
                        3'd4: cube_y = 8'd14;
                        3'd5: cube_y = 8'd20;
                        3'd6: cube_y = 8'd46;
                        3'd7: cube_y = 8'd54;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd4: begin
                    case (vertex)
                        3'd0: cube_y = 8'd16;
                        3'd1: cube_y = 8'd16;
                        3'd2: cube_y = 8'd56;
                        3'd3: cube_y = 8'd56;
                        3'd4: cube_y = 8'd8;
                        3'd5: cube_y = 8'd8;
                        3'd6: cube_y = 8'd48;
                        3'd7: cube_y = 8'd48;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd5: begin
                    case (vertex)
                        3'd0: cube_y = 8'd10;
                        3'd1: cube_y = 8'd18;
                        3'd2: cube_y = 8'd56;
                        3'd3: cube_y = 8'd46;
                        3'd4: cube_y = 8'd18;
                        3'd5: cube_y = 8'd12;
                        3'd6: cube_y = 8'd50;
                        3'd7: cube_y = 8'd58;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd6: begin
                    case (vertex)
                        3'd0: cube_y = 8'd8;
                        3'd1: cube_y = 8'd22;
                        3'd2: cube_y = 8'd58;
                        3'd3: cube_y = 8'd44;
                        3'd4: cube_y = 8'd20;
                        3'd5: cube_y = 8'd10;
                        3'd6: cube_y = 8'd44;
                        3'd7: cube_y = 8'd58;
                        default: cube_y = 8'd0;
                    endcase
                end

                3'd7: begin
                    case (vertex)
                        3'd0: cube_y = 8'd14;
                        3'd1: cube_y = 8'd20;
                        3'd2: cube_y = 8'd46;
                        3'd3: cube_y = 8'd54;
                        3'd4: cube_y = 8'd22;
                        3'd5: cube_y = 8'd12;
                        3'd6: cube_y = 8'd38;
                        3'd7: cube_y = 8'd56;
                        default: cube_y = 8'd0;
                    endcase
                end

                default: cube_y = 8'd32;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Draw-line command byte generator
    //
    // Command format:
    // 0x21, x0, y0, x1, y1, R, G, B
    // ------------------------------------------------------------
    function automatic logic [7:0] line_byte(
        input logic [3:0] edge_id,
        input logic [7:0] index,
        input logic [2:0] frame,
        input logic [2:0] color
    );
        logic [2:0] v0;
        logic [2:0] v1;
        begin
            v0 = edge_v0(edge_id);
            v1 = edge_v1(edge_id);

            case (index)
                8'd0: line_byte = CMD_DRAWLINE;
                8'd1: line_byte = cube_x(frame, v0);
                8'd2: line_byte = cube_y(frame, v0);
                8'd3: line_byte = cube_x(frame, v1);
                8'd4: line_byte = cube_y(frame, v1);
                8'd5: line_byte = color_r(color);
                8'd6: line_byte = color_g(color);
                8'd7: line_byte = color_b(color);
                default: line_byte = 8'h00;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Select current byte to transmit
    // ------------------------------------------------------------
    always_comb begin
        case (state)
            ST_SEND_INIT:       tx_data = init_byte(byte_index);
            ST_SEND_CLEAR:      tx_data = clear_byte(byte_index);
            ST_SEND_DISPLAY_ON: tx_data = CMD_DISPLAYON;
            ST_ANIM_CLEAR:      tx_data = clear_byte(byte_index);
            ST_DRAW_CUBE:       tx_data = line_byte(edge_index, byte_index, frame_index, color_index);
            default:            tx_data = 8'h00;
        endcase
    end

    // ------------------------------------------------------------
    // SPI transmitter
    //
    // Clock idles high.
    // Data changes while SCLK is low.
    // OLED samples data when SCLK rises.
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_state       <= SPI_IDLE;
            spi_shift       <= 8'h00;
            spi_bit_index   <= 3'd7;
            spi_div_counter <= 16'd0;
            spi_busy        <= 1'b0;
            spi_done        <= 1'b0;
            sclk            <= 1'b1;
            mosi            <= 1'b0;
        end else begin
            spi_done <= 1'b0;

            case (spi_state)

                SPI_IDLE: begin
                    sclk            <= 1'b1;
                    spi_div_counter <= 16'd0;
                    spi_bit_index   <= 3'd7;
                    spi_busy        <= 1'b0;

                    if (spi_start) begin
                        spi_shift <= tx_data;
                        mosi      <= tx_data[7];
                        spi_busy  <= 1'b1;
                        spi_state <= SPI_CLK_LOW;
                    end
                end

                SPI_CLK_LOW: begin
                    spi_busy <= 1'b1;

                    if (spi_div_counter == SPI_DIV - 1) begin
                        spi_div_counter <= 16'd0;
                        sclk            <= 1'b0;
                        spi_state       <= SPI_CLK_HIGH;
                    end else begin
                        spi_div_counter <= spi_div_counter + 1'b1;
                    end
                end

                SPI_CLK_HIGH: begin
                    spi_busy <= 1'b1;

                    if (spi_div_counter == SPI_DIV - 1) begin
                        spi_div_counter <= 16'd0;
                        sclk            <= 1'b1;

                        if (spi_bit_index == 3'd0) begin
                            spi_state <= SPI_DONE;
                        end else begin
                            spi_bit_index <= spi_bit_index - 1'b1;
                            mosi          <= spi_shift[spi_bit_index - 1'b1];
                            spi_state     <= SPI_CLK_LOW;
                        end
                    end else begin
                        spi_div_counter <= spi_div_counter + 1'b1;
                    end
                end

                SPI_DONE: begin
                    spi_busy  <= 1'b0;
                    spi_done  <= 1'b1;
                    spi_state <= SPI_IDLE;
                end

                default: begin
                    spi_state <= SPI_IDLE;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // Main OLED controller FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= ST_RESET;
            wait_counter <= 32'd0;
            byte_index   <= 8'd0;
            edge_index   <= 4'd0;
            frame_index  <= 3'd0;
            color_index  <= 3'd0;
            spi_start    <= 1'b0;

            rst_n        <= 1'b0;
            cs_n         <= 1'b1;
            DCEN         <= 1'b0;
            VCCEN        <= 1'b0;
            PMODEN       <= 1'b0;
        end else begin
            spi_start <= 1'b0;

            case (state)

                ST_RESET: begin
                    rst_n        <= 1'b0;
                    cs_n         <= 1'b1;
                    DCEN         <= 1'b0;
                    VCCEN        <= 1'b0;
                    PMODEN       <= 1'b0;
                    wait_counter <= 32'd0;
                    byte_index   <= 8'd0;
                    edge_index   <= 4'd0;
                    frame_index  <= 3'd0;
                    color_index  <= 3'd0;
                    state        <= ST_ENABLE_PMOD;
                end

                ST_ENABLE_PMOD: begin
                    PMODEN       <= 1'b1;
                    VCCEN        <= 1'b0;
                    rst_n        <= 1'b0;
                    wait_counter <= 32'd0;
                    state        <= ST_WAIT_PMOD;
                end

                ST_WAIT_PMOD: begin
                    if (wait_counter >= WAIT_20US_CYCLES) begin
                        wait_counter <= 32'd0;
                        state        <= ST_ASSERT_OLED_RESET;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                ST_ASSERT_OLED_RESET: begin
                    rst_n        <= 1'b0;
                    wait_counter <= 32'd0;
                    state        <= ST_WAIT_RESET_LOW;
                end

                ST_WAIT_RESET_LOW: begin
                    if (wait_counter >= WAIT_1MS_CYCLES) begin
                        wait_counter <= 32'd0;
                        state        <= ST_RELEASE_OLED_RESET;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                ST_RELEASE_OLED_RESET: begin
                    rst_n        <= 1'b1;
                    wait_counter <= 32'd0;
                    state        <= ST_WAIT_RESET_HIGH;
                end

                ST_WAIT_RESET_HIGH: begin
                    if (wait_counter >= WAIT_2MS_CYCLES) begin
                        wait_counter <= 32'd0;
                        byte_index   <= 8'd0;
                        state        <= ST_SEND_INIT;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                ST_SEND_INIT: begin
                    cs_n <= 1'b0;
                    DCEN <= 1'b0;

                    if (!spi_busy && !spi_done) begin
                        spi_start <= 1'b1;
                    end

                    if (spi_done) begin
                        if (byte_index == INIT_LEN - 1) begin
                            byte_index <= 8'd0;
                            cs_n       <= 1'b1;
                            state      <= ST_SEND_CLEAR;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end

                ST_SEND_CLEAR: begin
                    cs_n <= 1'b0;
                    DCEN <= 1'b0;

                    if (!spi_busy && !spi_done) begin
                        spi_start <= 1'b1;
                    end

                    if (spi_done) begin
                        if (byte_index == CLEAR_LEN - 1) begin
                            byte_index <= 8'd0;
                            cs_n       <= 1'b1;
                            state      <= ST_ENABLE_VCC;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end

                ST_ENABLE_VCC: begin
                    VCCEN        <= 1'b1;
                    wait_counter <= 32'd0;
                    state        <= ST_WAIT_VCC;
                end

                ST_WAIT_VCC: begin
                    if (wait_counter >= WAIT_100MS_CYCLES) begin
                        wait_counter <= 32'd0;
                        byte_index   <= 8'd0;
                        state        <= ST_SEND_DISPLAY_ON;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                ST_SEND_DISPLAY_ON: begin
                    cs_n <= 1'b0;
                    DCEN <= 1'b0;

                    if (!spi_busy && !spi_done) begin
                        spi_start <= 1'b1;
                    end

                    if (spi_done) begin
                        cs_n         <= 1'b1;
                        wait_counter <= 32'd0;
                        state        <= ST_WAIT_AFTER_ON;
                    end
                end

                ST_WAIT_AFTER_ON: begin
                    if (wait_counter >= WAIT_100MS_CYCLES) begin
                        wait_counter <= 32'd0;
                        byte_index   <= 8'd0;
                        edge_index   <= 4'd0;
                        state        <= ST_ANIM_CLEAR;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                ST_ANIM_CLEAR: begin
                    cs_n <= 1'b0;
                    DCEN <= 1'b0;

                    if (!spi_busy && !spi_done) begin
                        spi_start <= 1'b1;
                    end

                    if (spi_done) begin
                        if (byte_index == CLEAR_LEN - 1) begin
                            byte_index <= 8'd0;
                            edge_index <= 4'd0;
                            cs_n       <= 1'b1;
                            state      <= ST_DRAW_CUBE;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end

                ST_DRAW_CUBE: begin
                    cs_n <= 1'b0;
                    DCEN <= 1'b0;

                    if (!spi_busy && !spi_done) begin
                        spi_start <= 1'b1;
                    end

                    if (spi_done) begin
                        if (byte_index == LINE_LEN - 1) begin
                            byte_index <= 8'd0;

                            if (edge_index == NUM_EDGES - 1) begin
                                edge_index   <= 4'd0;
                                cs_n         <= 1'b1;
                                wait_counter <= 32'd0;
                                state        <= ST_FRAME_WAIT;
                            end else begin
                                edge_index <= edge_index + 1'b1;
                            end
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end

                ST_FRAME_WAIT: begin
                    cs_n <= 1'b1;
                    DCEN <= 1'b0;

                    if (wait_counter >= WAIT_50MS_CYCLES) begin
                        wait_counter <= 32'd0;

                        frame_index <= frame_index + 1'b1;
                        color_index <= color_index + 1'b1;

                        byte_index <= 8'd0;
                        edge_index <= 4'd0;
                        state      <= ST_ANIM_CLEAR;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                default: begin
                    state <= ST_RESET;
                end

            endcase
        end
    end

endmodule