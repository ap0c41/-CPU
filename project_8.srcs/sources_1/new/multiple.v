`timescale 1ns / 1ps
module processor_core(
    input wire sys_clk,
    input wire sys_rst,
    input wire exec_enable,
    output wire [31:0] program_counter,
    output wire [31:0] next_pc,
    output wire [4:0] src_reg1_addr,
    output wire [31:0] src_reg1_data,
    output wire [4:0] src_reg2_addr,
    output wire [31:0] src_reg2_data,
    output wire [31:0] arith_result,
    output wire [31:0] writeback_data,
    output wire reg2_write_flag
);
parameter [2:0] 
    S_IF  = 3'd0,  // 取指令
    S_ID  = 3'd1,  // 译码
    S_EX  = 3'd2,  // 执行
    S_MEM = 3'd3,  // 访存
    S_WB  = 3'd4;  // 写回

reg [2:0] current_state, next_state;
reg [31:0] PC_reg;
reg [31:0] PC_reg_prev = 32'b0;
reg [31:0] IR_reg;      // 指令寄存器
reg [31:0] A_reg;       // 寄存器A暂存器
reg [31:0] B_reg;       // 寄存器B暂存器
reg [31:0] ALUOut_reg;  // ALU结果寄存器
reg [31:0] MDR_reg;     // 内存数据寄存器（仅用于lw）
wire [5:0] op_code = IR_reg[31:26];
wire [4:0] reg_s = IR_reg[25:21];
wire [4:0] reg_t = IR_reg[20:16];
wire [4:0] reg_d = IR_reg[15:11];
wire [4:0] shift_amt = IR_reg[10:6];
wire [5:0] func_code = IR_reg[5:0];
wire [15:0] immediate = IR_reg[15:0];
wire [25:0] jump_target = IR_reg[25:0];
wire pc_write_en;
wire reg_write_en;
wire alu_src_a_sel;
wire alu_src_b_sel;
wire mem_to_reg;
wire wrregsrc;
wire [1:0] dest_reg_sel;
wire sign_extend;
wire mem_read;
wire mem_write;
wire [2:0] alu_control;
wire branch_equal;
wire branch_not_equal;
wire branch_less_equal;
wire jr_flag;
wire jump_flag;
wire jal_flag;
wire halt_flag;

decoder_control u_decoder(
    .opcode       (op_code),
    .funct        (func_code),
    .PCWre        (pc_write_en),
    .RegWre       (reg_write_en),
    .ALUSrcA      (alu_src_a_sel),
    .ALUSrcB      (alu_src_b_sel),
    .DBDataSrc    (mem_to_reg),
    .WrRegDSrc    (wrregsrc),
    .RegDst       (dest_reg_sel),
    .ExtSel       (sign_extend),
    .mRD          (mem_read),
    .mWR          (mem_write),
    .ALUOp        (alu_control),
    .Branch_beq   (branch_equal),
    .Branch_bne   (branch_not_equal),
    .Branch_blez  (branch_less_equal),
    .JR           (jr_flag),
    .Jump         (jump_flag),
    .Jal          (jal_flag),
    .Halt         (halt_flag)
);
wire [31:0] reg_s_out, reg_t_out;
reg [4:0] reg_write_addr;
reg reg_write_enable;

register_bank u_reg_bank(
    .clk    (sys_clk),
    .rst    (sys_rst),
    .we     (reg_write_enable & exec_enable),
    .raddr1 (reg_s),
    .raddr2 (reg_t),
    .waddr  (reg_write_addr),
    .wdata  (writeback_data),
    .rdata1 (reg_s_out),
    .rdata2 (reg_t_out)
);
wire [31:0] extended_imm;
immediate_extender u_ext_unit(
    .imm    (immediate),
    .ext_sel(sign_extend),
    .out    (extended_imm)
);
wire [31:0] alu_result;
wire alu_zero, alu_sign;
wire [31:0] alu_a = alu_src_a_sel ? {27'b0, shift_amt} : A_reg;
wire [31:0] alu_b = alu_src_b_sel ? extended_imm : B_reg;

arithmetic_logic_unit u_alu_unit(
    .A       (alu_a),
    .B       (alu_b),
    .alu_op  (alu_control),
    .result  (alu_result),
    .zero    (alu_zero),
    .sign    (alu_sign)
);
wire [31:0] inst_mem_data;
instruction_memory u_inst_mem(
    .addr   (PC_reg[9:2]),
    .dout   (inst_mem_data)
);
wire [31:0] data_mem_data;
wire [31:0] data_mem_addr;
wire data_mem_write_enable;
assign data_mem_addr = (current_state == S_MEM) ? ALUOut_reg : 32'b0;
assign data_mem_write_enable = (current_state == S_MEM) & mem_write & exec_enable;

data_memory u_data_mem(
    .clk  (sys_clk),
    .we   (data_mem_write_enable),
    .addr (data_mem_addr[9:2]),
    .din  (B_reg),
    .dout (data_mem_data)
);
always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        current_state <= S_IF;
        IR_reg <= 32'b0;
        A_reg <= 32'b0;
        B_reg <= 32'b0;
        ALUOut_reg <= 32'b0;
        MDR_reg <= 32'b0;
    end else if (exec_enable) begin
        current_state <= next_state;
        case (current_state)
            S_IF: begin  // 取指令
                IR_reg <= inst_mem_data;  // 从指令存储器读取指令
            end
            
            S_ID: begin  // 译码
                A_reg <= reg_s_out;  // 读取寄存器A
                B_reg <= reg_t_out;  // 读取寄存器B
            end
            
            S_EX: begin  // 执行
                ALUOut_reg <= alu_result;  // 保存ALU结果
            end
            
            S_MEM: begin  // 访存
                if (mem_read) begin
                    MDR_reg <= data_mem_data;  // 读取数据存储器
                end
            end
            
            S_WB: begin  // 写回
                if (reg_write_enable) begin
                end
            end
        endcase
    end
end

//============ 下一状态逻辑 ============
always @(*) begin
    next_state = S_IF;  // 默认回到取指
    
    case (current_state)
        S_IF: next_state = S_ID;
        S_ID: begin
            if(op_code == 6'b111111) //halt指令
                next_state = S_IF; // 停在取指，不执行
            else 
                next_state = S_EX;
        end
        S_EX: begin
            if (mem_read || mem_write)  // 需要访存的指令
                next_state = S_MEM; 
            else if(op_code == 6'b000100 || op_code == 6'b000101 || op_code == 6'b000110)
                next_state = S_IF;  
            else
                next_state = S_WB;
        end
        S_MEM: begin
            if (mem_read)  // lw指令需要写回
                next_state = S_WB;
            else  
                next_state = S_IF;
        end
        S_WB: next_state = S_IF;
    endcase
end

wire [31:0] pc_increment = PC_reg + 32'd4;
wire [31:0] offset_shifted = (extended_imm << 2);
wire [31:0] target_branch = PC_reg + offset_shifted;
wire [31:0] target_jump = {pc_increment[31:28], jump_target, 2'b00};
wire is_blez = (op_code == 6'b000110) && (reg_t == 5'b00000);
wire blez_condition = is_blez && ((A_reg[31]) || (A_reg == 32'b0));
wire beq_condition = branch_equal & alu_zero;
wire bne_condition = branch_not_equal & ~alu_zero;
wire branch_taken = beq_condition | bne_condition | blez_condition;
wire pc_update_en = (current_state == S_EX) && 
                   (jump_flag || jal_flag || 
                    (branch_taken && (branch_equal || branch_not_equal || branch_less_equal)) ||
                    (jr_flag && op_code == 6'b000000));

wire [31:0] pc_next;
reg [31:0] jal_temp;
assign pc_next = 
    jr_flag ? A_reg :  // JR指令
    jump_flag || jal_flag ? target_jump :  // J/JAL指令
    branch_taken ? target_branch :  // 分支指令
    pc_increment;  // 默认PC+4

always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        PC_reg <= 32'h0000_0000;
    end else if (exec_enable) begin
        if (current_state == S_IF) begin
            if(op_code == 6'b111111) begin
                PC_reg_prev <= PC_reg;
            end else begin
                PC_reg_prev <= PC_reg;
                PC_reg <= pc_increment;
            end
        end
        if (current_state == S_EX && pc_update_en) begin
            jal_temp <= PC_reg;
            PC_reg <= pc_next;
        end
    end
end
always @(*) begin
    reg_write_enable = 1'b0;
    reg_write_addr = 5'b0;
    
    if (current_state == S_WB) begin
        if (reg_write_en) begin
            reg_write_enable = 1'b1;
            case (dest_reg_sel)
                2'b00: reg_write_addr = 5'b11111;  // JAL: $ra
                2'b01: reg_write_addr = reg_t;     // I-type
                2'b10: reg_write_addr = reg_d;     // R-type
                default: reg_write_addr = reg_t;
            endcase
        end
    end
end
assign writeback_data = 
    mem_to_reg ? MDR_reg :           // lw指令：从内存读取的数据
    jal_flag ? (jal_temp) :    // JAL指令：PC+4
    ALUOut_reg;                      // 其他指令：ALU结果
assign program_counter = PC_reg_prev;
assign next_pc = PC_reg;
assign src_reg1_addr = reg_s;
assign src_reg1_data = reg_s_out;
assign src_reg2_addr = reg_t;
assign src_reg2_data = reg_t_out;
assign arith_result = ALUOut_reg;
assign reg2_write_flag = reg_write_enable && (reg_write_addr == reg_t);

endmodule
module program_counter_reg(
    input wire clk,
    input wire rst,          // 0 复位，1 正常工作
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
initial begin
    for (idx = 0; idx < 32; idx = idx + 1)
        register_array[idx] = 32'b0;
end

// 写操作：上升沿
always @(posedge clk or negedge rst) begin
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
    output reg WrRegDSrc,
    output reg [1:0]RegDst,
    output reg ExtSel,
    output reg mRD,
    output reg mWR,
    output reg [2:0] ALUOp,
    output reg Branch_beq,
    output reg Branch_bne,
    output reg Branch_blez,
    output reg JR,
    output reg Jump,
    output reg Jal,
    output reg Halt
);

localparam OP_R      = 6'b000000;
localparam OP_ADDIU  = 6'b001001;
localparam OP_XORI   = 6'b001110;  
localparam OP_ANDI   = 6'b001100;
localparam OP_ORI    = 6'b001101;
localparam OP_SLTI   = 6'b001010;
localparam OP_LW     = 6'b100011;
localparam OP_SW     = 6'b101011;
localparam OP_BEQ    = 6'b000100;
localparam OP_BNE    = 6'b000101;
localparam OP_BLEZ   = 6'b000110;   
localparam OP_J      = 6'b000010;
localparam OP_JAL    = 6'b000011;
localparam OP_HALT   = 6'b111111;

localparam FUNCT_ADD = 6'b100000;
localparam FUNCT_SUB = 6'b100010;
localparam FUNCT_AND = 6'b100100;
localparam FUNCT_OR  = 6'b100101;
localparam FUNCT_SLL = 6'b000000;
localparam FUNCT_SLT = 6'b101010;
localparam FUNCT_JR  = 6'b001000;
always @(*) begin
    PCWre        = 1'b1;
    RegWre       = 1'b0;
    ALUSrcA      = 1'b0;
    ALUSrcB      = 1'b0;
    DBDataSrc    = 1'b0;
    WrRegDSrc    = 1'b1;
    RegDst       = 2'b01;
    ExtSel       = 1'b1;  
    mRD          = 1'b0;
    mWR          = 1'b0;
    ALUOp        = 3'b000;
    Branch_beq   = 1'b0;
    Branch_bne   = 1'b0;
    Branch_blez  = 1'b0;
    JR           = 1'b0;
    Jump         = 1'b0;
    Jal          = 1'b0;
    Halt         = 1'b0;

    case (opcode)
        OP_R: begin
            RegWre = 1'b1;
            RegDst = 2'b10;
            case (funct)
                FUNCT_ADD: ALUOp = 3'b000;
                FUNCT_SUB: ALUOp = 3'b001;
                FUNCT_AND: ALUOp = 3'b100;
                FUNCT_OR : ALUOp = 3'b011;
                FUNCT_SLL: begin
                    ALUOp   = 3'b010;
                    ALUSrcA = 1'b1;
                end
                FUNCT_SLT: ALUOp = 3'b101;
                FUNCT_JR:  JR = 1'b1;
                default: ALUOp = 3'b000;
            endcase
        end
        OP_ADDIU: begin
            RegWre  = 1'b1;
            RegDst  = 2'b01;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b1;  
            ALUOp   = 3'b000;
        end

        OP_XORI: begin
            RegWre  = 1'b1;
            RegDst  = 2'b01;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b0;  
            ALUOp   = 3'b111;
        end

        OP_ANDI: begin
            RegWre  = 1'b1;
            RegDst  = 2'b01;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b0;  
            ALUOp   = 3'b100;
        end

        OP_ORI: begin
            RegWre  = 1'b1;
            RegDst  = 2'b01;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b0;  
            ALUOp   = 3'b011;
        end

        OP_SLTI: begin
            RegWre  = 1'b1;
            RegDst  = 2'b01;
            ALUSrcB = 1'b1;
            ExtSel  = 1'b1;  
            ALUOp   = 3'b110;
        end

        OP_LW: begin
            RegWre    = 1'b1;
            RegDst    = 2'b01;
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
        
        OP_JAL: begin
            Jal = 1'b1;
            WrRegDSrc = 1'b0;
            RegDst = 2'b00;
            RegWre = 1'b1;
        end
        
        OP_HALT: begin
            PCWre = 1'b0;
            Halt  = 1'b1;
        end
    endcase
end

endmodule
