`timescale 1ns / 1ps

module tb_softmax_front();

    // ==========================================
    // 参数定义
    // ==========================================
    parameter N = 16;
    parameter IN_WIDTH = 20;
    parameter TOTAL_IN_WIDTH = N * IN_WIDTH;
    parameter OUT_WIDTH = 16;
    
    // 我们之前测出来的 max_tree 真实延迟是 6 拍
    parameter MAX_LATENCY = 6; 

    // ==========================================
    // 信号声明
    // ==========================================
    reg                       clk;
    reg                       rst_n;
    reg                       valid_in;
    reg  [TOTAL_IN_WIDTH-1:0] data_in;
    
    // max_tree 输出
    wire signed [IN_WIDTH-1:0] max_out;
    wire                       max_valid;
    
    // sync_delay_line 输出
    wire [TOTAL_IN_WIDTH-1:0]  delayed_data_out;
    
    // sub_exp_array 输出
    wire                       exp_valid_out;
    wire [N*OUT_WIDTH-1:0]     exp_data_out;

    // ==========================================
    // 1. 例化：找最大值树
    // ==========================================
    max_tree #(
        .N(N), .WIDTH(IN_WIDTH), .STAGES(4)
    ) u_max_tree (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .data_in(data_in), .max_out(max_out), .valid_out(max_valid)
    );

    // ==========================================
    // 2. 例化：原始数据冷冻舱 (对齐 max_tree)
    // ==========================================
    sync_delay_line #(
        .DATA_WIDTH(TOTAL_IN_WIDTH), .DELAY_CYCLES(MAX_LATENCY)
    ) u_delay_line (
        .clk(clk), .rst_n(rst_n),
        .data_in(data_in), .data_out(delayed_data_out)
    );

    // ==========================================
    // 3. 例化：减法与激进查表阵列
    // ==========================================
    sub_exp_array #(
        .N(N), .IN_WIDTH(IN_WIDTH), .LUT_ADDR_W(8), .OUT_WIDTH(OUT_WIDTH)
    ) u_sub_exp (
        .clk(clk), .rst_n(rst_n), 
        .valid_in(max_valid),               // 使用 max 出来的 valid 作为流水线使能
        .row_data_in(delayed_data_out),     // 送入对齐好的 16 个原始数据
        .max_in(max_out),                   // 送入算好的最大值
        .valid_out(exp_valid_out),
        .exp_data_out(exp_data_out)
    );

    // ==========================================
    // 时钟与激励生成
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // 打包任务
    task send_row;
        input signed [IN_WIDTH-1:0] v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15;
        begin
            data_in = {v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15};
            valid_in = 1;
            #10; 
            valid_in = 0; // 发完一拍就停，方便看波形
            #10;
        end
    endtask

    initial begin
        rst_n = 0;
        valid_in = 0;
        data_in = 0;
        #35; rst_n = 1; #10;

        $display("--- 开始测试 Softmax 前端流水线 ---");
        
        // 刻意构造的测试向量：
        // Max 是 20000。
        // v0=20000 (差0) -> 预期输出 FFFF 或附近极大值
        // v1=19000 (差1000) -> 预期输出正常查表值
        // v5=3680 (差16320) -> 临界点，预期查出字典最后一页的值
        // v6=3000 (差17000) -> 预期触发 Bypass！硬件强行输出 0！
        // 后面全是负数深渊 -> 预期全部输出 0！
        send_row(20000, 19000, 15000, 10000, 5000, 3680, 3000, 0, -5000, -10000, -20000, -30000, -40000, -50000, -60000, -70000);
        
        #200;
        $display("--- 仿真结束 ---");
        $finish;
    end

    // ==========================================
    // 自动监控器：解包终极 Exp 输出
    // ==========================================
    wire [OUT_WIDTH-1:0] check_exp [0:N-1];
    wire signed [IN_WIDTH-1:0] check_orig [0:N-1];
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK_CHECK
            assign check_exp[g] = exp_data_out[N*OUT_WIDTH-1 - (g*OUT_WIDTH) : N*OUT_WIDTH-OUT_WIDTH - (g*OUT_WIDTH)];
            assign check_orig[g] = $signed(delayed_data_out[TOTAL_IN_WIDTH-1 - (g*IN_WIDTH) : TOTAL_IN_WIDTH-IN_WIDTH - (g*IN_WIDTH)]);
        end
    endgenerate

    always @(negedge clk) begin
        if (exp_valid_out) begin
            $display("=================================================");
            $display("Time = %t | Pipeline Done!", $time);
            $display("Max Found = %d", max_out);
            $display("-------------------------------------------------");
            $display("Index | Original | Exp Output (Hex) | Exp Output (Dec)");
            $display("-------------------------------------------------");
            // 这里我们用一个 for 循环打印所有 16 个通道的结果
            // 不能在 always 里直接放带 genvar 的 for，所以用 integer
            begin : PRINT_LOOP
                integer i;
                for (i = 0; i < N; i = i + 1) begin
                    $display(" [%2d] | %8d |      %04x      | %6d", 
                              i, check_orig[i], check_exp[i], check_exp[i]);
                end
            end
            $display("=================================================");
        end
    end

endmodule