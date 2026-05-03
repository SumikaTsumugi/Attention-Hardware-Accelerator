% ---------------------------------------------------------
% 极致版：基于隐藏位优化 & 16-bit 满精度的倒数查找表
% ---------------------------------------------------------

LUT_SIZE = 256;         
OUT_WIDTH = 16;         

% 听从你的建议，改为保留 16 位小数 (放大 65536 倍)
SCALE_RECIP = 2^16;     

recip_lut = zeros(LUT_SIZE, 1);
file_path = '.\course_design.srcs\sources_1\new\Recip_LUT.txt';
fileID_lut = fopen(file_path, 'w');

fprintf(fileID_lut, '// Reciprocal Look-Up Table (Optimized with Implicit Bit)\n');
fprintf(fileID_lut, '// Size: %d, Output Format: Unsigned Q0.16 (Saturated)\n', LUT_SIZE);

for i = 0 : (LUT_SIZE - 1)
    % 还原真实的归一化数字 (1.xxxx)
    real_val = 1 + (double(i) / LUT_SIZE); 
    
    % 计算真实倒数
    real_recip = 1.0 / real_val;
    
    % 定点化：放大 65536 倍并四舍五入
    quantized_recip = round(real_recip * SCALE_RECIP);
    
    % 【关键】：由于 1.0 * 65536 = 65536 (17-bit)，必须饱和截断到 65535
    if quantized_recip > (2^OUT_WIDTH - 1)
        quantized_recip = 2^OUT_WIDTH - 1;
    end
    
    recip_lut(i+1) = quantized_recip;
    
    % 以 16-bit 16进制格式写入
    fprintf(fileID_lut, '%04x\n', quantized_recip);
end

fclose(fileID_lut);
disp(['Recip_LUT.txt 生成成功！路径: ', file_path]);
disp('已升级为 16-bit 满精度 Q0.16 格式，溢出保护生效！');