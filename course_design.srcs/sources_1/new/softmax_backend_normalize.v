`timescale 1ns / 1ps

module softmax_backend_normalize #(
    parameter N = 16,
    parameter IN_WIDTH = 16,     // e^x 的位宽
    parameter SUM_WIDTH = 20,    // Adder Tree 输出的位宽
    parameter PROB_WIDTH = 16    // 最终输出的概率位宽 【极致升级：Q0.16 格式】
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire [N*IN_WIDTH-1:0]  exp_data_in,  
    
    output reg                    valid_out,
    output wire [N*PROB_WIDTH-1:0] prob_data_out 
);

    // ==========================================
    // 1. 加法树 & 2. 倒数引擎 & 3. 延迟线 
    // (逻辑保持完美，直接复用)
    // ==========================================
    wire [SUM_WIDTH-1:0] sum_out;
    wire                 sum_valid;
    adder_tree #(.N(N), .IN_WIDTH(IN_WIDTH), .OUT_WIDTH(SUM_WIDTH), .STAGES(4)) u_adder_tree (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .data_in(exp_data_in),
        .sum_out(sum_out), .valid_out(sum_valid)
    );

    wire [15:0] recip_out;
    wire [4:0]  shift_amt;
    wire        recip_valid;
    recip_unit #(.SUM_WIDTH(SUM_WIDTH), .LUT_ADDR_W(8), .RECIP_WIDTH(16)) u_recip_unit (
        .clk(clk), .rst_n(rst_n), .valid_in(sum_valid), .sum_in(sum_out),
        .valid_out(recip_valid), .recip_out(recip_out), .shift_amt_out(shift_amt)
    );

    wire [N*IN_WIDTH-1:0] delayed_exp_data;
    sync_delay_line #(.DATA_WIDTH(N*IN_WIDTH), .DELAY_CYCLES(7)) u_delay_line (
        .clk(clk), .rst_n(rst_n), .data_in(exp_data_in), .data_out(delayed_exp_data)
    );

    // ==========================================
    // 4. 第一级计算流水：DSP 乘法阵列与移位量预计算 (Cycle 8)
    // ==========================================
    wire [IN_WIDTH-1:0] unpk_exp [0:N-1];
    reg  [31:0]         product_arr [0:N-1];
    reg  [4:0]          shift_down_amt;
    reg                 mult_valid;
    
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : UNPACK_DELAYED
            assign unpk_exp[g] = delayed_exp_data[N*IN_WIDTH-1 - (g*IN_WIDTH) : N*IN_WIDTH-IN_WIDTH - (g*IN_WIDTH)];
        end
    endgenerate

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) product_arr[i] <= 32'd0;
            shift_down_amt <= 5'd0;
            mult_valid     <= 1'b0;
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                product_arr[i] <= unpk_exp[i] * recip_out; 
            end
            // 【回归 19】：由于输出从 Q1.15 升级为 Q0.16，目标倍数变大，右移位数退回 19
            //这里的19是一个很关键的数，19=19+16-16
            shift_down_amt <= 5'd19 - shift_amt; 
            mult_valid     <= recip_valid;
        end
    end

    // ==========================================
    // 5. 第二级计算流水：桶形右移与【终极饱和截断】 (Cycle 9)
    // ==========================================
    reg [PROB_WIDTH-1:0] final_prob_arr [0:N-1];
    wire [31:0]          shifted_val [0:N-1]; // 用于暂存移位后的 32 位结果
    
    generate
        for (g = 0; g < N; g = g + 1) begin : SHIFT_CALC
            assign shifted_val[g] = product_arr[g] >> shift_down_amt;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) final_prob_arr[i] <= 16'd0;
            valid_out <= 1'b0;
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                // 【架构核心：硬件级饱和截断】
                // 如果移位后的结果大于等于 65535 (16'hFFFF)，强行拉平到 FFFF
                // 彻底防止 1.0 (65536) 溢出变成 0000 的灾难！
                if (shifted_val[i] >= 32'h0000_FFFF)
                    final_prob_arr[i] <= 16'hFFFF;
                else
                    final_prob_arr[i] <= shifted_val[i][15:0];
            end
            valid_out <= mult_valid;
        end
    end

    generate
        for (g = 0; g < N; g = g + 1) begin : PACK_OUT
            assign prob_data_out[N*PROB_WIDTH-1 - (g*PROB_WIDTH) : N*PROB_WIDTH-PROB_WIDTH - (g*PROB_WIDTH)] = final_prob_arr[g];
        end
    endgenerate

endmodule