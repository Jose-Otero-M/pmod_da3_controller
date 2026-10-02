module pmod_da3_controller #(
    parameter integer CLK_FREQ_HZ  = 100_000_000,
    parameter integer SCLK_FREQ_HZ = 25_000_000
)(
    input  wire               clk,
    input  wire               rst,

    // Input sample
    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,

    // Status
    output wire               sample_ready,
    output reg                sample_done,
    output reg                busy,

    // Pmod DA3 interface
    output reg                dac_cs_n,
    output reg                dac_din,
    output wire               dac_ldac_n,
    output reg                dac_sclk
);

    // -------------------------------------------------------------------------
    // Clock divider
    //
    // SCLK toggles every HALF_PERIOD_CLKS system clock cycles.
    //
    // For:
    //   CLK_FREQ_HZ  = 100 MHz
    //   SCLK_FREQ_HZ = 25 MHz
    //
    // HALF_PERIOD_CLKS = 2
    // -------------------------------------------------------------------------

    localparam integer HALF_PERIOD_CLKS =
        CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ);

    localparam integer DIV_W =
        (HALF_PERIOD_CLKS <= 1) ? 1 : $clog2(HALF_PERIOD_CLKS);

    reg [DIV_W-1:0] clk_count;

    // -------------------------------------------------------------------------
    // Serial transmission registers
    // -------------------------------------------------------------------------

    reg [15:0] tx_word;
    reg [4:0]  bit_index;

    // -------------------------------------------------------------------------
    // Convert signed Q1.15 two's complement into unsigned offset binary.
    //
    // Q1.15:
    //     0x8000 -> -1.000000
    //     0x0000 ->  0.000000
    //     0x7FFF -> +0.999969
    //
    // DAC code:
    //     0x0000 -> 0 V
    //     0x8000 -> VREF/2
    //     0xFFFF -> approximately VREF
    //
    // For 16-bit two's complement, offset-binary conversion only requires
    // inversion of the MSB.
    // -------------------------------------------------------------------------

    wire [15:0] dac_code;

    assign dac_code = {
        ~sample_in[15],
         sample_in[14:0]
    };

    // -------------------------------------------------------------------------
    // Ready status
    // -------------------------------------------------------------------------

    assign sample_ready = ~busy;

    // -------------------------------------------------------------------------
    // LDAC
    //
    // The AD5541A allows LDAC to remain low. In this configuration the DAC
    // output is updated when CS returns high after the 16-bit transmission.
    //
    // This simplifies the interface and makes the update deterministic.
    // -------------------------------------------------------------------------

    assign dac_ldac_n = 1'b0;

    // -------------------------------------------------------------------------
    // Serial transmitter
    //
    // SPI Mode 0:
    //     CPOL = 0
    //     CPHA = 0
    //
    // Data is presented before the rising edge of SCLK.
    // The AD5541A captures DIN on the rising edge.
    // -------------------------------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            clk_count   <= {DIV_W{1'b0}};
            tx_word     <= 16'd0;
            bit_index   <= 5'd15;

            dac_cs_n    <= 1'b1;
            dac_din     <= 1'b0;
            dac_sclk    <= 1'b0;

            busy        <= 1'b0;
            sample_done <= 1'b0;

        end else begin

            // Default value: one-clock pulse when a transfer finishes
            sample_done <= 1'b0;

            // IDLE
            if (!busy) begin

                dac_cs_n  <= 1'b1;
                dac_sclk  <= 1'b0;
                clk_count <= {DIV_W{1'b0}};

                if (sample_valid) begin

                    tx_word <= dac_code; // Store the complete DAC word

                    dac_din <= dac_code[15]; // SPI sends MSB first

                    bit_index <= 5'd15;

                    // Start transaction
                    dac_cs_n <= 1'b0;
                    busy     <= 1'b1;

                end

            end

            // TRANSFER

            else begin

                if (clk_count == HALF_PERIOD_CLKS - 1) begin

                    clk_count <= {DIV_W{1'b0}};

                    // -----------------------------------------------------
                    // Rising edge of SCLK
                    //
                    // DAC samples DIN here.
                    // -----------------------------------------------------

                    if (dac_sclk == 1'b0) begin

                        dac_sclk <= 1'b1;

                    end

                    // -----------------------------------------------------
                    // Falling edge of SCLK
                    //
                    // Prepare next bit.
                    // -----------------------------------------------------

                    else begin

                        dac_sclk <= 1'b0;

                        if (bit_index == 0) begin

                            // All 16 bits have been transmitted.
                            // CS rising edge updates the DAC because
                            // LDAC is held low.
                            dac_cs_n <= 1'b1;

                            busy        <= 1'b0;
                            sample_done <= 1'b1;

                        end else begin

                            bit_index <= bit_index - 1'b1;

                            // Prepare next bit before next rising SCLK edge
                            dac_din <= tx_word[bit_index - 1'b1];

                        end

                    end

                end else begin

                    clk_count <= clk_count + 1'b1;

                end

            end

        end

    end

endmodule