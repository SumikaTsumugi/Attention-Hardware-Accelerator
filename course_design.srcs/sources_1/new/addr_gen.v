`timescale 1ns / 1ps

module addr_gen #(
    parameter ADDR_WIDTH = 4,
    parameter MAX_ADDR   = 15
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    
    output wire                  bram_ena,
    output reg  [ADDR_WIDTH-1:0] addr,
    output reg                   valid_out
);

    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam DONE = 2'b10;
    
    reg [1:0] current_state, next_state;

    // ==============================================
    // 1. 状态机：状态跳转 (时序逻辑)
    // ==============================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    // ==============================================
    // 2. 状态机：下一状态判定 (纯组合逻辑)
    // ==============================================
    always @(*) begin
        next_state = current_state; // 防 Latch
        case (current_state)
            IDLE: if (start) next_state = READ;
            READ: if (addr == MAX_ADDR) next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end

    // ==============================================
    // 3. 数据通路：使能控制 (基于当前状态)
    // 只要系统处于 READ 状态，BRAM 使能就一直拉高
    // ==============================================
    assign bram_ena = (current_state == READ);

    // ==============================================
    // 4. 数据通路：地址发生器核心
    // ==============================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr <= 0;
        end else begin
            if (current_state == IDLE) begin
                addr <= 0; // 重点：在 IDLE 状态时，把地址死死按在 0 上
            end else if (current_state == READ) begin
                if (addr < MAX_ADDR)
                    addr <= addr + 1; // 进入 READ 的下个周期才开始加 1
            end
        end
    end

    // ==============================================
    // 5. 硬件流水线对齐：修复 BRAM 一拍延迟
    // ==============================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else begin
            // 绝妙的打拍技巧：
            // 当 current_state == READ 时，BRAM 正在吃这一拍的地址
            // 在下一个时钟沿，BRAM 吐出数据，同时这行代码将 valid_out 拉高
            // 使得 valid_out 和 q_data 在时间轴上实现 100% 完美对齐！
            valid_out <= (current_state == READ);
        end
    end

endmodule