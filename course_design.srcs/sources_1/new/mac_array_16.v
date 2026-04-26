`timescale 1ns / 1ps

module mac_array_16 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in, // 数据有效脉冲
    input  wire [127:0] q_vec,    // 16个 8-bit Q 数据拼接
    input  wire [127:0] k_vec,    // 16个 8-bit K 数据拼接
    
    output reg signed [19:0] dot_result, // 点积最终结果 (位宽防溢出)
    output reg               valid_out   // 结果有效信号
);

    // ==========================================
    // 0. 数据解包与类型转换 (Unpacking)
    // ==========================================
    // 将 128-bit 拆解为 16 个 8-bit 有符号数
    wire signed [7:0] q_arr [0:15];
    wire signed [7:0] k_arr [0:15];
    
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : UNPACK
            assign q_arr[i] = $signed(q_vec[(i*8)+7 : i*8]);
            assign k_arr[i] = $signed(k_vec[(i*8)+7 : i*8]);
        end
    endgenerate

    // ==========================================
    // 流水线第 1 级：并行乘法层 (16个乘法器)
    // 位宽：8-bit * 8-bit = 16-bit
    // ==========================================
    reg signed [15:0] mult_reg [0:15];
    integer m;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (m = 0; m < 16; m = m + 1) mult_reg[m] <= 16'd0;
        end 
        else begin
            for (m = 0; m < 16; m = m + 1) begin
                // 使用 Verilog 自带乘法号，综合器会自动调用 DSP48E
                mult_reg[m] <= q_arr[m] * k_arr[m]; 
            end
        end
    end

    // ==========================================
    // 流水线第 2 级：加法树 L1 (8个加法器)
    // 位宽：16-bit + 16-bit = 17-bit
    // ==========================================
    reg signed [16:0] add_l1_reg [0:7];
    integer a1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (a1 = 0; a1 < 8; a1 = a1 + 1) add_l1_reg[a1] <= 17'd0;
        end
        else begin
            for (a1 = 0; a1 < 8; a1 = a1 + 1) begin
                add_l1_reg[a1] <= mult_reg[a1*2] + mult_reg[a1*2+1];
            end
        end
    end

    // ==========================================
    // 流水线第 3 级：加法树 L2 (4个加法器)
    // 位宽：17-bit + 17-bit = 18-bit
    // ==========================================
    reg signed [17:0] add_l2_reg [0:3];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_l2_reg[0] <= 0; add_l2_reg[1] <= 0;
            add_l2_reg[2] <= 0; add_l2_reg[3] <= 0;
        end else begin
            add_l2_reg[0] <= add_l1_reg[0] + add_l1_reg[1];
            add_l2_reg[1] <= add_l1_reg[2] + add_l1_reg[3];
            add_l2_reg[2] <= add_l1_reg[4] + add_l1_reg[5];
            add_l2_reg[3] <= add_l1_reg[6] + add_l1_reg[7];
        end
    end

    // ==========================================
    // 流水线第 4 级：加法树 L3 (2个加法器)
    // 位宽：18-bit + 18-bit = 19-bit
    // ==========================================
    reg signed [18:0] add_l3_reg [0:1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_l3_reg[0] <= 0; add_l3_reg[1] <= 0;
        end else begin
            add_l3_reg[0] <= add_l2_reg[0] + add_l2_reg[1];
            add_l3_reg[1] <= add_l2_reg[2] + add_l2_reg[3];
        end
    end

    // ==========================================
    // 流水线第 5 级：最终输出 (1个加法器)
    // 位宽：19-bit + 19-bit = 20-bit
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dot_result <= 0;
        else        dot_result <= add_l3_reg[0] + add_l3_reg[1];
    end

    // ==========================================
    // 同步控制信号：Valid 移位寄存器 (极其关键!)
    // 数据在树里跑了 5 个时钟周期，valid 信号也必须延迟 5 拍
    // ==========================================
    reg [4:0] valid_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_shift <= 5'd0;
            valid_out   <= 1'b0;
        end
        else begin
            // 移位寄存器：把 valid_in 从最低位推入，5拍后从最高位掉出来
            valid_shift <= {valid_shift[3:0], valid_in};
            valid_out   <= valid_shift[4]; 
        end
    end

endmodule