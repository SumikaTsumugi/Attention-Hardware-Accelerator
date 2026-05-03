`timescale 1ns / 1ps

module tb_softmax_front_exp();

    // ==========================================
    // 参数定义
    // ==========================================
    parameter N = 16;
    parameter IN_WIDTH = 20;
    parameter EXP_WIDTH = 16;
    parameter TOTAL_IN_WIDTH = N * IN_WIDTH;

    // ==========================================
    // 信号声明
    // ==========================================
    reg                       clk;
    reg                       rst_n;
    reg                       valid_in;
    reg  [TOTAL_IN_WIDTH-1:0] row_data_in;
    
    wire                      valid_out;
    wire [N*EXP_WIDTH-1:0]    exp_data_out;

    // ==========================================
    // 1. 例化待测目标 (DUT: Device Under Test)
    // ==========================================
    softmax_front_exp #(
        .N(N), 
        .IN_WIDTH(IN_WIDTH), 
        .LUT_ADDR_W(8), 
        .OUT_WIDTH(EXP_WIDTH), 
        .MAX_LATENCY(6)
    ) u_dut_front (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(valid_in), 
        .row_data_in(row_data_in),
        
        .valid_out(valid_out), 
        .exp_data_out(exp_data_out)
    );

    // ==========================================
    // 时钟生成 (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // 数据发送任务 (打包 16 个通道)
    // ==========================================
    task send_row;
        input signed [IN_WIDTH-1:0] v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15;
        begin
            row_data_in = {v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15};
            valid_in = 1;
            #10; 
            valid_in = 0; // 只发一拍有效数据
            #10;
        end
    endtask

    // ==========================================
    // 激励生成模块
    // ==========================================
    initial begin
        rst_n = 0;
        valid_in = 0;
        row_data_in = 0;
        
        #35; rst_n = 1; #10;

        $display("--- 开始测试 softmax_front_exp 模块 ---");
        
        // 刻意构造跨度极大的测试向量 (沿用你之前的经典测试集)
        send_row(20000, 19000, 15000, 10000, 5000, 3680, 3000, 0, -5000, -10000, -20000, -30000, -40000, -50000, -60000, -70000);
        
        // 留出足够的时间让流水线跑完
        #150;
        $display("--- 仿真结束 ---");
        $finish;
    end

    // ==========================================
    // 自动监控器：精确抓取与打印
    // ==========================================
    
    // 【TB特供移位寄存器】：为了在控制台里把输入输出拼在一起显示
    // 模块内部延迟是 8 拍 (max_tree 6拍 + sub_exp 2拍)
    // 我们在这里把原始数据同步延迟 8 拍
    reg [TOTAL_IN_WIDTH-1:0] tb_delay_pipe [0:8];
    integer i;
    always @(posedge clk) begin
        tb_delay_pipe[0] <= row_data_in;
        for(i = 1; i <= 8; i = i + 1) begin
            tb_delay_pipe[i] <= tb_delay_pipe[i-1];
        end
    end

    // 解包总线数据
    wire [EXP_WIDTH-1:0] check_exp [0:N-1];
    wire signed [IN_WIDTH-1:0] check_orig [0:N-1];
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK_CHECK
            // 提取输出的指数
            assign check_exp[g] = exp_data_out[N*EXP_WIDTH-1 - (g*EXP_WIDTH) : N*EXP_WIDTH-EXP_WIDTH - (g*EXP_WIDTH)];
            // 提取被监视器延迟了 8 拍的原始数据
            assign check_orig[g] = $signed(tb_delay_pipe[8][TOTAL_IN_WIDTH-1 - (g*IN_WIDTH) : TOTAL_IN_WIDTH-IN_WIDTH - (g*IN_WIDTH)]);
        end
    endgenerate

    // 抓取 valid_out 下降沿 (或者直接抓高电平)，打印结果
    always @(negedge clk) begin
        if (valid_out) begin
            $display("=================================================");
            $display("Time = %t | softmax_front_exp 计算完成!", $time);
            $display("-------------------------------------------------");
            $display("Index | Original Input | Exp Output (Hex) | Exp Output (Dec)");
            $display("-------------------------------------------------");
            begin : PRINT_LOOP
                integer j;
                for (j = 0; j < N; j = j + 1) begin
                    $display(" [%2d] |   %10d   |      %04x      | %6d", 
                              j, check_orig[j], check_exp[j], check_exp[j]);
                end
            end
            $display("=================================================");
        end
    end

endmodule