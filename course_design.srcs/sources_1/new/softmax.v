`timescale 1ns / 1ps

module softmax #(
    parameter N          = 16,     // 并行通道数
    parameter IN_WIDTH   = 20,     // MAC阵列传来的原始打分位宽
    parameter EXP_WIDTH  = 16,     // 中间 e^x 结果位宽
    parameter PROB_WIDTH = 16      // 最终输出的归一化概率位宽 (Q0.16）
)(
    input  wire                       clk,
    input  wire                       rst_n,
    
    // 输入端接口 (握手信号与数据)
    input  wire                       valid_in,
    input  wire [N*IN_WIDTH-1:0]      row_data_in,
    
    // 输出端接口 (握手信号与数据)
    output wire                       valid_out,
    output wire [N*PROB_WIDTH-1:0]    prob_data_out
);

    // ==========================================
    // 内部高速总线声明
    // ==========================================
    wire [N*EXP_WIDTH-1:0] exp_data_bus; // 承载 16 个 e^x 的高速路
    wire                   exp_valid;    // 前端完成计算的握手信号

    // ==========================================
    // 1. 实例化：Softmax 前端处理核心 (寻找最大值 + 指数非线性)
    // 模块总延迟：8 个时钟周期 (Max=6, Sub=1, ROM=1)
    // ==========================================
    softmax_front_exp #(
        .N(N), 
        .IN_WIDTH(IN_WIDTH), 
        .LUT_ADDR_W(8), 
        .OUT_WIDTH(EXP_WIDTH),
        .MAX_LATENCY(6)  // 匹配内部 max_tree 的延迟
    ) u_front_exp (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(valid_in), 
        .row_data_in(row_data_in),
        
        .valid_out(exp_valid), 
        .exp_data_out(exp_data_bus)
    );

    // ==========================================
    // 2. 实例化：Softmax 后端归一化核心 (求和 + 倒数 + 乘法平账)
    // 模块总延迟：9 个时钟周期 (Adder=5, Recip=2, Mult=1, Shift=1)
    // ==========================================
    softmax_backend_normalize #(
        .N(N), 
        .IN_WIDTH(EXP_WIDTH), 
        .SUM_WIDTH(20),       // 加法树的最大膨胀位宽 (16个数相加最多膨胀4位)
        .PROB_WIDTH(PROB_WIDTH)
    ) u_backend_norm (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(exp_valid), 
        .exp_data_in(exp_data_bus),
        
        .valid_out(valid_out), 
        .prob_data_out(prob_data_out)
    );

endmodule