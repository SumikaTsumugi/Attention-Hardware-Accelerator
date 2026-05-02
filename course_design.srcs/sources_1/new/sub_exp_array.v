`timescale 1ns / 1ps

module sub_exp_array #(
    parameter N = 16,
    parameter IN_WIDTH = 20,     // 减法前的位宽
    parameter LUT_ADDR_W = 8,    // 查表地址位宽 (256行)
    parameter OUT_WIDTH = 16     // 查表出的 exp 结果位宽
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire [N*IN_WIDTH-1:0]  row_data_in, // 对齐后的 16 个原始 Score
    input  wire signed [IN_WIDTH-1:0] max_in,  // 同步到达的最大值
    
    output reg                    valid_out,
    output wire [N*OUT_WIDTH-1:0] exp_data_out // 输出 16 个查完表的 exp 结果
);

    // ==========================================
    // 0. 解包输入数据
    // ==========================================
    wire signed [IN_WIDTH-1:0] unpk_data [0:N-1];
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK
            assign unpk_data[g] = $signed(row_data_in[N*IN_WIDTH-1 - (g*IN_WIDTH) : N*IN_WIDTH-IN_WIDTH - (g*IN_WIDTH)]);
        end
    endgenerate

    // ==========================================
    // 1. 组合逻辑：减法与激进的范围压缩
    // ==========================================
    wire [IN_WIDTH-1:0] raw_diff [0:N-1];
    wire [IN_WIDTH-1:0] shifted_diff [0:N-1];
    wire                bypass_zero [0:N-1];

    generate
        for (g = 0; g < N; g = g + 1) begin : DIFF_CALC
            // (1) 减法：最大值减去当前值，得到正数硬件差值
            assign raw_diff[g] = max_in - unpk_data[g];
            
            // (2) 极致压缩：右移 6 位，字典步长变为 64
            assign shifted_diff[g] = raw_diff[g] >> 6;
            
            // (3) 旁路判定：如果差值超过 255 页，直接标记为"直接输出 0，放弃查表"
            assign bypass_zero[g] = (shifted_diff[g] > 255);
        end
    endgenerate

    // ==========================================
    // 2. 第一级流水：地址锁存与旁路信号打拍
    // ==========================================
    reg [LUT_ADDR_W-1:0] diff_addr [0:N-1];
    reg                  bypass_reg_1 [0:N-1]; // 第 1 拍延迟
    reg                  bypass_reg_2 [0:N-1]; // 第 2 拍延迟 (对齐 ROM 输出)
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin
                diff_addr[i]    <= 0;
                bypass_reg_1[i] <= 0;
                bypass_reg_2[i] <= 0;
            end
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                // 如果越界，送 0 保护 ROM；否则送入截取的高 8 位
                diff_addr[i]    <= bypass_zero[i] ? 8'd0 : shifted_diff[i][7:0];
                
                // 【时序对齐核心】：信号像传送带一样往后传两拍
                bypass_reg_1[i] <= bypass_zero[i]; 
                bypass_reg_2[i] <= bypass_reg_1[i]; 
            end
        end
    end

    // ==========================================
    // 3. 第二级流水：ROM 查表阵列与终极 MUX 截断
    // ==========================================
    wire [OUT_WIDTH-1:0] lut_out [0:N-1];
    wire [OUT_WIDTH-1:0] final_exp [0:N-1];
    
    generate
        for (g = 0; g < N; g = g + 1) begin : ROM_ARRAY
            // 
            rom_256x16_exp u_rom (
                .clk(clk),
                .addr(diff_addr[g]),
                .dout(lut_out[g])
            );
            
            // 硬件旁路清零：bypass 信号与 ROM 数据完美在第 2 拍相遇！
            assign final_exp[g] = bypass_reg_2[g] ? 16'd0 : lut_out[g];
        end
    endgenerate

    // ==========================================
    // 4. 打包输出与 Valid 同步延迟 (总延迟 = 2 拍)
    // ==========================================
    reg valid_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_shift <= 0;
            valid_out   <= 1'b0;
        end else begin
            valid_shift <=  valid_in;
            valid_out   <= valid_shift;
        end
    end

    generate
        for (g = 0; g < N; g = g + 1) begin : PACK
            assign exp_data_out[N*OUT_WIDTH-1 - (g*OUT_WIDTH) : N*OUT_WIDTH-OUT_WIDTH - (g*OUT_WIDTH)] = final_exp[g];
        end
    endgenerate

endmodule