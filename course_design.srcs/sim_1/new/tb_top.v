`timescale 1ns / 1ps

module tb_top_datapath();

    // 信号声明
    reg          clk;
    reg          rst_n;
    reg          start;
    
    wire signed [19:0] final_dot_product;
    wire               final_valid;

    // 实例化待测系统 (DUT)
    top_datapath #(
        .DATA_WIDTH(128),
        .ADDR_WIDTH(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .final_dot_product(final_dot_product),
        .final_valid(final_valid)
    );

    // 生成 100MHz 时钟
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // 测试激励逻辑
    initial begin
        rst_n = 0;
        start = 0;
        #100;
        rst_n = 1; 
        #20;

        // 启动计算
        $display("--- 硬件计算开始 ---");
        start = 1;
        #10; 
        start = 0;

        // 我们设置一个超时保护，防止仿真死循环
        #500;
        $display("--- 仿真结束 ---");
        $finish;
    end

    // 自动监控：当结果有效时，在控制台打印十六进制结果
    always @(negedge clk) begin
        if (final_valid) begin
            $display("Time=%t | Dot Product Result (Hex): %h | (Dec): %d", 
                      $time, final_dot_product, final_dot_product);
        end
    end

endmodule