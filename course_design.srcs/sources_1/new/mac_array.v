`timescale 1ns / 1ps

module mac_array #(
    parameter N = 16,               // 向量维度 d_k
    parameter ADDER_STAGES = 4      // 加法树层数: log2(16) = 4
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,
    input  wire [N*8-1:0] q_vec,    // 参数化总线位宽
    input  wire [N*8-1:0] k_vec,
    
    output reg signed [19:0] dot_result,
    output reg               valid_out
);

    // ==========================================
    // 0. 数据解包 (使用 generate 块展开)
    // ==========================================
    wire signed [7:0] q_arr [0:N-1];
    wire signed [7:0] k_arr [0:N-1];
    
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK
            assign q_arr[g] = $signed(q_vec[N*8-1 - (g*8) : N*8-8 - (g*8)]);
            assign k_arr[g] = $signed(k_vec[N*8-1 - (g*8) : N*8-8 - (g*8)]);
        end
    endgenerate

    // ==========================================
    // 1. 定义统一位宽的二维寄存器阵列
    // tree_regs[层级 stage][节点 index]
    // ==========================================
    reg signed [19:0] tree_regs [0:ADDER_STAGES][0:N-1];
    
    integer s, i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s <= ADDER_STAGES; s = s + 1)
                for (i = 0; i < N; i = i + 1)
                    tree_regs[s][i] <= 20'd0;
            dot_result <= 20'd0;
        end else begin
            // 第 0 级：并行乘法层 (将 16-bit 乘积自动符号扩展存入 20-bit 寄存器)
            for (i = 0; i < N; i = i + 1) begin
                tree_regs[0][i] <= q_arr[i] * k_arr[i]; 
            end
            
            // 第 1 到 ADDER_STAGES 级：参数化流水线加法树
            for (s = 1; s <= ADDER_STAGES; s = s + 1) begin
                // 绝妙的边界控制：每一层的节点数是上一层的一半 (N >> s)
                for (i = 0; i < (N >> s); i = i + 1) begin
                    tree_regs[s][i] <= tree_regs[s-1][2*i] + tree_regs[s-1][2*i+1];
                end
            end
            
            // 最终输出：取出最后一级的唯一结果
            dot_result <= tree_regs[ADDER_STAGES][0];
        end
    end

    // ==========================================
    // 2. valid 同步延迟 (乘法1拍 + 加法树ADDER_STAGES拍)
    // ==========================================
    reg [ADDER_STAGES:0] valid_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_shift <= 0;
            valid_out   <= 1'b0;
        end else begin
            valid_shift <= {valid_shift[ADDER_STAGES-1:0], valid_in};
            valid_out   <= valid_shift[ADDER_STAGES]; 
        end
    end

endmodule