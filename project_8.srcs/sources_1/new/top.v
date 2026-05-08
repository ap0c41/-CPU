`timescale 1ns / 1ps 
module basys3_top_module(
    input  wire        clk,      
    input  wire [15:0] sw,
    input  wire        btnR,
    output wire [7:0]  seg,
    output wire [3:0]  an
);
    wire system_reset = sw[0];
    wire single_step;
    button_debouncer u_button_ctrl(
        .clk   (clk),
        .rst   (system_reset),
        .btn_in(btnR),
        .pulse (single_step)  
    );
    wire [31:0] current_pc, future_pc;
    wire [4:0]  source1_addr, source2_addr;
    wire [31:0] source1_val, source2_val;
    wire [31:0] calc_output, write_value;
    wire        target2_modified;  

    processor_core u_processor(
        .sys_clk        (clk),       
        .sys_rst        (system_reset),       // 低电平复位
        .exec_enable    (single_step),   // 单步使能
        .program_counter    (current_pc),
        .next_pc    (future_pc),
        .src_reg1_addr    (source1_addr),
        .src_reg1_data    (source1_val),
        .src_reg2_addr    (source2_addr),
        .src_reg2_data    (source2_val),
        .arith_result (calc_output),
        .writeback_data  (write_value),
        .reg2_write_flag(target2_modified)
    );
    wire [7:0] pc_low_byte      = current_pc[7:0];
    wire [7:0] next_pc_low = future_pc[7:0];
    wire [7:0] reg1_addr_ext     = {3'b000, source1_addr};
    wire [7:0] reg2_addr_ext     = {3'b000, source2_addr};
    wire [7:0] reg2_display = target2_modified ? write_value[7:0] : source2_val[7:0];

    reg [15:0] display_content;
    always @(*) begin
        case (sw[15:14])
            2'b00: display_content = { pc_low_byte,        next_pc_low      }; // PC : PC_next
            2'b01: display_content = { reg1_addr_ext,       source1_val[7:0]      }; // RS号 : RS数据低8位
            2'b10: display_content = { reg2_addr_ext,       reg2_display           }; // RT号 : RT显示值
            2'b11: display_content = { calc_output[7:0], write_value[7:0]   }; // ALU低8位 : 写回数据低8位
            default: display_content = 16'h0000;
        endcase
    end
    seven_seg_controller u_display(
        .clk (clk),
        .rst (system_reset),
        .data(display_content),
        .seg (seg),
        .an  (an)
    );
endmodule

module button_debouncer(
    input  wire clk,
    input  wire rst,      // 0 = 复位, 1 = 正常
    input  wire btn_in,
    output reg  pulse
);
    reg btn_meta, btn_stable;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            btn_meta <= 1'b0;
            btn_stable <= 1'b0;
        end else begin
            btn_meta <= btn_in;
            btn_stable <= btn_meta;
        end
    end
    reg [19:0] counter;
    reg        button_status = 0;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            counter       <= 20'd0;
            button_status <= 1'b0;
        end else if (btn_stable != button_status) begin
            counter <= counter + 1'b1;
            if (counter == 20'hFFFFF) begin
                button_status <= btn_stable;
                counter       <= 20'd0;
            end
        end else begin
            counter <= 20'd0;
        end
    end
    reg button_prev;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            button_prev <= 1'b0;
            pulse       <= 1'b0;
        end else begin
            button_prev <= button_status;
            pulse       <= button_status & ~button_prev;  
        end
    end
endmodule

module seven_seg_controller(
    input  wire        clk,
    input  wire        rst,    // 0 = 复位, 1 = 正常
    input  wire [15:0] data,
    output reg  [7:0]  seg,
    output reg  [3:0]  an
);
    reg [15:0] refresh_counter;
    reg [1:0]  position_sel;
    reg [3:0]  current_digit;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            refresh_counter   <= 16'd0;
            position_sel <= 2'd0;
        end else begin
            refresh_counter <= refresh_counter + 1'b1;
            if (refresh_counter == 16'd49999) begin
                refresh_counter   <= 16'd0;
                position_sel <= position_sel + 1'b1;
            end
        end
    end
    always @(*) begin
        case (position_sel)
            2'd0: begin an = 4'b1110; current_digit = data[3:0];   end
            2'd1: begin an = 4'b1101; current_digit = data[7:4];   end
            2'd2: begin an = 4'b1011; current_digit = data[11:8];  end
            2'd3: begin an = 4'b0111; current_digit = data[15:12]; end
        endcase
    end
    always @(*) begin
        case (current_digit)
            4'h0: seg = 8'b1100_0000;
            4'h1: seg = 8'b1111_1001;
            4'h2: seg = 8'b1010_0100;
            4'h3: seg = 8'b1011_0000;
            4'h4: seg = 8'b1001_1001;
            4'h5: seg = 8'b1001_0010;
            4'h6: seg = 8'b1000_0010;
            4'h7: seg = 8'b1111_1000;
            4'h8: seg = 8'b1000_0000;
            4'h9: seg = 8'b1001_0000;
            4'hA: seg = 8'b1000_1000;
            4'hB: seg = 8'b1000_0011;
            4'hC: seg = 8'b1100_0110;
            4'hD: seg = 8'b1010_0001;
            4'hE: seg = 8'b1000_0110;
            4'hF: seg = 8'b1000_1110;
            default: seg = 8'b1111_1111;
        endcase
    end
endmodule
