`timescale 1ns / 1ps

/////////////////////////////////////transaction
class transaction;
    rand bit din;
    bit dout;

    function transaction copy(); //deep copy
        copy=new();
        copy.din=this.din;
        copy.dout=this.dout;
    endfunction

    function void display();
        $display("Input : %b and Output : %b", din, dout);
    endfunction
endclass

////////////////////////////////////generator
class generator;
    transaction t1;
    mailbox #(transaction)mbx_gen_drv;
    mailbox #(transaction)mbx_gen_sco;
    event done;
    event next;
    int count;

    function new(mailbox #(transaction)mbx_gen_drv, mailbox #(transaction)mbx_gen_sco);
        t1 = new();
        this.mbx_gen_drv=mbx_gen_drv;
        this.mbx_gen_sco=mbx_gen_sco; // for golden data cmp
    endfunction

    task run();
        repeat(count) begin
            if (!t1.randomize)
                $error("randomization failed..simulation stopped");
            else begin
                mbx_gen_drv.put(t1.copy);
                mbx_gen_sco.put(t1.copy);
                $display("Generator: val generated and sent: din=%b",t1.din);
                @(next);
                $display("Generator: received next event, generating next...");
            end
        end
        ->done;
    endtask
endclass

///////////////////////////////////interface
interface dff_interface;
    logic clk;
    logic rst;
    logic din;
    logic dout;
endinterface

//////////////////////// driver
class driver;
    transaction t1;
    virtual dff_interface vif;
    mailbox #(transaction)mbx_gen_drv;

    function new(mailbox #(transaction)mbx_gen_drv);
        this.mbx_gen_drv=mbx_gen_drv;
    endfunction

    task run();
        forever begin
            mbx_gen_drv.get(t1);
            vif.din<=t1.din;
            $display("Driver: signal sent to DUT: din=%b", t1.din);
        end
    endtask
endclass


////////////////////////monitor
class monitor;
    transaction t1;
    mailbox #(transaction)mbx_mon_sco;
    virtual dff_interface vif;

    function new(mailbox #(transaction)mbx_mon_sco);
        this.mbx_mon_sco=mbx_mon_sco;
    endfunction

    task run();
    t1=new();
    forever begin
        @(posedge vif.clk);
        t1.din=vif.din;
        @(posedge vif.clk);
        t1.dout=vif.dout;
        mbx_mon_sco.put(t1);
        $display("Monitor: data sent to scoreboard: din=%b dout=%b",t1.din,t1.dout);
    end
endtask
endclass

///////////////////////////////scoreboard

class scoreboard;
    transaction t1,t2;
    mailbox #(transaction)mbx_gen_sco;
    mailbox #(transaction)mbx_mon_sco;
    event next;

    function new(mailbox #(transaction)mbx_gen_sco, mailbox #(transaction)mbx_mon_sco);
        this.mbx_gen_sco=mbx_gen_sco;
        this.mbx_mon_sco=mbx_mon_sco;
    endfunction

    task run();
        forever begin
            mbx_gen_sco.get(t1);
            $display("Scoreboard: got golden data: din=%b",t1.din);
            mbx_mon_sco.get(t2);
            $display("Scoreboard: got monitored data: dout=%b",t2.dout);

            if (t2.dout == t1.din)
                $display("Scoreboard: data matched");
            else
                $display("Scoreboard: data not matched... Expected: %b Got: %b",t1.din,t2.dout);
            $display("----------------------------------------------");
            ->next;
            $display("Scoreboard: triggered next event");
        end
    endtask
endclass

///////////////////////////////////testbench

module DFF_tb;
    dff_interface vif();

    DFF dut (.clk(vif.clk),.rst(vif.rst),.din(vif.din),.dout(vif.dout));

    mailbox #(transaction)mbx_gen_drv =new();
    mailbox #(transaction)mbx_gen_sco =new();
    mailbox #(transaction)mbx_mon_sco =new();

    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    initial begin
        vif.clk=0;
        forever #5 vif.clk = ~vif.clk;
    end

    initial begin
        vif.rst=1;
        vif.din=0;
        repeat(2) @(posedge vif.clk);
        vif.rst=0;
    end

    initial begin
        gen=new(mbx_gen_drv,mbx_gen_sco);
        drv=new(mbx_gen_drv);
        mon=new(mbx_mon_sco);
        sco=new(mbx_gen_sco, mbx_mon_sco);
        drv.vif=vif;
        mon.vif=vif;
        gen.next=sco.next;

        gen.count=20;

        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
        wait(gen.done.triggered);
        
        $display("Test completed ");
        $finish;
    end

endmodule
