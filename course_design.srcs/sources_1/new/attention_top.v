`timescale 1ns / 1ps

module attention_top #(
    parameter N = 16,           // 序列长度
    parameter D = 16,           // 特征维度
    parameter QK_WIDTH = 8,     // Q, K 输入位宽
    parameter V_WIDTH = 16,     // V 输入位宽
    parameter OUT_WIDTH = 16    // 最终 Attention 特征输出位宽
)(
    input  wire                       clk,
    input  wire                       rst_n,
    
    // 三大核心输入：Q, K, V
    input  wire                       valid_in,
    input  wire [D*QK_WIDTH-1:0]      q_vector_in, // 1xD Query
    input  wire [N*D*QK_WIDTH-1:0]    k_matrix_in, // NxD Key 矩阵
    input  wire [N*N*V_WIDTH-1:0]     v_matrix_in, // NxN Value 矩阵
    
    // 终极输出
    output wire                       valid_out,
    output wire [N*OUT_WIDTH-1:0]     attention_out
);

    // ==========================================
    // 1. 点积打分：Q * K^T (延迟 = 2 拍)
    // ==========================================
    wire [N*20-1:0] qk_scores;
    wire            qk_valid;
    
    qk_dot_array #(
        .N(N), .D(D), .IN_WIDTH(QK_WIDTH), .OUT_WIDTH(20)
    ) u_qk_dot (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .q_vector_in(q_vector_in), .k_matrix_in(k_matrix_in),
        
        .valid_out(qk_valid), .score_out(qk_scores)
    );

    // ==========================================
    // 2. 满血 Q0.16 变速箱：Softmax (延迟 = 17 拍)
    // ==========================================
    wire [N*16-1:0] p_vector;
    wire            p_valid;
    
    softmax #(
        .N(N), .IN_WIDTH(20), .EXP_WIDTH(16), .PROB_WIDTH(16)
    ) u_softmax (
        .clk(clk), .rst_n(rst_n), .valid_in(qk_valid), // 承接 QK 的有效信号
        .row_data_in(qk_scores),
        
        .valid_out(p_valid), .prob_data_out(p_vector)
    );

    // ==========================================
    // 3. V 矩阵时空同步器 (延迟 = QK的2拍 + Softmax的17拍 = 19拍)
    // ==========================================
    wire [N*N*V_WIDTH-1:0] v_matrix_delayed;
    
    sync_delay_line #(
        .DATA_WIDTH(N*N*V_WIDTH), .DELAY_CYCLES(22) // 严丝合缝的时序对齐
    ) u_v_delay (
        .clk(clk), .rst_n(rst_n),
        .data_in(v_matrix_in),      // T=0 时与 Q, K 同时送达的 V
        .data_out(v_matrix_delayed) // T=19 时准时解冻
    );

    // ==========================================
    // 4. 注意力加权求和：P * V (延迟 = 2 拍)
    // ==========================================
    pv_mac_array #(
        .N(N), .P_WIDTH(16), .V_WIDTH(V_WIDTH), .OUT_WIDTH(OUT_WIDTH)
    ) u_pv_mac (
        .clk(clk), .rst_n(rst_n), .valid_in(p_valid),
        .p_vector_in(p_vector),
        .v_matrix_in(v_matrix_delayed),
        
        .valid_out(valid_out), .attention_out(attention_out)
    );

endmodule