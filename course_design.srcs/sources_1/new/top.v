`timescale 1ns / 1ps

module top_datapath #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    
    output wire signed [19:0] final_dot_product, // 最终输出的点积结果
    output wire               final_valid        // 结果有效标志
);

    // 内部连线
    wire                  w_bram_ena;
    wire [ADDR_WIDTH-1:0] w_bram_addr;
    wire                  w_q_valid_pre; // 经过打拍对齐后的数据有效信号
    
    wire [DATA_WIDTH-1:0] w_q_bus;
    wire [DATA_WIDTH-1:0] w_k_bus;

    // 1. 实例化地址发生器
    addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MAX_ADDR(15)
    ) u_addr_gen (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .bram_ena   (w_bram_ena),
        .addr       (w_bram_addr),
        .valid_out  (w_q_valid_pre) 
    );

    // 2. 实例化 Q 存储器
    bram_128b #(.INIT_FILE("Q_input.txt")) u_bram_q (
        .clk(clk), .ena(w_bram_ena), .wea(1'b0), .addra(w_bram_addr), .dina(128'd0), .douta(w_q_bus)
    );

    // 3. 实例化 K 存储器
    bram_128b #(.INIT_FILE("K_input.txt")) u_bram_k (
        .clk(clk), .ena(w_bram_ena), .wea(1'b0), .addra(w_bram_addr), .dina(128'd0), .douta(w_k_bus)
    );

    // 4. 实例化心脏：MAC 阵列
    mac_array_16 u_mac_array (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (w_q_valid_pre), // 使用对齐后的有效信号
        .q_vec      (w_q_bus),
        .k_vec      (w_k_bus),
        .dot_result (final_dot_product),
        .valid_out  (final_valid)
    );

endmodule