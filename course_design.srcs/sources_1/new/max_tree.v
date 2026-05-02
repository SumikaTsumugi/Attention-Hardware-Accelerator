`timescale 1ns / 1ps

module max_tree #(
    parameter N = 16,               // 输入数据个数 (16个点积结果)
    parameter WIDTH = 20,           // 每个数据的位宽 (MAC出来的 20-bit 有符号数)
    parameter STAGES = 4            // 流水线级数: log2(16) = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire [N*WIDTH-1:0]     data_in,  // 16 个 20-bit 拼接成 320-bit 的超宽总线
    
    output reg signed [WIDTH-1:0] max_out,  // 最终找出的最大值
    output reg                    valid_out // 最大值有效信号
);

    // ==========================================
    // 0. 数据解包与有符号转换
    // ==========================================
    wire signed [WIDTH-1:0] unpk_data [0:N-1];
    
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK
            // 大端序解包：最左边截取第0个，最右边截取第15个
            assign unpk_data[g] = $signed(data_in[N*WIDTH-1 - (g*WIDTH) : N*WIDTH-WIDTH - (g*WIDTH)]);
        end
    endgenerate

    // ==========================================
    // 1. 二维寄存器阵列: tree_regs[层级 stage][节点 index]
    // ==========================================
    reg signed [WIDTH-1:0] tree_regs [0:STAGES][0:N-1];
    
    integer s, i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s <= STAGES; s = s + 1)
                for (i = 0; i < N; i = i + 1)
                    tree_regs[s][i] <= {WIDTH{1'b0}}; // 清零
            max_out <= {WIDTH{1'b0}};
        end else begin
            // 第 0 级：直接把总线数据吃进寄存器 (为了更好的时序，不与上一级组合逻辑粘连)
            for (i = 0; i < N; i = i + 1) begin
                tree_regs[0][i] <= unpk_data[i];
            end
            
            // 第 1 到 STAGES 级：锦标赛淘汰制两两比较
            for (s = 1; s <= STAGES; s = s + 1) begin
                // 同样使用极其优雅的位移边界控制 (N >> s)
                for (i = 0; i < (N >> s); i = i + 1) begin
                    // 核心比较逻辑：谁大就把谁存到下一级的寄存器里
                    if (tree_regs[s-1][2*i] > tree_regs[s-1][2*i+1])
                        tree_regs[s][i] <= tree_regs[s-1][2*i];
                    else
                        tree_regs[s][i] <= tree_regs[s-1][2*i+1];
                end
            end
            
            // 最终输出 (此时已经打满 5 拍: 1 拍输入缓存 + 4 拍比较树)
            max_out <= tree_regs[STAGES][0];
        end
    end

    // ==========================================
    // 2. valid 同步移位寄存器 (极其重要)
    // ==========================================
    // 数据在阵列里跑了 5 拍 (STAGES + 1)，valid 也要延迟 5 拍
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