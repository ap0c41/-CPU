`timescale 1ns / 1ps
module tb_cpu_simple();
    reg clk;
    reg rst;
    reg en;
    wire [31:0] pc;
    wire [31:0] next_pc;
    wire [4:0]  rs_addr, rt_addr;
    wire [31:0] rs_data, rt_data;
    wire [31:0] alu_result, wb_data;
    wire        rt_wr_flag;
    processor_core cpu_inst(
        .sys_clk        (clk),
        .sys_rst        (rst),
        .exec_enable    (en),
        .program_counter(pc),
        .next_pc        (next_pc),
        .src_reg1_addr  (rs_addr),
        .src_reg1_data  (rs_data),
        .src_reg2_addr  (rt_addr),
        .src_reg2_data  (rt_data),
        .arith_result   (alu_result),
        .writeback_data (wb_data),
        .reg2_write_flag(rt_wr_flag)
    );
    initial begin
        $display("=== CPU测试案例1: 基本指令流 ===");
        clk = 0;
        rst = 0;  
        en = 0;
        #20;
        rst = 1;
        #20;
        en = 1;
        #100;  
        $display("运行5条指令后:");
        $display("PC = %h", pc);
        $display("RS = $%d = %h", rs_addr, rs_data);
        $display("RT = $%d = %h", rt_addr, wb_data);
        #500;
        if (pc == 32'h00000050) begin
            $display("? 测试通过：执行到HALT指令");
        end else begin
            $display("? 测试失败：PC=%h，期望0x50", pc);
        end
        
        #10;
        $finish;
    end
    initial begin
        forever #10 clk = ~clk;
    end
    
endmodule
