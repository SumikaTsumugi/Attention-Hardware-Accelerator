`timescale 1ns / 1ps

module pv_mac_array #(
    parameter N = 16,
    parameter P_WIDTH = 16,     // Softmax 出来的 Q0.16 概率
    parameter V_WIDTH = 16,     // V 矩阵的带符号原始数据
    parameter OUT_WIDTH = 16    // 最终输出位宽
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       valid_in,
    
    input  wire [N*P_WIDTH-1:0]       p_vector_in,  // 1x16 的概率向量
    input  wire [N*N*V_WIDTH-1:0]     v_matrix_in,  // 16x16 的 V 矩阵 (展开后的超宽总线)
    
    output reg                        valid_out,
    output wire [N*OUT_WIDTH-1:0]     attention_out // 最终加权求和后的 1x16 结果
);

    // ==========================================
    // 1. 数据解包与对齐
    // ==========================================
    wire [P_WIDTH-1:0]        P [0:N-1];
    wire signed [V_WIDTH-1:0] V [0:N-1][0:N-1]; // V[行][列]
    
    genvar i, j;
    generate
        // 解包概率向量 P
        for (i = 0; i < N; i = i + 1) begin : UNPACK_P
            assign P[i] = p_vector_in[N*P_WIDTH-1 - (i*P_WIDTH) : N*P_WIDTH-P_WIDTH - (i*P_WIDTH)];
        end
        // 解包 V 矩阵 (假设按行优先排列)
        for (i = 0; i < N; i = i + 1) begin : ROW
            for (j = 0; j < N; j = j + 1) begin : COL
                // 巧妙计算偏移量提取 V[i][j]
                assign V[i][j] = $signed(v_matrix_in[ ((N*N*V_WIDTH)-1) - ((i*N+j)*V_WIDTH) : ((N*N*V_WIDTH)) - ((i*N+j+1)*V_WIDTH) ]);
            end
        end
    endgenerate

    // ==========================================
    // 2. 第一拍流水：带符号位扩展与 256 并行乘法
    // ==========================================
    // 【架构师黑科技落地】：强行补 0，让 0xFFFF 变成正数！
    wire signed [P_WIDTH:0] P_safe [0:N-1];
    generate
        for (i = 0; i < N; i = i + 1) begin : SIGN_EXTEND
            assign P_safe[i] = {1'b0, P[i]}; // 变成 17-bit 的正数
        end
    endgenerate

    reg signed [P_WIDTH+V_WIDTH:0] mult_res [0:N-1][0:N-1]; // 33-bit 乘积
    reg mult_valid;
    
    integer r, c;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (r=0; r<N; r=r+1)
                for (c=0; c<N; c=c+1)
                    mult_res[r][c] <= 0;
            mult_valid <= 0;
        end else begin
            for (r=0; r<N; r=r+1) begin
                for (c=0; c<N; c=c+1) begin
                    // 触发物理 DSP 乘法！
                    mult_res[r][c] <= P_safe[r] * V[r][c];
                end
            end
            mult_valid <= valid_in;
        end
    end

    // ==========================================
    // 3. 第二拍流水：加法树求和与缩放还原
    // ==========================================
    reg signed [37:0] sum_res [0:N-1]; // 预留 4 bits 防溢出
    reg [N*OUT_WIDTH-1:0] packed_out;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (c=0; c<N; c=c+1) sum_res[c] <= 0;
            packed_out <= 0;
            valid_out <= 0;
        end else begin
            for (c=0; c<N; c=c+1) begin
                // 对每一列进行求和 (Out_c = 偏置 + Sum(P_r * V_r,c))
                sum_res[c] = 0; // 组合逻辑累加器
                for (r=0; r<N; r=r+1) begin
                    sum_res[c] = sum_res[c] + mult_res[r][c];
                end
                
                // 【终极平账】：因为 P 是 Q0.16 放大进来的
                // 我们算出乘积后，必须整体右移 16 位 (带符号算术右移 >>>) 
                // 才能把 V 的尺度完美还原回来！
                packed_out[N*OUT_WIDTH-1 - (c*OUT_WIDTH) -: OUT_WIDTH] <= sum_res[c] >>> 16;
            end
            valid_out <= mult_valid;
        end
    end

    assign attention_out = packed_out;

endmodule