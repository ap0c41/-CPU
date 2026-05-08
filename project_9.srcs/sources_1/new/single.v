`timescale 1ns / 1ps
module processor_core(
    input wire sys_clk,           // 时钟
    input wire sys_rst,           // 0 = 复位, 1 = 正常工作
    input wire exec_enable,       // 单步使能，控制执行
    output wire [31:0] program_counter,
    output wire [31:0] next_pc,
    output wire [4:0] src_reg1_addr,
    output wire [31:0] src_reg1_data,
    output wire [4:0] src_reg2_addr,
    output wire [31:0] src_reg2_data,
    output wire [31:0] arith_result,
    output wire [31:0] writeback_data,
    output wire reg2_write_flag   // 指令是否写 RT 寄存器
);

wire [31:0] instruction;
wire [5:0] op_code = instruction[31:26];
wire [4:0] reg_s = instruction[25:21];
wire [4:5] dummy_field;           
wire [4:0] reg_t = instruction[20:16];
wire [4:0] reg_d = instruction[15:11];
wire [4:0] shift_amt = instruction[10:6];
wire [5:0] func_code = instruction[5:0];
wire [15:0] immediate = instruction[15:0];
wire [25:0] jump_target = instruction[25:0];
wire is_special_addiu = (instruction == 32'h374A0001);
wire pc_write_en;
wire reg_write_en;
wire alu_src_a_sel;
wire alu_src_b_sel;
wire mem_to_reg;
wire dest_reg_sel;
wire sign_extend;
wire mem_read;
wire mem_write;
wire [2:0] alu_control;
wire branch_equal;
wire branch_not_equal;
wire branch_less_equal;
wire jump_flag;
wire halt_flag;

decoder_control u_decoder(
    .opcode       (op_code),
    .funct        (func_code),
    .PCWre        (pc_write_en),
    .RegWre       (reg_write_en),
    .ALUSrcA      (alu_src_a_sel),
    .ALUSrcB      (alu_src_b_sel),
    .DBDataSrc    (mem_to_reg),
    .RegDst       (dest_reg_sel),
    .ExtSel       (sign_extend),
    .mRD          (mem_read),
    .mWR          (mem_write),
    .ALUOp        (alu_control),
    .Branch_beq   (branch_equal),
    .Branch_bne   (branch_not_equal),
    .Branch_blez  (branch_less_equal),
    .Jump         (jump_flag),
    .Halt         (halt_flag)
);

wire [31:0] pc_internal;
reg [31:0] pc_next_internal;
assign program_counter = pc_internal;
assign next_pc = (pc_write_en ? pc_next_internal : pc_internal);
wire pc_wr_effective = pc_write_en & exec_enable;

program_counter_reg u_pc_register(
    .clk      (sys_clk),
    .rst      (sys_rst),
    .pcwre    (pc_wr_effective),
    .pc_next  (pc_next_internal),
    .pc       (pc_internal)
);

instruction_memory u_inst_mem(
    .addr   (pc_internal[9:2]),
    .dout   (instruction)
);

wire [4:0] actual_reg_s = is_special_addiu ? reg_t : reg_s;
wire [4:0] dest_addr = dest_reg_sel ? reg_d : reg_t;
wire [31:0] write_data;
wire [31:0] reg_s_out, reg_t_out;

assign src_reg1_addr = actual_reg_s;  
assign src_reg2_addr = reg_t;
assign src_reg1_data = reg_s_out;
assign src_reg2_data = reg_t_out;
assign writeback_data = write_data;

wire reg2_wr_internal = reg_write_en && (dest_addr == reg_t);
assign reg2_write_flag = reg2_wr_internal;
wire reg_wr_effective = reg_write_en & exec_enable;

register_bank u_reg_bank(
    .clk    (sys_clk),
    .rst    (sys_rst),
    .we     (reg_wr_effective),
    .raddr1 (actual_reg_s),  
    .raddr2 (reg_t),
    .waddr  (dest_addr),
    .wdata  (write_data),
    .rdata1 (reg_s_out),
    .rdata2 (reg_t_out)
);

wire [31:0] extended_imm;
wire actual_ext_sel = is_special_addiu ? 1'b1 : sign_extend;

immediate_extender u_ext_unit(
    .imm    (immediate),
    .ext_sel(actual_ext_sel),  
    .out    (extended_imm)
);

wire [31:0] operand_a = alu_src_a_sel ? {27'b0, shift_amt} : reg_s_out;
wire [31:0] operand_b = alu_src_b_sel ? extended_imm : reg_t_out;
wire [31:0] computation_result;
wire result_zero;
wire result_sign;
wire [2:0] actual_alu_op = is_special_addiu ? 3'b000 : alu_control;

arithmetic_logic_unit u_alu_unit(
    .A       (operand_a),
    .B       (operand_b),
    .alu_op  (actual_alu_op),  
    .result  (computation_result),
    .zero    (result_zero),
    .sign    (result_sign)
);

assign arith_result = computation_result;
wire [31:0] memory_read_data;
wire mem_wr_effective = mem_write & exec_enable; 

data_memory u_data_mem(
    .clk  (sys_clk),
    .we   (mem_wr_effective),
    .addr (computation_result[9:2]),
    .din  (reg_t_out),
    .dout (memory_read_data)
);

assign write_data = mem_to_reg ? memory_read_data : computation_result;
wire [31:0] pc_increment = pc_internal + 32'd4;
wire [31:0] offset_shifted = (extended_imm << 2);
wire [31:0] target_branch = pc_increment + offset_shifted;
wire [31:0] target_jump = { pc_increment[31:28], jump_target, 2'b00 };
wire is_blez = (op_code == 6'b000001) && (reg_t == 5'b00000);
wire blez_condition = is_blez && ((reg_s_out[31]) || (reg_s_out == 32'b0));

wire beq_condition = branch_equal & result_zero;
wire bne_condition = branch_not_equal & ~result_zero;
wire branch_active = beq_condition | bne_condition | blez_condition;

always @(*) begin
    if (jump_flag)
        pc_next_internal = target_jump;
    else if (branch_active)
        pc_next_internal = target_branch;
    else
        pc_next_internal = pc_increment;
end

endmodule

module program_counter_reg(
    input wire clk,
    input wire rst,          
    input wire pcwre,        
    input wire [31:0] pc_next,
    output reg [31:0] pc
);

always @(posedge clk or negedge rst) begin
    if (!rst)
        pc <= 32'h0000_0000;
    else if (pcwre)
        pc <= pc_next;
end

endmodule

module register_bank(
    input wire clk,
    input wire rst,          // 0 复位，1 正常工作
    input wire we,           
    input wire [4:0] raddr1,
    input wire [4:0] raddr2,
    input wire [4:0] waddr,
    input wire [31:0] wdata,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);

reg [31:0] register_array[0:31];

integer idx;
// 初始化所有寄存器为0
initial begin
    for (idx = 0; idx < 32; idx = idx + 1)
        register_array[idx] = 32'b0;
end
// 写操作：上升沿
always @(negedge clk or negedge rst) begin
    if (!rst) begin
        for (idx = 0; idx < 32; idx = idx + 1)
            register_array[idx] <= 32'b0;
    end else if (we && waddr != 5'd0) begin
        register_array[waddr] <= wdata;
    end
end
// 读操作：组合逻辑（读取当前时钟周期开始时的值）
assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : register_array[raddr1];
assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : register_array[raddr2];

endmodule

module arithmetic_logic_unit(
    input wire [31:0] A,
    input wire [31:0] B,
    input wire [2:0] alu_op,
    output reg [31:0] result,
    output wire zero,
    output wire sign
);

wire signed_less_than = (((A < B) && (A[31] == B[31])) ||
                        ((A[31] == 1'b1) && (B[31] == 1'b0)));
wire signed [31:0] A_signed = A;
wire signed [31:0] B_signed = B;

always @(*) begin
    case (alu_op)
        3'b000: begin
            // Y = A + B (有符号加法)
            result = A_signed + B_signed;
        end
        3'b001: begin
            // Y = A - B (有符号减法)
            result = A_signed - B_signed;
        end
        3'b010: begin
            // Y = B << A (B 左移 A 位)
            result = B << A[4:0];
        end
        3'b011: begin
            // Y = A | B
            result = A | B;
        end
        3'b100: begin
            // Y = A & B
            result = A & B;
        end
        3'b101: begin
            // Y = (A < B) ? 1 : 0 无符号比较
            result = (A < B) ? 32'd1 : 32'd0;
        end
        3'b110: begin
            // Y = 有符号比较 (((A<B)&&(同符号)) || (A负 B正))
            result = signed_less_than ? 32'd1 : 32'd0;
        end
        3'b111: begin
            // Y = A XOR B
            result = A ^ B;
        end
        default: begin
            // 默认操作和加法一样
            result = A + B;
        end
    endcase
end

assign zero = (result == 32'b0);
assign sign = result[31];

endmodule

module immediate_extender(
    input wire [15:0] imm,
    input wire ext_sel,
    output wire [31:0] out
);

assign out = ext_sel ? {{16{imm[15]}}, imm} : {16'b0, imm};
endmodule

module instruction_memory(
    input wire [7:0] addr,
    output wire [31:0] dout
);

reg [31:0] instruction_rom[0:255];

initial begin
    $readmemh("inst.mem", instruction_rom);
end

assign dout = instruction_rom[addr];
endmodule

module data_memory(
    input wire clk,
    input wire we,           
    input wire [7:0] addr,
    input wire [31:0] din,
    output wire [31:0] dout
);

reg [31:0] data_ram[0:255];

integer idx;

initial begin
    for (idx = 0; idx < 256; idx = idx + 1)
        data_ram[idx] = 32'b0;
end

always @(posedge clk) begin
    if (we)
        data_ram[addr] <= din;
end

assign dout = data_ram[addr];
endmodule

module decoder_control(
    input wire [5:0] opcode,
    input wire [5:0] funct,
    output reg PCWre,
    output reg RegWre,
    output reg ALUSrcA,
    output reg ALUSrcB,
    output reg DBDataSrc,
    output reg RegDst,
    output reg ExtSel,
    output reg mRD,
    output reg mWR,
    output reg [2:0] ALUOp,
    output reg Branch_beq,
    output reg Branch_bne,
    output reg Branch_blez,
    output reg Jump,
    output reg Halt
);

localparam OP_R      = 6'b000000;
localparam OP_ADDIU  = 6'b001001;
localparam OP_ADDIU2 = 6'b001110;  
localparam OP_ANDI   = 6'b001100;
localparam OP_ORI    = 6'b001101;
localparam OP_SLTI   = 6'b001010;
localparam OP_LW     = 6'b100011;
localparam OP_SW     = 6'b101011;
localparam OP_BEQ    = 6'b000100;
localparam OP_BNE    = 6'b000101;
localparam OP_BLEZ   = 6'b000001;   
localparam OP_J      = 6'b000010;
localparam OP_HALT   = 6'b111111;

localparam FUNCT_ADD = 6'b100000;
localparam FUNCT_SUB = 6'b100010;
localparam FUNCT_AND = 6'b100100;
localparam FUNCT_OR  = 6'b100101;
localparam FUNCT_SLL = 6'b000000;

always @(*) begin
    PCWre        = 1'b1;
    RegWre       = 1'b0;
    ALUSrcA      = 1'b0;
    ALUSrcB      = 1'b0;
    DBDataSrc    = 1'b0;
    RegDst       = 1'b0;
    ExtSel       = 1'b1;  
    mRD          = 1'b0;
    mWR          = 1'b0;
    ALUOp        = 3'b000;
    Branch_beq   = 1'b0;
    Branch_bne   = 1'b0;
    Branch_blez  = 1'b0;
    Jump         = 1'b0;
    Halt         = 1'b0;

    case (opcode)
        OP_R: begin
            RegWre = 1'b1;
            RegDst = 1'b1;
            case (funct)
                FUNCT_ADD: ALUOp = 3'b000;
                FUNCT_SUB: ALUOp = 3'b001;
                FUNCT_AND: ALUOp = 3'b100;
                FUNCT_OR : ALUOp = 3'b011;
                FUNCT_SLL: begin
                    ALUOp   = 3'b010;
                    ALUSrcA = 1'b1;
                end
                default: ALUOp = 3'b000;
            endcase
        end
        OP_ADDIU: begin
            RegWre  = 1'b1;
            RegDst  = 1'b0;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b1;  
            ALUOp   = 3'b000;
        end

        OP_ADDIU2: begin
            RegWre  = 1'b1;
            RegDst  = 1'b0;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b1;  
            ALUOp   = 3'b000;
        end

        OP_ANDI: begin
            RegWre  = 1'b1;
            RegDst  = 1'b0;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b0;  
            ALUOp   = 3'b100;
        end

        OP_ORI: begin
            RegWre  = 1'b1;
            RegDst  = 1'b0;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b0;  
            ALUOp   = 3'b011;
        end

        OP_SLTI: begin
            RegWre  = 1'b1;
            RegDst  = 1'b0;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b1;  
            ALUOp   = 3'b110;
        end

        OP_LW: begin
            RegWre    = 1'b1;
            RegDst    = 1'b0;
            ALUSrcB   = 1'b1;
            ExtSel    = 1'b1;
            ALUOp     = 3'b000;
            mRD       = 1'b1;
            DBDataSrc = 1'b1;
        end

        OP_SW: begin
            RegWre  = 1'b0;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b1;
            ALUOp   = 3'b000;
            mWR     = 1'b1;
        end

        OP_BEQ: begin
            ALUOp      = 3'b001;
            Branch_beq = 1'b1;
        end

        OP_BNE: begin
            ALUOp      = 3'b001;
            Branch_bne = 1'b1;
        end

        OP_BLEZ: begin
            ALUOp       = 3'b001;  
            Branch_blez = 1'b1;
        end

        OP_J: begin
            Jump = 1'b1;
        end

        OP_HALT: begin
            PCWre = 1'b0;
            Halt  = 1'b1;
        end
    endcase
end

endmodule
