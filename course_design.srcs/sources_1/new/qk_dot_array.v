`timescale 1ns / 1ps

module qk_dot_array #(
    parameter N = 16,     // Key 的序列长度 (Token 数量)
    parameter D = 16,           // Q, K 的特征维度 (Head Dimension)
    parameter IN_WIDTH = 8,     // Q, K 的输入位宽 (例如 INT8)
    parameter OUT_WIDTH = 20,   // 乘积累加后的得分位宽 (完美对接 Softmax)
    parameter ADDER_STAGES = 4  // 加法树层数: log2(16) = 4
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       valid_in,
    
    input  wire [D*IN_WIDTH-1:0]      q_vector_in,  // 1xD 的 Query 向量
    input  wire [N*D*IN_WIDTH-1:0] k_matrix_in,  //  NxD 的 Key 矩阵
    
    output wire                       valid_out,
    output wire [N*OUT_WIDTH-1:0] score_out     // 1xSEQ_LEN 的打分结果
);

    // ==========================================
    // 1. 数据解包：将矩阵切片成 N 个 1xD 的向量
    // ==========================================
    wire [D*IN_WIDTH-1:0] k_row [0:N-1];
    
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : UNPACK_K
            // 安全地切出每一个 Key 向量
            assign k_row[i] = k_matrix_in[N*D*IN_WIDTH-1 - (i*D*IN_WIDTH) -: D*IN_WIDTH];
        end
    endgenerate

    // ==========================================
    // 2. 核心例化：调用 N 个并行的底层 mac_array
    // ==========================================
    wire [N-1:0]   mac_valid_out_array;
    wire [OUT_WIDTH-1:0] mac_score_out [0:N-1];

    generate
        for (i = 0; i < N; i = i + 1) begin : MAC_ENGINES
            mac_array #(
                .N(D),                   // 映射特征维度 D 到底层的 N
                .ADDER_STAGES(ADDER_STAGES) // 传递加法树层数
            ) u_mac_engine (
                .clk(clk),
                .rst_n(rst_n),
                .valid_in(valid_in),
                
                // 接口严丝合缝对齐底层 IP
                .q_vec(q_vector_in),     // 广播 Query 向量
                .k_vec(k_row[i]),        // 路由对应的 Key 向量
                
                .valid_out(mac_valid_out_array[i]),
                .dot_result(mac_score_out[i])
            );
        end
    endgenerate

    // ==========================================
    // 3. 握手同步与数据打包输出
    // ==========================================
    // 取第 0 个的 valid 信号作为总输出标志（所有阵列物理并行，延迟绝对一致）
    assign valid_out = mac_valid_out_array[0];

    generate
        for (i = 0; i < N; i = i + 1) begin : PACK_OUT
            // 将单独的得分打包成高速总线
            assign score_out[N*OUT_WIDTH-1 - (i*OUT_WIDTH) -: OUT_WIDTH] = mac_score_out[i];
        end
    endgenerate

endmodule