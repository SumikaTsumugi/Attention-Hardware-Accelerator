function [Q_int8, K_int8, V_int8, output_fp32] = attention_golden_model(L, d_k)
    % 如果未输入参数，默认使用 L=16, d_k=16
    if nargin < 2
        L = 16;
        d_k = 16;
    end

    % 1. 生成随机 FP32 输入 (模拟真实特征)
    % randn 生成标准正态分布的浮点数
    Q_fp32 = randn(L, d_k);
    K_fp32 = randn(L, d_k);
    V_fp32 = randn(L, d_k);

    % 2. FP32 参考计算
    % 矩阵相乘：K_fp32' 是 K 的转置
    scores = (Q_fp32 * K_fp32') / sqrt(d_k);

    % Softmax 计算 (按行减去最大值防溢出)
    % max(scores, [], 2) 表示求每一行 (维度2) 的最大值
    max_scores = max(scores, [], 2);
    e_scores = exp(scores - max_scores);
    probs = e_scores ./ sum(e_scores, 2);

    % 最终融合输出
    output_fp32 = probs * V_fp32;

    % 3. 定点化量化 (INT8)
    % 假设量化系数为 32 (即 1.0 对应硬件里的 32)
    scale = 32;

    % MATLAB 的 int8() 自带四舍五入(round)规则，且会自动进行饱和截断(Saturate to [-128, 127])
    % 实际上保存的是原本数据的3位整数加5位小数，被放大了32倍
    Q_int8 = int8(round(Q_fp32 * scale));
    K_int8 = int8(round(K_fp32 * scale));
    V_int8 = int8(round(V_fp32 * scale));
end

% ==========================================
% 主程序脚本 (可以直接接在同一个文件下方运行)
% ==========================================

% 调用函数生成数据
rng(42);            %保证结果可复现
[Q, K, V, output_fp32] = attention_golden_model(16, 16);

% --- 导出为 Vivado 可读的十六进制格式 (.txt) ---
% 打开文件准备写入
fileID = fopen('.\course_design.srcs\sim_1\new\Q_input.txt', 'w');
fprintf(fileID, '// Q Matrix 128-bit Hex Test Vector (16 rows x 16 bytes)\n');

L=16;
d_k=16;

% 逐行遍历 Q 矩阵
for i = 1:L
    % 取出第 i 行的数据 (16 个 INT8 元素)
    row_data = typecast(Q(i, :), 'uint8');
    
    % 在同一行内，连续打印这 16 个字节，不加空格和换行
    for j = 1:d_k
        fprintf(fileID, '%02x', row_data(j));
    end
    
    % 这 16 个字节（即一个 128-bit 的数据词）拼完后，再换行
    fprintf(fileID, '\n');
end

fclose(fileID);
disp('128-bit 位宽对齐的 Q_input.txt 已重新生成！');


% 生成 K 的 128-bit 仿真文件
fileID_K = fopen('.\course_design.srcs\sim_1\new\K_input.txt', 'w');
fprintf(fileID_K, '// K Matrix 128-bit Hex\n');
for i = 1:L
    row_data_k = typecast(K(i, :), 'uint8');
    for j = 1:d_k
        fprintf(fileID_K, '%02x', row_data_k(j));
    end
    fprintf(fileID_K, '\n');
end
fclose(fileID_K);
disp('K_input.txt 已生成，请将其也加入 Vivado 仿真源。');