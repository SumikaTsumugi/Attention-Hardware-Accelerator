`timescale 1ns / 1ps

module tb_attention_top();

    // ==========================================
    // 1. 系统参数定义
    // ==========================================
    parameter N = 16;
    parameter D = 16;
    parameter QK_WIDTH = 8;
    parameter V_WIDTH = 16;
    parameter OUT_WIDTH = 16;

    // ==========================================
    // 2. 信号声明
    // ==========================================
    reg                       clk;
    reg                       rst_n;
    reg                       valid_in;
    
    // 超宽输入总线
    reg  [D*QK_WIDTH-1:0]     q_vector_in;
    reg  [N*D*QK_WIDTH-1:0]   k_matrix_in;
    reg  [N*N*V_WIDTH-1:0]    v_matrix_in;
    
    wire                      valid_out;
    wire [N*OUT_WIDTH-1:0]    attention_out;

    // ==========================================
    // 3. 例化 V12 引擎：attention_top
    // ==========================================
    attention_top #(
        .N(N), .D(D), .QK_WIDTH(QK_WIDTH), .V_WIDTH(V_WIDTH), .OUT_WIDTH(OUT_WIDTH)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .q_vector_in(q_vector_in),
        .k_matrix_in(k_matrix_in),
        .v_matrix_in(v_matrix_in),
        
        .valid_out(valid_out),
        .attention_out(attention_out)
    );

    // ==========================================
    // 4. 时钟生成 (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // 5. 激励注入与剧本编排
    // ==========================================
    integer i, j;
    initial begin
        // 初始化
        rst_n = 0;
        valid_in = 0;
        q_vector_in = 0;
        k_matrix_in = 0;
        v_matrix_in = 0;
        
        #35; rst_n = 1; #10;
        $display("=========================================================");
        $display("启动 Attention 硬件加速器全流水线测试 ...");
        $display("=========================================================");

       // ----------------------------------------------------
        // 构造"绝对注意力"场景 (狂暴数值版)
        // ----------------------------------------------------
        
        // 1. 打包 Q 向量: 16 个维度全部填入 120！
        for (i = 0; i < D; i = i + 1) begin
            q_vector_in[D*QK_WIDTH-1 - i*QK_WIDTH -: QK_WIDTH] = 8'd120;
        end
        
        // 2. 打包 K 矩阵: 
        // Token 0 的 16 个维度全部填入 120！
        // 其余 15 个 Token 全部填 0
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < D; j = j + 1) begin
                if (i == 0)
                    k_matrix_in[N*D*QK_WIDTH-1 - (i*D+j)*QK_WIDTH -: QK_WIDTH] = 8'd120;
                else
                    k_matrix_in[N*D*QK_WIDTH-1 - (i*D+j)*QK_WIDTH -: QK_WIDTH] = 8'd0;
            end
        end
        
        // 3. 打包 V 矩阵: 
        // Token 0 的 V 全是 8888 (期望输出的结果)
        // 其他 Token 的 V 给一个干扰值 1111
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                if (i == 0)
                    v_matrix_in[N*N*V_WIDTH-1 - (i*N+j)*V_WIDTH -: V_WIDTH] = 16'd8888;
                else
                    v_matrix_in[N*N*V_WIDTH-1 - (i*N+j)*V_WIDTH -: V_WIDTH] = 16'd1111;
            end
        end

        // 触发一次有效脉冲
        valid_in = 1;
        #10;
        valid_in = 0;
        
        // 数据已经在流水线深处狂飙了，我们耐心等待...
        #500;
        $display("如果看到这条消息，说明流水线堵塞，valid_out 没有拉高！");
        $finish;
    end

    // ==========================================
    // 6. 终极监视器：捕获 valid_out 与结果打印
    // ==========================================
    wire signed [OUT_WIDTH-1:0] check_attention [0:N-1];
    
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK_OUT
            assign check_attention[g] = attention_out[N*OUT_WIDTH-1 - (g*OUT_WIDTH) -: OUT_WIDTH];
        end
    endgenerate

    always @(posedge clk) begin
        if (valid_out) begin
            $display("\n🎉 [%0t] 硬件流水线计算完成！成功捕获 valid_out！", $time);
            $display("---------------------------------------------------------");
            $display(" 期望结果：由于 Token 0 的 Score 碾压，P0 约为 1.0。");
            $display(" 最终 Attention 特征应完全镜像 Token 0 的 V (即 8888)。");
            $display("---------------------------------------------------------");
            $display("Index | Final Attention Feature (Dec)");
            $display("---------------------------------------------------------");
            begin : PRINT_LOOP
                integer k;
                for (k = 0; k < N; k = k + 1) begin
                    $display(" [%2d] | %10d", k, check_attention[k]);
                end
            end
            $display("=========================================================\n");
            $finish; // 完美收工，结束仿真
        end
    end

endmodule