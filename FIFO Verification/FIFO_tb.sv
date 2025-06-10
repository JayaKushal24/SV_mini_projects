/////////////////////////////transaction
class transaction;
  rand bit op;
  bit rd,wr;
  bit [7:0]data_in;
  bit full,empty;
  bit [7:0]data_out;

  constraint oper_ctrl {    op dist {1 := 50 , 0 := 50};    }
endclass

/////////////////////////////interface

interface fifo_if;
  logic clock,rd,wr;
  logic full,empty;
  logic [7:0]data_in;
  logic [7:0]data_out;
  logic rst;
endinterface

///////////////////////////////////////generator

class generator;
      transaction t1;
      mailbox #(transaction) mbx;
      int count=0;
      int i=0;
      event next;
      event done;
      function new(mailbox #(transaction) mbx);
            this.mbx=mbx;
            t1=new();
      endfunction;
      task run();
            repeat(count) begin
              if (!t1.randomize) $error("Randomization failed");
              else begin
                i++;
                mbx.put(t1);
                $display("[GEN] : Op : %0d iteration : %0d",t1.op,i);
              end
              @(next);
            end
            ->done;
      endtask
endclass

///////////////////////////////driver
class driver;
      virtual fifo_if vif;
      mailbox #(transaction)mbx;
      transaction t1;
      function new(mailbox #(transaction)mbx);
            this.mbx = mbx;
      endfunction;
    
      task reset();
            vif.rst<=1'b1;
            vif.rd<=1'b0;
            vif.wr<=1'b0;
            vif.data_in<=0;
            repeat (5) @(posedge vif.clock);
            vif.rst<=1'b0;
            $display("[DRV] : DUT Reset Done");
      endtask
    
      task write();
            @(posedge vif.clock);
            vif.rst<=1'b0;
            vif.rd<=1'b0;
            vif.wr<=1'b1;
            vif.data_in<=$urandom_range(1, 10);
            @(posedge vif.clock);
            vif.wr<=1'b0;
            $display("[DRV] : DATA WRITE  data : %0d ",vif.data_in);
            @(posedge vif.clock);
      endtask
    
      task read();
            @(posedge vif.clock);
            vif.rst<=1'b0;
            vif.rd<=1'b1;
            vif.wr<=1'b0;
            @(posedge vif.clock);
            vif.rd<=1'b0;
            $display("[DRV] : DATA READ");
            @(posedge vif.clock);
      endtask
    
      task run();
            forever begin
              mbx.get(t1);
              if (t1.op==1'b1) write();
              else read();
            end
      endtask
endclass

//////////////////////////////monitor


class monitor;
      virtual fifo_if vif;
      mailbox #(transaction)mbx;
      transaction t2;
    
      function new(mailbox #(transaction)mbx);
            this.mbx=mbx;
      endfunction;
    
      task run();
            t2 = new();
            forever begin
              repeat (2)@(posedge vif.clock);
              t2.wr=vif.wr;
              t2.rd=vif.rd;
              t2.data_in=vif.data_in;
              t2.full=vif.full;
              t2.empty=vif.empty;
              @(posedge vif.clock);
              t2.data_out=vif.data_out;
              mbx.put(t2);
              $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d",t2.wr,t2.rd,t2.data_in,t2.data_out,t2.full,t2.empty);
            end
      endtask
endclass

////////////////////////////scoreboard

class scoreboard;
  mailbox #(transaction)mbx;
  transaction t2;
  event next;
  bit [7:0]din[$];//queue
  bit [7:0]temp;
  function new(mailbox #(transaction)mbx);
    this.mbx=mbx;
  endfunction;
  task run();
    forever begin
      mbx.get(t2);
      $display("[SCO] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d",t2.wr,t2.rd,t2.data_in,t2.data_out,t2.full,t2.empty);

      if (t2.wr == 1'b1) begin
        if (t2.full == 1'b0) begin
          din.push_front(t2.data_in);
          $display("[SCO] : DATA STORED IN QUEUE :%0d",t2.data_in);
        end else begin
          $display("[SCO] : FIFO is full");
        end
        $display("--------------------------------------");
      end

      if (t2.rd==1'b1) begin
        if (t2.empty==1'b0) begin
          temp=din.pop_back();
          if (t2.data_out==temp)
            $display("[SCO] : DATA MATCH");
          else
            $error("[SCO] : DATA MISMATCH");
        end else begin
          $display("[SCO] : FIFO IS EMPTY");
        end
        $display("--------------------------------------");
      end
      ->next;
    end
  endtask
  
  
endclass

///////////////////////////////testbench

module FIFO_tb;
  fifo_if vif();//interface
  
  initial begin
    vif.clock = 0;
    forever #5 vif.clock = ~vif.clock;//clock
  end
//link DUT
  FIFO dut (.clk(vif.clock),.rst(vif.rst),.wr(vif.wr),.rd(vif.rd),.din(vif.data_in),.dout(vif.data_out),.full(vif.full),.empty(vif.empty));

  mailbox #(transaction)mbx_gen_drv=new();//initializing mailboxes
  mailbox #(transaction)mbx_mon_sco=new();
  event next;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;

  initial begin
    gen=new(mbx_gen_drv);//connecting mailboxes
    drv=new(mbx_gen_drv);
    mon=new(mbx_mon_sco);
    sco=new(mbx_mon_sco);

    drv.vif=vif;//connecting interface
    mon.vif=vif;
    
    gen.next=next;//connecting events
    sco.next=next;
    
    gen.count=20;
    drv.reset();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
    wait(gen.done.triggered);
    $finish();
  end

endmodule
