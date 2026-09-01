import re
from pathlib import Path

FILE_DIR = "Lab2.file\\"
in_path = Path(FILE_DIR + "inst_code.hex")
out_path = Path(FILE_DIR + "inst_code_clean.hex")

hex_pat = re.compile(r'0x[0-9A-Fa-f]{8}|\b[0-9A-Fa-f]{8}\b')

out_lines = []
for line in in_path.read_text(encoding="utf-8", errors="ignore").splitlines():
    tokens = hex_pat.findall(line)
    if len(tokens) >= 2:
        out_lines.append(tokens[1].replace("0x", ""))
    elif len(tokens) == 1:
        out_lines.append(tokens[0].replace("0x", ""))

out_path.write_text("\n".join(out_lines) + "\n", encoding="ascii")