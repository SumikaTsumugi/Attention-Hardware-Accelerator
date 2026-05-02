LUT_SIZE = 256;         
LUT_FRAC_BITS = 16;     

% 量化因子
SCALE_Q = 32;
SCALE_K = 32;
MAC_SCALE = SCALE_Q * SCALE_K; % 1024
SQRT_DK = 4;
TOTAL_DIVISOR = MAC_SCALE * SQRT_DK; % 4096

ADDR_SHIFT = 6; %硬件移位
HW_STEP = 2^ADDR_SHIFT; % 64

exp_lut = zeros(LUT_SIZE, 1);
file_path = '.\course_design.srcs\sources_1\new\Exp_LUT.txt';
fileID_lut = fopen(file_path, 'w');

fprintf(fileID_lut, '// Exp(x) LUT (16-bit Precision, Dynamic Range Fixed)\n');
fprintf(fileID_lut, '// hw_step = %d, total_divisor = %d\n', HW_STEP, TOTAL_DIVISOR);
fprintf(fileID_lut, '// True offset = -(addr * %d) / %d\n', HW_STEP, TOTAL_DIVISOR);

for i = 0 : (LUT_SIZE - 1)
    % 完美的浮点映射公式： i * 64 / 4096 = i / 64
    real_x = -double(i * HW_STEP) / TOTAL_DIVISOR; 
    real_exp = exp(real_x);
    
    quantized_exp = round(real_exp * (2^LUT_FRAC_BITS));
    
    % 完美的边界饱和保护
    if quantized_exp > (2^LUT_FRAC_BITS - 1)
        quantized_exp = (2^LUT_FRAC_BITS - 1); 
    end
    
    exp_lut(i+1) = quantized_exp;
    fprintf(fileID_lut, '%04x\n', quantized_exp); 
end

fclose(fileID_lut);
disp('究极体 Exp_LUT.txt 已生成！动态范围已完美铺满！');