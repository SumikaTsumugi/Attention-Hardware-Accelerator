`timescale 1ns / 1ps

module tb_softmax_backend_normalize();

    // ==========================================
    // 参数定义
    // ==========================================
    parameter N = 16;
    parameter IN_WIDTH = 16;      // 输入 e^x 位宽
    parameter SUM_WIDTH = 20;     // Adder Tree 总和位宽
    parameter PROB_WIDTH = 16;    // 输出概率位宽 (Q1.15)
    parameter TOTAL_IN_WIDTH = N * IN_WIDTH;

    // ==========================================
    // 信号声明
    // ==========================================
    reg                       clk;
    reg                       rst_n;
    reg                       valid_in;
    reg  [TOTAL_IN_WIDTH-1:0] exp_data_in;
    
    wire                      valid_out;
    wire [N*PROB_WIDTH-1:0]   prob_data_out;

    // ==========================================
    // 1. 例化待测目标 (DUT)
    // 模块总延迟：9 个时钟周期
    // ==========================================
    softmax_backend_normalize #(
        .N(N), .IN_WIDTH(IN_WIDTH), .SUM_WIDTH(SUM_WIDTH), .PROB_WIDTH(PROB_WIDTH)
    ) u_dut_backend (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(valid_in), 
        .exp_data_in(exp_data_in),
        
        .valid_out(valid_out), 
        .prob_data_out(prob_data_out)
    );

    // ==========================================
    // 时钟生成 (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // 数据发送任务
    // ==========================================
    task send_exp_row;
        input [IN_WIDTH-1:0] v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15;
        begin
            exp_data_in = {v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15};
            valid_in = 1;
            #10; 
            valid_in = 0;
            #10;
        end
    endtask

    // ==========================================
    // 激励生成模块
    // ==========================================
    initial begin
        rst_n = 0;
        valid_in = 0;
        exp_data_in = 0;
        
        #35; rst_n = 1; #10;

        $display("--- 开始测试 softmax_backend_normalize (Q0.16 倒数优化版) ---");
        
        // 向量 1：绝对平均 (16 个通道全是 1000)
        // 期望：每个通道占比 1/16 = 0.0625。Q1.15下值为: 32768 * 0.0625 = 2048 (16'h0800)
        send_exp_row(1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000);
        
        // 向量 2：一家独大 (模拟模型极度自信的情况)
        // Sum = 65000 + 15*10 = 65150. P0 ≈ 0.9977 (期望 Q1.15值 ≈ 32692)
        send_exp_row(65000, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10);
        
        // 向量 3：随机阶梯 (验证不同大小的数混合时的移位平账准确性)
        send_exp_row(60000, 30000, 15000, 8000, 4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 0);
        
        #200;
        $display("--- 仿真结束 ---");
        $finish;
    end

    // ==========================================
    // 自动监控器：精确抓取与打印
    // ==========================================
    
    // 【TB特供移位寄存器】：模块内部延迟是 9 拍
    // 我们在这里把输入的 e^x 延迟 9 拍，用于对齐输出结果
    reg [TOTAL_IN_WIDTH-1:0] tb_delay_pipe [0:9];
    integer i;
    always @(posedge clk) begin
        tb_delay_pipe[0] <= exp_data_in;
        for(i = 1; i <= 9; i = i + 1) begin
            tb_delay_pipe[i] <= tb_delay_pipe[i-1];
        end
    end

    // 解包总线数据
    wire [PROB_WIDTH-1:0] check_prob [0:N-1];
    wire [IN_WIDTH-1:0]   check_exp_in [0:N-1];
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK_CHECK
            assign check_prob[g] = prob_data_out[N*PROB_WIDTH-1 - (g*PROB_WIDTH) : N*PROB_WIDTH-PROB_WIDTH - (g*PROB_WIDTH)];
            assign check_exp_in[g] = tb_delay_pipe[9][TOTAL_IN_WIDTH-1 - (g*IN_WIDTH) : TOTAL_IN_WIDTH-IN_WIDTH - (g*IN_WIDTH)];
        end
    endgenerate

    // 抓取并打印，同时计算所有通道概率总和！
    always @(negedge clk) begin
        if (valid_out) begin : PRINT_BLOCK  // <--- 核心修改：给 begin 加个名字！
            integer j;
            reg [31:0] prob_sum; // 用于验证总和是否为 1.0 (32768)
            prob_sum = 0;
            
            $display("=================================================");
            $display("Time = %t | 后端归一化计算完成!", $time);
            $display("-------------------------------------------------");
            $display("Index | Input e^x | Final Prob (Dec) | Prob (Float)");
            $display("-------------------------------------------------");
            
            for (j = 0; j < N; j = j + 1) begin
                prob_sum = prob_sum + check_prob[j];
                // 打印出浮点数视角，方便人类阅读
                $display(" [%2d] |   %5d   |      %5d       |   %f", 
                          j, check_exp_in[j], check_prob[j], check_prob[j] / 65536.0);
            end
            $display("-------------------------------------------------");
            $display(">>> PROBABILITY SUM (Q0.16) = %d (Expected: ~65536) <<<", prob_sum);
            $display(">>> PROBABILITY SUM (Float) = %f", prob_sum / 65536.0);
            $display("=================================================\n");
        end
    end

endmodule