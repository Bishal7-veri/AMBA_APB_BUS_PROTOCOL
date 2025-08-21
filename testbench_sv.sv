
interface apb_if(input logic pclk);
  logic         presetn;
  logic         psel;
  logic         penable;
  logic [7:0]   paddr;
  logic         pwrite;
  logic [31:0]  pwdata;
  logic [31:0]  prdata;
  logic         pready;
  logic         pslverr;

  modport drv_mp (input pclk, pready, prdata,
                  output presetn, psel, penable, paddr, pwrite, pwdata);

  modport mon_mp (input pclk, presetn, psel, penable, paddr, pwrite, pwdata, prdata, pready, pslverr);
endinterface

class apb_transaction;
  rand bit [7:0]   addr;
  rand bit [31:0]  data;
  rand bit         write;      
       bit [31:0]  read_data;  

  constraint c_addr { addr inside {[0:31]}; }

  function void display(string tag);
    $display("[%s] addr=%0d write=%0b data=0x%08h read_data=0x%08h",
              tag, addr, write, data, read_data);
  endfunction
endclass

class generator;
  mailbox #(apb_transaction) gen2drv;

  function new(mailbox #(apb_transaction) gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task run();
    apb_transaction tr;

    for (int i = 0; i < 8; i++) begin
      tr = new();
      assert(tr.randomize() with { write == 1; addr == i; }); 
      tr.data = 32'hA0A0_0000 + i;
      gen2drv.put(tr);
      tr.display("GEN");
    end

    for (int i = 0; i < 8; i++) begin
      tr = new();
      assert(tr.randomize() with { write == 0; addr == i; });
      gen2drv.put(tr);
      tr.display("GEN");
    end

    for (int i = 0; i < 8; i++) begin
      tr = new();
      assert(tr.randomize());
      gen2drv.put(tr);
      tr.display("GEN");
    end
  endtask
endclass

class driver;
  virtual apb_if vif;
  mailbox #(apb_transaction) gen2drv;

  function new(virtual apb_if vif, mailbox #(apb_transaction) gen2drv);
    this.vif     = vif;
    this.gen2drv = gen2drv;
  endfunction

  task apb_write(apb_transaction tr);
    @(posedge vif.pclk);
    vif.paddr   <= tr.addr;
    vif.pwrite  <= 1'b1;
    vif.pwdata  <= tr.data;
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;

    @(posedge vif.pclk);
    vif.penable <= 1'b1;

    wait(vif.pready == 1'b1);

    @(posedge vif.pclk);
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
  endtask

  task apb_read(apb_transaction tr);
    @(posedge vif.pclk);
    vif.paddr   <= tr.addr;
    vif.pwrite  <= 1'b0;
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;

    @(posedge vif.pclk);
    vif.penable <= 1'b1;

    wait(vif.pready == 1'b1);

    @(posedge vif.pclk);
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
  endtask

  task run();
    apb_transaction tr;
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
    vif.paddr   <= '0;
    vif.pwdata  <= '0;

    forever begin
      gen2drv.get(tr);
      if (tr.write) apb_write(tr);
      else          apb_read(tr);
    end
  endtask
endclass

class monitor;
  virtual apb_if.mon_mp vif;
  mailbox #(apb_transaction) mon2scb;

  function new(virtual apb_if.mon_mp vif, mailbox #(apb_transaction) mon2scb);
    this.vif     = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    apb_transaction tr;

    forever begin
     
      @(posedge vif.pclk);
      if (vif.psel && !vif.penable) begin
        tr = new();
        tr.addr  = vif.paddr;
        tr.write = vif.pwrite;
        tr.data  = vif.pwdata; 

       
        @(posedge vif.pclk);
        if (vif.penable) begin
          
          wait (vif.pready == 1'b1);

          if (!tr.write) tr.read_data = vif.prdata;
          else           tr.read_data = '0;

          mon2scb.put(tr);
          tr.display("MON");
        end
      end
    end
  endtask
endclass


class scoreboard;
  mailbox #(apb_transaction) mon2scb;

  bit        has_written [byte];    
  bit [31:0] mem_model  [byte];     

  function new(mailbox #(apb_transaction) mon2scb);
    this.mon2scb = mon2scb;
  endfunction

  task run();
    apb_transaction tr;
    forever begin
      mon2scb.get(tr);

      if (tr.write) begin
        mem_model[tr.addr]  = tr.data;
        has_written[tr.addr]= 1'b1;
        $display("[SCB] WRITE stored: Addr=%0d Data=0x%08h", tr.addr, tr.data);
      end
      else begin
        if (!has_written.exists(tr.addr) || !has_written[tr.addr]) begin
          $display("[SCB][INFO] Read @%0d before any write: Observed=0x%08h (no check)",
                   tr.addr, tr.read_data);
        end else begin
          if (tr.read_data !== mem_model[tr.addr]) begin
            $display("[SCB][ERROR] Addr=%0d Expected=0x%08h Got=0x%08h",
                     tr.addr, mem_model[tr.addr], tr.read_data);
          end else begin
            $display("[SCB][OK] Addr=%0d Data=0x%08h", tr.addr, tr.read_data);
          end
        end
      end
    end
  endtask
endclass

class environment;
  generator  gen;
  driver     drv;
  monitor    mon;
  scoreboard scb;

  mailbox #(apb_transaction) gen2drv;
  mailbox #(apb_transaction) mon2scb;

  virtual apb_if vif;

  function new(virtual apb_if vif);
    this.vif = vif;

    gen2drv = new();
    mon2scb = new();

    gen = new(gen2drv);
    drv = new(vif, gen2drv);
    mon = new(vif, mon2scb);
    scb = new(mon2scb);
  endfunction

  task run();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_none
  endtask
endclass


module apb_master_tb;

  localparam ADDR_WIDTH = 8;
  localparam DATA_WIDTH = 32;

 
  logic pclk;
  initial begin
    pclk = 0;
    forever #5 pclk = ~pclk; 
  end


  apb_if apb(pclk);

 
  apb_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_DEPTH(256),
    .WAIT_STATES(0) 
  ) dut (
    .pclk    (pclk),
    .presetn (apb.presetn),
    .psel    (apb.psel),
    .penable (apb.penable),
    .paddr   (apb.paddr),
    .pwrite  (apb.pwrite),
    .pwdata  (apb.pwdata),
    .prdata  (apb.prdata),
    .pready  (apb.pready),
    .pslverr (apb.pslverr)
  );

  
  environment env;

  
  initial begin
   
    $dumpfile("apb_env.vcd");
    $dumpvars(0, apb_master_tb);

   
    apb.presetn = 0;
    apb.psel    = 0;
    apb.penable = 0;
    apb.pwrite  = 0;
    apb.paddr   = '0;
    apb.pwdata  = '0;

    #25;
    apb.presetn = 1;

   
    env = new(apb);
    env.run();

    #2000;
    $display("Simulation complete via $finish");
    $finish;
  end

endmodule
