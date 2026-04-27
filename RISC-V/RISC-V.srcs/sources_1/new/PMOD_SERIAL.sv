`timescale 1ns / 1ps

module PMOD_SERIAL #(
    parameter int CLK_FREQ_HZ = 100_000_000
    parameter int SPI_CLK_DIV = 32
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

typedef enum logic [4:0] {
    OLED_ST_RESET,
    OLED_ST_PWR_UP,
    OLED_ST_RST_PULSE,
    OLED_ST_INIT_DLY,
    OLED_ST_UNLOCK,
    OLED_ST_SHUTDOWN,
    OLED_ST_IDLE

} oled_state_t;

oled_state_t oled_state_cur, oled_state_nxt;

typedef enum logic [2:0] {
    SPI_ST_RESET,
    SPI_ST_IDLE,
    SPI_ST_START,
    SPI_ST_LOAD,
    SPI_ST_TRANSFER,
    SPI_ST_STOP
  } spi_state_t;

spi_state_t spi_state_cur, spi_state_nxt;

logic[31:0] clk_div_cnt;
logic[7:0] spi_payload_1, spi_payload_2;
logic[2:0] spi_bit_cnt;
logic spi_busy, spi_done;

logic spi_start, spi_cmd_data, spi_init, spi_ack;


logic [31:0] delay_cnt;
logic [31:0] delay_tgt;
logic delay_done;
logic delay_busy;

logic delay_en;
logic delay_ack;
logic [31:0] delay_value;

localparam int  WAIT20US = 20 * CLK_FREQ_HZ / 1_000_000;
localparam int  WAIT50MS = 50 * CLK_FREQ_HZ / 1_000;
localparam int  SCLK_PERIOD = SPI_CLK_DIV / CLK_FREQ_HZ * 1000000000; // 320ns 

always_ff @(posedge clk ) begin

    if(rst) begin
        delay_cnt <= 32'd0;
        delay_tgt <= 32'd0;
        delay_busy <= 1'b0;
        delay_done <= 1'b0;
    end else if (delay_en && !delay_busy && !delay_done) begin
        delay_busy <= 1'b1;
        delay_tgt <= delay_value;
        delay_cnt <= 32'd0;

    end else if (delay_busy && !delay_done) begin
        if (delay_cnt >= delay_tgt) begin
            delay_done <= 1'b1;
            delay_busy <= 1'b0;
        end else begin
            delay_cnt <= delay_cnt + 32'd1;
        end

    end else if (delay_ack && delay_done) begin
        delay_cnt <= 32'd0;
        delay_tgt <= 32'd0;
        delay_done <= 1'b0;
    end
end




/// OLED State Machine /// 


always_ff @(posedge clk ) begin
    if(rst) begin
        oled_state_cur <= OLED_ST_RESET;
    end

    else begin
        oled_state_cur <= oled_state_nxt;
    end
end

always_comb begin

    oled_state_nxt = oled_state_cur;

    rst_n = 1'b1;
    VCCEN = 1'b0;
    PMODEN = 1'b0;

    spi_reset = 1'b0;
    spi_init = 1'b0;
    spi_start = 1'b0;
    spi_cmd_data = 1'b0;


    delay_en = 1'b0;
    delay_value = 32'd0;
    delay_ack = 1'b0;

    case(oled_state_cur)
        OLED_ST_RESET: begin
            rst_n = 1'b1;
            VCCEN = 1'b0;
            PMODEN = 1'b0;

            spi_reset = 1'b1;
            spi_init = 1'b0;
            spi_start = 1'b0;
            spi_cmd_data = 1'b0;


            delay_en = 1'b0;
            delay_value = 32'd0;
            delay_ack = 1'b0;

            oled_state_nxt = OLED_ST_PWR_UP;
        end

        OLED_ST_PWR_UP: begin
            PMODEN = 1'b1;
            delay_en = 1'b1;
            delay_value = WAIT20US;

            if(delay_done) begin
                delay_en = 1'b0;
                delay_ack = 1'b1;
                oled_state_nxt = OLED_ST_RST_PULSE;
            end
        end

        OLED_ST_RST_PULSE: begin
            rst_n = 1'b0;
            delay_ack = 1'b0;
            delay_en = 1'b1;
            delay_value = WAIT20US;
            if(delay_done) begin
                delay_en = 1'b0;
                delay_ack = 1'b1;
                rst_n = 1'b1;
                oled_state_nxt = OLED_ST_INIT_DLY;
            end
        end

        OLED_ST_INIT_DLY: begin
            delay_en = 1'b1;
            delay_ack = 1'b0;
            delay_value = WAIT20US;
            
            if(delay_done) begin
                delay_ack = 1'b1;
                oled_state_nxt = OLED_ST_UNLOCK;
            end
        end

        OLED_ST_UNLOCK: begin
            spi_cmd_data = 1'b1;
            spi_two_byte = 1'b1;
            spi_start = 1'b1;

            spi_payload_1 = 8'hFD; // Command Lock
            spi_payload_2 = 8'h12; // Unlock OLED driver IC command set

            if(spi_2_done) begin
                spi_start = 1'b0;
                oled_state_nxt = OLED_ST_IDLE;
            end
        end
    endcase
    
end

/// SPI State Machine /// 

always_ff @(posedge clk ) begin
    if(rst || spi_reset) begin
        spi_state_cur <= SPI_ST_RESET;
    end

    else begin
        spi_state_cur <= spi_state_nxt;
    end
end


always_comb begin

    spi_state_nxt = spi_state_cur;

    sclk = 1'b1; //SPI MODE 3, CLK idles high
    mosi = 1'b0;
    cs_n = 1'b1;
    DCEN = 1'b0;

    spi_busy = 1'b0;
    spi_done = 1'b0;

    spi_bit_cnt = 3'd0;
    clk_div_cnt = 32'd0;

    case(spi_state_cur)
        SPI_ST_IDLE: begin

            sclk = 1'b1; //SPI MODE 3, CLK idles high
            mosi = 1'b0;
            cs_n = 1'b1;
            DCEN = 1'b0;

            spi_busy = 1'b0;
            spi_busy = 1'b0;
            spi_1_done = 1'b0;
            spi_2_done = 1'b0;

            spi_bit_cnt = 3'd0;
            clk_div_cnt = 32'd0;



            if(spi_start) begin
                spi_state_nxt = SPI_ST_RISING_EDGE;
            end
        end

        SPI_ST_SCLK_POS: begin
        end 

        SPI_ST__SCLK_NEG: begin
        end

        SPI_SI_STOP: begin
            
        end
    endcase
end

endmodule