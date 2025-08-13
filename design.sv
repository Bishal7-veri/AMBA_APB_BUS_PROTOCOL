// Code your design here
// apb_slave.v
// Simple AMBA APB3 slave peripheral with a small RAM.
// - Latches address & pwrite in SETUP
// - In ACCESS it optionally waits (WAIT_STATES) before asserting pready
// - Performs write when pwrite==1 and pready==1
// - Drives prdata for reads when pready==1
// - Drives pslverr = 0 (no error) by default

module apb_slave #(
    parameter ADDR_WIDTH = 8,          // address width (bytes/words based on ALIGN)
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 256,        // number of words
    parameter WAIT_STATES = 0          // 0 => single-cycle ACCESS, >0 => wait cycles
) (
    input  wire                   pclk,
    input  wire                   presetn,
    input  wire                   psel,
    input  wire                   penable,
    input  wire [ADDR_WIDTH-1:0]  paddr,
    input  wire                   pwrite,
    input  wire [DATA_WIDTH-1:0]  pwdata,
    output reg  [DATA_WIDTH-1:0]  prdata,
    output reg                    pready,
    output reg                    pslverr
);

    // FSM states
    localparam IDLE   = 2'b00;
    localparam SETUP  = 2'b01;
    localparam ACCESS = 2'b10;

    reg [1:0] current_state, next_state;

    // latched control from SETUP
    reg [ADDR_WIDTH-1:0] lat_addr;
    reg                  lat_pwrite;

    // wait counter for ACCESS wait-states
    integer wait_cnt;

    // memory (simple synchronous RAM)
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // ----------------------
    // Next-state (combinational)
    // ----------------------
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (psel)
                    next_state = SETUP;
                else
                    next_state = IDLE;
            end

            SETUP: begin
                // spec: SETUP lasts one cycle, next cycle master must assert penable
                next_state = ACCESS;
            end

            ACCESS: begin
                // stay in ACCESS until slave indicates ready (pready==1)
                // but APB master will sample pready; slave decides when to go back to IDLE
                if (pready)
                    next_state = IDLE;
                else
                    next_state = ACCESS;
            end

            default: next_state = IDLE;
        endcase
    end

    // ----------------------
    // State register
    // ----------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ----------------------
    // Latch address/control in SETUP, handle ACCESS behavior
    // ----------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            lat_addr  <= {ADDR_WIDTH{1'b0}};
            lat_pwrite <= 1'b0;
            pready    <= 1'b0;
            prdata    <= {DATA_WIDTH{1'b0}};
            pslverr   <= 1'b0;
            wait_cnt  <= 0;
        end else begin
            // default outputs
            pslverr <= 1'b0;

            case (current_state)
                IDLE: begin
                    pready <= 1'b0;
                    wait_cnt <= 0;
                end

                SETUP: begin
                    // latch address & direction in SETUP phase (APB timing rule)
                    lat_addr   <= paddr;
                    lat_pwrite <= pwrite;
                    pready <= 1'b0;
                    wait_cnt <= WAIT_STATES;
                end

                ACCESS: begin
                    // On ACCESS, master will assert penable. Slave may delay using WAIT_STATES.
                    if (wait_cnt > 0) begin
                        // still waiting; not yet ready
                        pready <= 1'b0;
                        wait_cnt <= wait_cnt - 1;
                    end else begin
                        // ready to complete transfer
                        pready <= 1'b1;

                        if (lat_pwrite) begin
                            // WRITE: pwdata is valid during ACCESS - write to memory
                            // Note: we use lat_addr as index; user must ensure addressing fits MEM_DEPTH
                            if (lat_addr < MEM_DEPTH)
                                mem[lat_addr] <= pwdata;
                            else
                                pslverr <= 1'b1;
                        end else begin
                            // READ: drive prdata (make it available when pready asserted)
                            if (lat_addr < MEM_DEPTH)
                                prdata <= mem[lat_addr];
                            else begin
                                prdata <= {DATA_WIDTH{1'b0}};
                                pslverr <= 1'b1;
                            end
                        end
                    end
                end

                default: begin
                    pready <= 1'b0;
                end
            endcase
        end
    end

endmodule
