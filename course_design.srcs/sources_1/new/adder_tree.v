`timescale 1ns / 1ps

module adder_tree #(
    parameter N = 16,             // 输入数据个数
    parameter IN_WIDTH = 16,      // 查表出来的 e^x 位宽
    parameter OUT_WIDTH = 20,     // 总和位宽 = IN_WIDTH + log2(N)
    parameter STAGES = 4          // 流水线级数: log2(16) = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire [N*IN_WIDTH-1:0]  data_in,  // 16个16-bit数据拼接总线
    
    output reg  [OUT_WIDTH-1:0]   sum_out,  // 最终的 20-bit 累加和
    output reg                    valid_out
);

    // ==========================================
    // 0. 数据解包 (无符号数)
    // ==========================================
    wire [IN_WIDTH-1:0] unpk_data [0:N-1];
    
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK
            assign unpk_data[g] = data_in[N*IN_WIDTH-1 - (g*IN_WIDTH) : N*IN_WIDTH-IN_WIDTH - (g*IN_WIDTH)];
        end
    endgenerate

    // ==========================================
    // 1. 二维加法树寄存器阵列 (统一声明为最大位宽)
    // ==========================================
    reg [OUT_WIDTH-1:0] tree_regs [0:STAGES][0:N-1];
    
    integer s, i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s <= STAGES; s = s + 1)
                for (i = 0; i < N; i = i + 1)
                    tree_regs[s][i] <= 0;
            sum_out <= 0;
        end else begin
            // 第 0 级：数据缓冲输入
            // 注意：这里是无符号赋值，16-bit 赋给 20-bit，高 4 位会自动补零扩展！
            for (i = 0; i < N; i = i + 1) begin
                tree_regs[0][i] <= unpk_data[i]; 
            end
            
            // 第 1 到 STAGES 级：参数化流水线加法树
            for (s = 1; s <= STAGES; s = s + 1) begin
                for (i = 0; i < (N >> s); i = i + 1) begin
                    tree_regs[s][i] <= tree_regs[s-1][2*i] + tree_regs[s-1][2*i+1];
                end
            end
            
            // 最终输出 (耗时 1 拍缓冲 + 4 拍加法 = 5 个周期)
            sum_out <= tree_regs[STAGES][0];
        end
    end

    // ==========================================
    // 2. Valid 同步移位
    // ==========================================
    reg [STAGES:0] valid_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_shift <= 0;
            valid_out   <= 1'b0;
        end else begin
            valid_shift <= {valid_shift[STAGES-1:0], valid_in};
            valid_out   <= valid_shift[STAGES]; 
        end
    end

endmodule