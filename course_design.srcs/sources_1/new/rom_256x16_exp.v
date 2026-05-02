`timescale 1ns / 1ps

module rom_256x16_exp (
    input  wire         clk,
    input  wire  [7:0]  addr,  // 8-bit 地址线，对应 256 行
    output  reg   [15:0] dout   // 16-bit 数据线，对应查出的 e^x
);

    // 定义一个深度为 256，宽度为 16 的二维寄存器阵列
    reg [15:0] memory [0:255];

    // 在 FPGA 上电或复位时，将 MATLAB 算好的 txt 烧录进这个阵列
    initial begin
        $readmemh("Exp_LUT.txt", memory);
    end

    // 单端口 ROM 的标准读取逻辑：自带 1 拍延迟 (提升时钟频率)
    always @(posedge clk) begin
        dout <= memory[addr];
    end

endmodule