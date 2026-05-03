`timescale 1ns / 1ps

module recip_unit #(
    parameter SUM_WIDTH = 20,    // 输入的 Sum 位宽
    parameter LUT_ADDR_W = 8,    // 倒数 ROM 地址位宽
    parameter RECIP_WIDTH = 16   // 倒数 ROM 输出位宽 (Q0.16)
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire [SUM_WIDTH-1:0]   sum_in,
    
    output wire                   valid_out,
    output wire [RECIP_WIDTH-1:0] recip_out,
    output wire [4:0]             shift_amt_out // 必须输出，用于后端平账
);

    // ==========================================
    // 1. 实例化：前导零检测与归一化 (LZD)
    // 延迟：1 拍
    // ==========================================
    wire [LUT_ADDR_W-1:0] norm_addr;
    wire [4:0]            lzd_shift_amt;
    wire                  lzd_valid;
    
    lzd_normalize #(
        .IN_WIDTH(SUM_WIDTH), .ADDR_WIDTH(LUT_ADDR_W), .SHIFT_WIDTH(5)
    ) u_lzd_norm (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .sum_in(sum_in),
        .valid_out(lzd_valid), .norm_addr(norm_addr), .shift_amt(lzd_shift_amt)
    );

    // ==========================================
    // 2. 实例化：倒数查找表 (Reciprocal ROM)
    // 延迟：1 拍
    // ==========================================
    rom_256x16_recip u_rom_recip (
        .clk(clk),
        .addr(norm_addr),
        .dout(recip_out)  // 数据在这里耗费了第 2 拍才出来
    );

    // ==========================================
    // 3. 内部时序对齐 (Pipeline Alignment)
    // ==========================================
    // LZD 的 valid 和 shift_amt 只有 1 拍延迟，
    // 必须用寄存器打一拍，等待 ROM 的数据出来。
    reg       valid_delay;
    reg [4:0] shift_amt_delay;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_delay     <= 1'b0;
            shift_amt_delay <= 5'd0;
        end else begin
            valid_delay     <= lzd_valid;
            shift_amt_delay <= lzd_shift_amt;
        end
    end
    
    assign valid_out     = valid_delay;
    assign shift_amt_out = shift_amt_delay;

endmodule