`timescale 1ns / 1ps

module softmax_front_exp #(
    parameter N = 16,
    parameter IN_WIDTH = 20,       // 原始 Score 输入位宽
    parameter LUT_ADDR_W = 8,      // Exp ROM 地址位宽
    parameter OUT_WIDTH = 16,      // e^x 输出位宽
    parameter MAX_LATENCY = 6      // max_tree 的固有延迟 (必须与 sync_delay_line 匹配)
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       valid_in,
    input  wire [N*IN_WIDTH-1:0]      row_data_in, // 16 个原始打分数据
    
    output wire                       valid_out,
    output wire [N*OUT_WIDTH-1:0]     exp_data_out // 16 个计算好的 e^x
);

    // ==========================================
    // 内部连线声明
    // ==========================================
    wire signed [IN_WIDTH-1:0] max_out;
    wire                       max_valid;
    wire [N*IN_WIDTH-1:0]      delayed_data_out;

    // ==========================================
    // 1. 实例化：找最大值树 (Max Tree)
    // 延迟：6 拍
    // ==========================================
    max_tree #(
        .N(N), .WIDTH(IN_WIDTH), .STAGES(4)
    ) u_max_tree (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(valid_in),
        .data_in(row_data_in), 
        
        .max_out(max_out), 
        .valid_out(max_valid)
    );

    // ==========================================
    // 2. 实例化：原始数据冷冻舱 (Delay Line)
    // 目的：精确等待 max_tree 消耗的 6 拍
    // ==========================================
    sync_delay_line #(
        .DATA_WIDTH(N*IN_WIDTH), .DELAY_CYCLES(MAX_LATENCY)
    ) u_delay_line (
        .clk(clk), 
        .rst_n(rst_n),
        .data_in(row_data_in), 
        
        .data_out(delayed_data_out)
    );

    // ==========================================
    // 3. 实例化：减法与非线性查表阵列 (Sub & Exp)
    // 包含激进的硬件旁路截断 (>> 6)
    // 延迟：2 拍
    // ==========================================
    sub_exp_array #(
        .N(N), .IN_WIDTH(IN_WIDTH), .LUT_ADDR_W(LUT_ADDR_W), .OUT_WIDTH(OUT_WIDTH)
    ) u_sub_exp (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(max_valid),           // 用 max_tree 吐出的 valid 激活后续流水线
        .row_data_in(delayed_data_out), // 睡了 6 拍刚苏醒的原始数据
        .max_in(max_out),               // 刚刚算出来的最大值
        
        .valid_out(valid_out),
        .exp_data_out(exp_data_out)
    );

endmodule