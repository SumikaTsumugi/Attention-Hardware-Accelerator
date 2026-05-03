`timescale 1ns / 1ps

module lzd_normalize #(
    parameter IN_WIDTH = 20,     // Sum 的位宽
    parameter ADDR_WIDTH = 8,    // 送给 ROM 的地址位宽
    parameter SHIFT_WIDTH = 5    // 移位记录的位宽 (log2(20)向上取整 = 5)
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire [IN_WIDTH-1:0]    sum_in,
    
    output reg                    valid_out,
    output reg  [ADDR_WIDTH-1:0]  norm_addr, // 归一化后截取的次高位往后 8 位 (去查倒数表)
    output reg  [SHIFT_WIDTH-1:0] shift_amt  // 记录左移了多少位 (极其重要，后面要用！)
);

    // 1. 组合逻辑：计算前导零个数，优先编码器
    reg [SHIFT_WIDTH-1:0] leading_zeros;
    integer i;
    
    always @(*) begin
        // 默认情况（如果全0，防错处理）
        leading_zeros = 5'd0; 
        
        // 倒序遍历：从最低位查到最高位。
        // 最后一次覆盖 leading_zeros 的，一定是最高位的 1！
        for (i = 0; i < IN_WIDTH; i = i + 1) begin
            if (sum_in[i] == 1'b1) begin
                leading_zeros = (IN_WIDTH - 1) - i;
            end
        end
    end

    // 2. 组合逻辑：执行左移归一化 (Barrel Shifter)
    wire [IN_WIDTH-1:0] shifted_sum;
    assign shifted_sum = sum_in << leading_zeros;

    // 3. 时序逻辑：打拍输出截取的地址 和 移位量
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            norm_addr <= 8'd0;
            shift_amt <= 5'd0;
        end else begin
            valid_out <= valid_in;
		//输出次高位往后的8位，因为最高位一定为1
            norm_addr <= shifted_sum[IN_WIDTH-2 : IN_WIDTH-ADDR_WIDTH-1]; 
            // 必须把左移的位数保存下来，像"接力棒"一样传给下一级
            shift_amt <= leading_zeros;
        end
    end

endmodule