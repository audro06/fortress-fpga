#!/usr/bin/env python3
"""포트리스 ROM·헤더·정답 벡터 생성기.

웹 시뮬레이터(포트리스 FPGA 보드 시뮬레이터)의 JS 수식을 그대로 옮겼어요.
실행:  python3 tools/gen_roms.py      (레포 루트에서)

만드는 파일
  rom/vel_rom.mem      속도 ROM   976워드 {vx[11:0], vh[11:0]}  주소 = (각도-30)*16 + (ROM파워-1)
  rom/muzzle_rom.mem   포구 ROM    61워드 {dx[11:0], h0[11:0]}   주소 = 각도-30
  rom/cannon_rom.mem   대포 그림  488행  주소 = (각도-30)*8 + 행  (bit4 = 왼쪽 픽셀)
  rom/glyph_rom.mem    직접 만든 문자 28개 x 8행
  rom/msg_rom.mem      메시지 16바이트씩 (LCD 문자 코드, 빈칸 8'h20)
  rom/msg_len.mem      메시지 길이 1바이트씩
  rtl/include/glyph_ids.vh, rtl/include/msg_ids.vh
  sim/tb_trajectory.v  trajectory.v 정답 비교 테스트벤치
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def js_round(x):
    """JS Math.round: .5는 +무한대 쪽으로."""
    return math.floor(x + 0.5)


def hexn(v, n):
    return format(v & ((1 << (4 * n)) - 1), "X").zfill(n)


# ---------------------------------------------------------------- 탄도 ROM
VROM, MROM = [], []
for a in range(30, 91):
    r = a * math.pi / 180
    MROM.append((js_round(4 * math.cos(r) * 256), js_round((3 + 4 * math.sin(r)) * 2 * 256)))
    for p in range(1, 17):
        v = 0.55 + 0.12 * p
        VROM.append((js_round(v * math.cos(r) * 256), js_round(v * math.sin(r) * 256)))


def cannon_rows(ang):
    rows = [0, 0, 0, 0, 0, 0b11110, 0b11111, 0b01010]
    rad = ang * math.pi / 180
    t = 0.0
    while t <= 4:
        x = js_round(1 + t * math.cos(rad))
        y = js_round(4 - t * math.sin(rad))
        if 0 <= x < 5 and 0 <= y < 8:
            rows[y] |= 1 << (4 - x)
        t += 0.5
    return rows


# ---------------------------------------------------------------- 그림
def B(s):
    return [int(x, 2) for x in s.split()]


GL = {
    "p1":     B("01110 11111 01010 00100 11111 00100 01010 10001"),
    "p2":     B("10001 01110 01010 01110 00100 11111 00100 01010"),
    "cup":    B("11111 01110 01110 00100 00100 01110 11111 00000"),
    "wall2":  B("11100 10001 11011 00100 10111 10001 11101 11111"),
    "wall1":  B("00000 00000 00000 00000 01000 11010 11111 11111"),
    "lava":   B("00000 00000 00000 00100 01001 10110 11111 10101"),
    "sh1":    B("00000 10100 01010 00101 01010 10100 00000 00000"),
    "sh2":    B("00000 01110 11111 11111 11111 01110 00000 00000"),
    "sh3":    B("00100 10101 01110 11111 01110 10101 00100 00000"),
    "sh4":    B("00100 00110 01110 01111 11111 11011 01110 00000"),
}
EXP = {
    "N": ["00000 00000 00000 00000 00000 00100 01110 11111", "00000 00000 00000 00100 01110 11111 11111 11111",
          "00000 00100 10101 01110 11111 11111 01110 11111", "10001 00100 10101 01010 10101 01110 10101 11111",
          "10001 00000 10001 00100 10001 01010 10101 01010", "10000 00001 00000 10000 00001 00000 10001 00000"],
    "I": ["00000 00000 00000 00100 01110 00100 00000 00000", "00000 00100 10101 01110 11111 01110 10101 00100",
          "00100 10101 01110 11111 01110 10101 00100 00000", "10001 00100 01010 10101 01010 00100 10001 00000",
          "10001 00000 00100 01010 00100 00000 10001 00000", "00000 00000 00100 00000 00100 00000 00000 00000"],
    "F": ["00000 00000 00000 00000 00100 00100 01110 11111", "00000 00000 00100 00110 01110 01111 11111 11111",
          "00100 00110 01110 01111 11111 11011 11111 11111", "00010 00100 01100 01110 11110 11111 11011 01110",
          "00100 00110 01110 01111 11111 11011 11111 11111", "00000 00010 00100 01100 01010 10001 01010 00000"],
}
GLYPHS = [("P1", GL["p1"]), ("P2", GL["p2"]), ("CRACK", GL["wall2"]), ("RUBBLE", GL["wall1"]),
          ("LAVA", GL["lava"]), ("CUP", GL["cup"]), ("SH_X2", GL["sh1"]), ("SH_WIDE", GL["sh2"]),
          ("SH_ICE", GL["sh3"]), ("SH_FIRE", GL["sh4"])]
for k in "NIF":
    for i, g in enumerate(EXP[k]):
        GLYPHS.append((f"EXP_{k}{i}", B(g)))

# ---------------------------------------------------------------- 메시지 (16바이트씩)
MSGS = ["P1 TURN", "P2 TURN", "CPU TURN", "P1 MOVE", "P2 MOVE", "CPU MOVE", "MOVE", "DODGE", "FROZEN", "5:END",
        "DIRECT!", "HIT!", "MISS", "OUT!", "OOPS!", "BLOCKED", "WALL DOWN", "FROZEN!", "BRRR..", "BURN!", "BACKFIRE",
        "EVENT!", "LAVA!", "LOW-G!", "GUST!", "QUAKE!", "FOG!", "METEOR!", "FIRE 1ST", "NORM", "X2", "WIDE", "ICE", "FIRE",
        "FORTRESS", "P1 WINS!", "P2 WINS!", "CPU WINS!", "DRAW GAME!",
        "NO MOVE", "NORM ONLY", " PUSH 5 TO START", "SHELLS", " PUSH 5 : AGAIN "]


def msg_name(m):
    n = "MSG_" + m.strip().replace("!", "_X").replace(" ", "_").replace(":", "_").replace(".", "_").replace("-", "_")
    while "__" in n:
        n = n.replace("__", "_")
    return n.rstrip("_")


# ---------------------------------------------------------------- 탄도 정답 (goldenFlight 그대로)
G_NORM, G_LOW = 18, 11


def golden_flight(pv, d, a, p, w, g):
    mx, h0 = MROM[a - 30]
    vx, vh = VROM[(a - 30) * 16 + (p - 1)]
    x, h, vx, vh = (pv << 8) + d * mx, h0, d * vx, vh
    for t in range(1, 701):
        vx += w
        vh -= g
        x += vx
        h += vh
        px = x >> 8
        if px < -4 or px > 84:
            return t, px, 1
        if h <= 0:
            return t, px, 0
    return 700, x >> 8, 0


def golden_cases():
    conds = [(0, G_NORM), (4, G_NORM), (-5, G_NORM), (0, G_LOW), (3, G_LOW)]
    out = []
    for a in range(30, 91, 5):
        for p in (1, 6, 11, 16):
            for pv, d in ((6, 1), (73, -1)):
                # JS: (a/5 + p + ...) % 5  (a는 5의 배수라 정수)
                w, g = conds[(a // 5 + p + (0 if d > 0 else 2)) % len(conds)]
                out.append((a, p, pv, d, w, g) + golden_flight(pv, d, a, p, w, g))
    return out


def pad(used, size, word):
    """메모리 크기만큼 남는 자리를 채움 ($readmemh 가 '파일이 짧다'고 경고하지 않게)"""
    return "// unused\n" + (word + "\n") * (size - used) if size > used else ""


def write(rel, text):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote", rel)


def main():
    # 주의: $readmemh 주석은 // 만 허용돼서 모든 줄 주석을 // 로 씀
    o = "// velocity ROM, 976 words: addr = (angle-30)*16 + (rom_power-1), data = {vx[11:0], vh[11:0]} (1/256 px/tick)\n"
    for i, (vx, vh) in enumerate(VROM):
        o += hexn(vx, 3) + hexn(vh, 3) + (f"  // {30 + (i >> 4)} deg" if i % 16 == 0 else "") + "\n"
    write("rom/vel_rom.mem", o)

    o = "// muzzle ROM, 61 words: addr = angle-30, data = {muzzle_dx[11:0], h0[11:0]} (1/256 px)\n"
    for i, (mx, h0) in enumerate(MROM):
        o += hexn(mx, 3) + hexn(h0, 3) + f"  // {30 + i} deg\n"
    write("rom/muzzle_rom.mem", o)

    o = "// cannon glyph ROM: addr = (angle-30)*8 + row, 5 bits (bit4 = left). P2 cannon = bit-reversed\n"
    for a in range(30, 91):
        for y, r in enumerate(cannon_rows(a)):
            o += hexn(r, 2) + (f"  // {a} deg" if y == 0 else "") + "\n"
    write("rom/cannon_rom.mem", o + pad(61 * 8, 512, "00"))

    o = "// glyph ROM: 8 rows per glyph (bit4 = left). ids in rtl/include/glyph_ids.vh\n"
    for n, rows in GLYPHS:
        for y, r in enumerate(rows):
            o += hexn(r, 2) + (f"  // {n}" if y == 0 else "") + "\n"
    write("rom/glyph_rom.mem", o + pad(len(GLYPHS) * 8, 256, "00"))

    o = "// glyph_rom.mem 그림 번호 (자동 생성: tools/gen_roms.py). ROM 주소 = {번호, 행[2:0]}\n"
    for i, (n, _) in enumerate(GLYPHS):
        o += f"localparam [4:0] GLY_{n:<8} = 5'd{i};\n"
    write("rtl/include/glyph_ids.vh", o)

    o = "// message ROM: 16 bytes per message (LCD char codes, padded with 8'h20). addr = {id, col[3:0]}\n"
    ln = "// message length ROM: 1 byte per message\n"
    for m in MSGS:
        assert len(m) <= 16, m
        for i, ch in enumerate(m.ljust(16)):
            o += hexn(ord(ch), 2) + (f"  // {m}" if i == 0 else "") + "\n"
        ln += hexn(len(m), 2) + f"  // {m}\n"
    write("rom/msg_rom.mem", o + pad(len(MSGS) * 16, 1024, "20"))
    write("rom/msg_len.mem", ln + pad(len(MSGS), 64, "00"))

    o = "// 메시지 번호 (자동 생성: tools/gen_roms.py)\n"
    used = set()
    for i, m in enumerate(MSGS):
        n = msg_name(m)
        if n in used:
            n += f"_{i}"
        used.add(n)
        o += f"localparam [5:0] {n:<16} = 6'd{i};  // \"{m}\"\n"
    o += f"localparam        MSG_COUNT        = {len(MSGS)};\n"
    write("rtl/include/msg_ids.vh", o)

    cases = golden_cases()
    lines = []
    for (a, p, pv, d, w, g, t, px, out) in cases:
        ws = f"-8'sd{-w}" if w < 0 else f"8'sd{w}"
        lines.append(f"        check(6'd{a - 30}, 4'd{p - 1}, 1'b{1 if d < 0 else 0}, 7'd{pv}, {ws}, 8'd{g}, {t}, {px}, 1'b{out});")
    tb = TB_TEMPLATE.replace("%%VECTORS%%", "\n".join(lines)).replace("%%COUNT%%", str(len(cases)))
    write("sim/tb_trajectory.v", tb)
    write("rtl/output/sfx_rom.v", gen_sfx_rom())


# ---------------------------------------------------------------- 효과음 ROM
# 시뮬레이터 SFX 표를 음표 목록으로 옮김. 항목 = (주파수 Hz 또는 0=쉼, 길이 ms) 또는 ('noise', lo, hi, ms)
def _seq(notes, st, delay=0.0):
    out = []
    if delay:
        out.append((0, round(delay * 1000)))
    on = round(st * 0.85 * 1000)
    off = round(st * 1000) - on
    for f in notes:
        if f:
            out += [(f, on), (0, off)]
        else:
            out.append((0, round(st * 1000)))
    return out


def _sweep(f1, f2, d, n):
    step = round(d * 1000 / n)
    return [(round(f1 * (f2 / f1) ** (k / (n - 1))), step) for k in range(n)]


SFX = [  # 순서 = params.vh 의 SFX_* 번호 (0번은 비어 있음)
    ("NONE", [(0, 1)]),
    ("TICK", [(1800, 12)]),
    ("ERR", [(140, 140)]),
    ("MOVE", [(330, 40), (0, 10), (262, 40)]),
    ("FIRE", _sweep(1300, 170, 0.2, 8)),
    ("BOOM", [("noise", 50, 300, 380)]),
    ("BOOM_BIG", [("noise", 50, 220, 700)]),
    ("HIT", _seq([880, 1175, 1568], 0.07, 0.25)),
    ("MISS", _seq([392, 330], 0.1, 0.2)),
    ("ARM", _seq([660, 990], 0.06)),
    ("TURN", _seq([523, 784], 0.08)),
    ("START", _seq([392, 523, 659, 784, 1047], 0.09)),
    ("WIN", _seq([523, 659, 784, 1047, 0, 784, 1047, 1047], 0.13)),
    ("LOSE", _seq([392, 370, 349, 330, 0, 262], 0.18)),
    ("OUT", _sweep(700, 250, 0.25, 6)),
    ("FREEZE", _seq([2093, 1568, 2637, 2093], 0.05)),
    ("BURN", [("noise", 400, 1200, 350)]),
    ("HEAL", [("noise", 50, 300, 300)] + _seq([659, 784, 1047], 0.07)),
    ("ROUL", [(1500, 12)]),
    ("FANFARE", _seq([523, 659, 784, 1047, 1319], 0.07)),
    ("METEOR", _sweep(2400, 300, 0.9, 12)),
    ("SPARK", [(1500, 30)]),
    ("QUAKE", [("noise", 40, 120, 900)]),
]


def gen_sfx_rom():
    entries, starts = [], []
    for name, notes in SFX:
        starts.append((name, len(entries)))
        for i, n in enumerate(notes):
            last = 1 if i == len(notes) - 1 else 0
            if n[0] == "noise":
                _, lo, hi, ms = n
                hmin, hmax = round(500000 / hi), round(500000 / lo)
                nb = int(math.log2(hmax - hmin + 1))
                entries.append((last, 1, nb, ms, hmin, f"{name} noise {lo}-{hi}Hz"))
            else:
                f, ms = n
                half = round(500000 / f) if f else 0
                entries.append((last, 0, 0, ms, half, f"{name} {f}Hz" if f else f"{name} rest"))
    assert len(entries) <= 128, len(entries)
    for e in entries:
        assert e[3] < 1024 and e[4] < 16384, e
    o = []
    o.append("// 효과음 ROM (자동 생성: tools/gen_roms.py) - 손으로 고치지 말고 gen_roms.py의 SFX 표를 고치세요")
    o.append("// 항목 = {last[29], noise[28], mask_bits[27:24], dur_ms[23:14], half_us[13:0]}")
    o.append("//   half_us: 1MHz 기준 반주기(0이면 쉼).  noise면 half_us + (난수 & (2^mask_bits-1))")
    o.append("module sfx_rom (")
    o.append("    input  wire [4:0]  sfx_id,")
    o.append("    output reg  [6:0]  start_addr,")
    o.append("    input  wire [6:0]  addr,")
    o.append("    output reg  [29:0] entry")
    o.append(");")
    o.append("    always @(*) begin")
    o.append("        case (sfx_id)")
    for i, (name, a) in enumerate(starts):
        o.append(f"            5'd{i}: start_addr = 7'd{a};  // {name}")
    o.append("            default: start_addr = 7'd0;")
    o.append("        endcase")
    o.append("    end")
    o.append("")
    o.append("    always @(*) begin")
    o.append("        case (addr)")
    for i, (last, noise, nb, ms, half, cm) in enumerate(entries):
        o.append(f"            7'd{i}: entry = {{1'b{last}, 1'b{noise}, 4'd{nb}, 10'd{ms}, 14'd{half}}};  // {cm}")
    o.append("            default: entry = {1'b1, 1'b0, 4'd0, 10'd1, 14'd0};")
    o.append("        endcase")
    o.append("    end")
    o.append("endmodule")
    return "\n".join(o) + "\n"


TB_TEMPLATE = r"""`timescale 1ns/1ps
// trajectory.v 검증: 시뮬레이터 수식으로 만든 정답(%%COUNT%%개)과 비교 (자동 생성: tools/gen_roms.py)
// rom/vel_rom.mem, rom/muzzle_rom.mem 을 시뮬레이션 소스에 같이 추가하세요.
module tb_trajectory;
    reg clk = 1'b0, rst = 1'b1, start = 1'b0, step = 1'b0, stop = 1'b0;
    reg [5:0] angle_idx = 6'd0;
    reg [3:0] power_idx = 4'd0;
    reg dir = 1'b0;
    reg [6:0] pivot_x = 7'd0;
    reg signed [7:0] wind = 8'sd0;
    reg [7:0] grav = 8'd18;
    wire active, hit_ground, out_of_map;
    wire signed [9:0] px, py;

    trajectory dut (
        .clk(clk), .rst(rst), .start(start), .step(step), .stop(stop),
        .angle_idx(angle_idx), .power_idx(power_idx), .dir(dir), .pivot_x(pivot_x),
        .start_x(20'sd0), .start_h(20'sd0), .start_vx(20'sd0), .start_vh(20'sd0), .use_raw(1'b0),
        .wind(wind), .grav(grav),
        .active(active), .px(px), .py(py), .hit_ground(hit_ground), .out_of_map(out_of_map)
    );

    always #5 clk = ~clk;

    integer errors = 0, total = 0, t;

    task check;
        input [5:0] a;
        input [3:0] p;
        input d;
        input [6:0] pv;
        input signed [7:0] w;
        input [7:0] g;
        input integer exp_t;
        input integer exp_px;
        input exp_out;
        begin
            @(negedge clk);
            angle_idx = a; power_idx = p; dir = d; pivot_x = pv; wind = w; grav = g;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            t = 0;
            while (!(out_of_map || hit_ground) && t < 700) begin
                step = 1'b1;
                @(negedge clk);
                step = 1'b0;
                t = t + 1;
            end
            total = total + 1;
            if (t != exp_t || px != exp_px || out_of_map != exp_out) begin
                errors = errors + 1;
                $display("FAIL #%0d: angle %0d power %0d dir %0d wind %0d grav %0d -> ticks %0d (exp %0d) px %0d (exp %0d) out %0b (exp %0b)",
                         total, a + 30, p + 1, d, w, g, t, exp_t, px, exp_px, out_of_map, exp_out);
            end
            stop = 1'b1;
            @(negedge clk);
            stop = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
%%VECTORS%%
        if (errors == 0) $display("PASS: all %0d vectors match", total);
        else             $display("FAIL: %0d of %0d vectors mismatch", errors, total);
        $finish;
    end
endmodule
"""

if __name__ == "__main__":
    main()
