`timescale 1ns/1ps

module apb_master_tb;

    // Parameters must match slave
    parameter ADDR_WIDTH = 8;
    parameter DATA_WIDTH = 32;

    reg pclk;
    reg presetn;

    // APB wires
    reg                    psel;
    reg                    penable;
    reg [ADDR_WIDTH-1:0]   paddr;
    reg                    pwrite;
    reg [DATA_WIDTH-1:0]   pwdata;
    wire [DATA_WIDTH-1:0]  prdata;
    wire                   pready;
    wire                   pslverr;

    // Instantiate slave
    apb_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(256),
        .WAIT_STATES(0)   // no wait states for simplicity
    ) dut (
        .pclk(pclk),
        .presetn(presetn),
        .psel(psel),
        .penable(penable),
        .paddr(paddr),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr)
    );

    // Clock generation: 100MHz
    initial begin
        pclk = 0;
        forever #5 pclk = ~pclk;
    end

    // APB Master Tasks
    task apb_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
    begin
        // SETUP phase
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b1;
        pwdata  <= data;
        psel    <= 1'b1;
        penable <= 1'b0;

        // ACCESS phase
        @(posedge pclk);
        penable <= 1'b1;

        // Wait until slave ready
        wait(pready == 1'b1);

        // Complete transfer
        @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    end
    endtask

    task apb_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
    begin
        // SETUP phase
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b0;
        psel    <= 1'b1;
        penable <= 1'b0;

        // ACCESS phase
        @(posedge pclk);
        penable <= 1'b1;

        // Wait until slave ready
        wait(pready == 1'b1);
        data = prdata;  // capture data when ready

        // Complete transfer
        @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
    end
    endtask

    // Test Sequence
    integer i;
    reg [DATA_WIDTH-1:0] read_data;

    initial begin
        // Initialize
        psel = 0;
        penable = 0;
        paddr = 0;
        pwrite = 0;
        pwdata = 0;
        presetn = 0;
        #20;
        presetn = 1;

        $display("\n===== Starting APB Write/Read Test =====");

        // WRITE multiple values
      for (i = 0; i < 15; i = i + 1) begin
            apb_write(i, 32'hA0A0_0000 + i);
            $display("WRITE: Addr=%0d Data=0x%08h", i, 32'hA0A0_0000 + i);
         apb_read(i, read_data);
            $display("READ : Addr=%0d Data=0x%08h", i, read_data);
        end
      

    

        $display("===== Test Completed =====\n");
        $stop;
    end

endmodule
