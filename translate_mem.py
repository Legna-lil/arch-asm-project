import re
from pathlib import Path

FILE_DIR = "Lab2.file\\"
# 文件路径设置
in_path = Path(FILE_DIR + "mem.hex")
out_path = Path(FILE_DIR + "mem_clean.hex")

# 匹配 0x 格式的十六进制数
hex_pattern = re.compile(r'0x[0-9a-fA-F]+')

all_data = []

if in_path.exists():
    lines = in_path.read_text().splitlines()
    for line in lines:
        tokens = hex_pattern.findall(line)
        if len(tokens) > 1:
            # tokens[0] 是地址，忽略它；tokens[1:] 是 8 个数据字
            for val in tokens[1:]:
                # 去掉 0x，转为小写并补齐 8 位
                clean_val = val.replace('0x', '').lower().zfill(8)
                all_data.append(clean_val)

# 找到最后一个非零数据的位置
last_nonzero_idx = -1
for i, val in enumerate(all_data):
    if int(val, 16) != 0:
        last_nonzero_idx = i

# 只保留到最后一个非零元素
if last_nonzero_idx != -1:
    clean_data = all_data[:last_nonzero_idx + 1]
else:
    clean_data = []

# 写入文件
out_path.write_text('\n'.join(clean_data) + '\n', encoding='ascii')
print(f"处理完成！提取了 {len(clean_data)} 条数据到 {out_path}")