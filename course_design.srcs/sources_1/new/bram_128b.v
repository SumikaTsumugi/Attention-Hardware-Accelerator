`timescale 1ns / 1ps

module bram_128b #(
    parameter DATA_WIDTH = 128,  // 16个 INT8 拼接 = 128 bits
    parameter ADDR_WIDTH = 4,    // 深度为 16，所以地址位宽 4 bits (2^4=16)
    parameter INIT_FILE = "Q_input.txt" // 初始化文件路径
)(
    input  wire                  clk,
    input  wire                  ena,   // RAM 使能信号
    input  wire                  wea,   // 写使能信号 (Write Enable)
    input  wire [ADDR_WIDTH-1:0] addra, // 读/写地址
    input  wire [DATA_WIDTH-1:0] dina,  // 写入数据
    output reg  [DATA_WIDTH-1:0] douta  // 读出数据
);

    // 声明核心存储器变量：16 个 128-bit 的寄存器数组
    reg [DATA_WIDTH-1:0] ram_block [0:(1<<ADDR_WIDTH)-1];

    // 重点：使用 initial 块和 $readmemh 读取 MATLAB 生成的测试激励
    // 注意：这在 FPGA 综合时会被映射为 BRAM 的初始值，非常适合原型验证
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram_block);
        end
    end

    // 同步读写逻辑
    always @(posedge clk) begin
        if (ena) begin
            if (wea) begin
                ram_block[addra] <= dina;
            end
            // 无论是否写入，douta 都会在一个时钟周期后输出当前地址的数据 (Read-First)
            douta <= ram_block[addra];
        end
    end

endmodule