`timescale 1ns / 1ps

module sync_delay_line #(
    parameter DATA_WIDTH = 320,  // 16 个 20-bit 拼接总线
    parameter DELAY_CYCLES = 5   // 需要延迟的拍数 (对齐 max_tree)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] data_in,
    output wire [DATA_WIDTH-1:0] data_out
);

    // 定义二维移位寄存器阵列
    reg [DATA_WIDTH-1:0] shift_reg [0:DELAY_CYCLES-1];
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DELAY_CYCLES; i = i + 1) begin
                shift_reg[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // 第 0 级吃进新数据
            shift_reg[0] <= data_in;
            // 第 1 到 N 级像传送带一样往后传
            for (i = 1; i < DELAY_CYCLES; i = i + 1) begin
                shift_reg[i] <= shift_reg[i-1];
            end
        end
    end

    // 最后一级作为输出
    assign data_out = shift_reg[DELAY_CYCLES-1];

endmodule