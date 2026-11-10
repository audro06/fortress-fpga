"""fortress_top 을 minisim 으로 돌리는 테스트 도우미 (tools/sim_tests.py 가 씀)

시뮬레이션을 빠르게 하려고 CLK_HZ 를 1200 으로 줄여서 돌려요 (1틱 = 40클럭, 1 ms = 1클럭).
게임 로직은 틱 기준이라 그대로이고, 서보·Piezo·LCD 처럼 실제 시간(us)이 중요한 모듈은
sim_tests.py 에서 1 MHz 로 따로 검사해요.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from minisim import Sim, _ts      # noqa: E402
import gen_roms                   # noqa: E402

ST = ["TITLE", "INTRO", "AIM", "CHARGE", "FLIGHT", "IMPACT", "RESULT", "MOVE", "METEOR", "OVER", "START", "NEXT"]
KEYS = "123456789*0#"
SHELL = {"normal": 0, "double": 1, "wide": 2, "ice": 3, "fire": 4}
SHELL_KEY = {1: "1", 2: "3", 3: "7", 4: "9"}
SYM = {0: "A", 1: "/", 2: "B", 3: "\\", 4: "%", 5: ":", 6: "~", 7: "@", 0xFF: "#", 0xA5: "'", 0xDF: "d", 0x20: " "}
SEGCH = {0b1111110: "0", 0b0110000: "1", 0b1101101: "2", 0b1111001: "3", 0b0110011: "4", 0b1011011: "5",
         0b1011111: "6", 0b1110000: "7", 0b1111111: "8", 0b1111011: "9", 0: " ", 0b0000001: "-",
         0b1100111: "P", 0b0001110: "L", 0b1110111: "A", 0b0111011: "y", 0b1001111: "E"}


class Game:
    TICK = 40

    def __init__(self, dip="10011011", randinit=None, sensor=1, skew=0):
        """dip: DIP1..DIP8 순서 문자열 ('1' = ON). 기본 = 특수포탄, 2인, 이벤트, 이동, 효과음, 벽"""
        self.sim = Sim("fortress_top", params={"CLK_HZ": 30 * self.TICK}, randinit=randinit)
        s = self.sim
        s.set("key", 0)
        s.set("dip", sum(1 << i for i, c in enumerate(dip) if c == "1"))
        s.set("step_sensor", sensor)
        s.clock(20 + skew)          # skew: 난수(LFSR) 위상을 바꿔서 판마다 다른 전개를 만듦
        self.log = []
        self.sfx = []
        self.hook = None            # 매 클럭 뒤에 부르는 함수 (감시용)

    # ------------------------------------------------------------ 값 읽기
    def g(self, name, signed=None):
        return self.sim.get("u_game." + name, signed)

    @property
    def st(self):
        return ST[self.g("st")]

    def hp(self):
        return self.g("u_p0.hp"), self.g("u_p1.hp")

    def pos(self):
        return self.g("u_p0.pos"), self.g("u_p1.pos")

    def walls(self):
        v = self.g("wall_hp")
        return [v & 3, (v >> 2) & 3, (v >> 4) & 3], self.g("wall2_col")

    # ------------------------------------------------------------ 진행
    def clock(self, n):
        s = self.sim
        req, sid = s.names["u_game.sfx_req"], s.names["u_game.sfx_id"]
        for _ in range(n):
            s.clock()
            if s.s[req]:
                self.sfx.append(s.s[sid])
            if self.hook:
                self.hook(self)

    def tick(self, n=1):
        self.clock(self.TICK * n)

    def wait(self, states, max_ticks=600):
        """상태가 states 중 하나가 될 때까지 진행. 못 만나면 예외"""
        if isinstance(states, str):
            states = (states,)
        for _ in range(max_ticks * 10):
            if self.st in states:
                return self.st
            self.clock(self.TICK // 10)
        raise TimeoutError(f"{states} 를 못 만남 (지금 {self.st}, turn {self.g('turn')}, st_t {self.g('st_t')})")

    def hold(self, key, on):
        k = self.sim.get("key")
        bit = 1 << KEYS.index(key)
        self.sim.set("key", (k | bit) if on else (k & ~bit))

    def press(self, key, hold_clocks=20, gap_clocks=20):
        self.hold(key, True)
        self.clock(hold_clocks)
        self.hold(key, False)
        self.clock(gap_clocks)

    # ------------------------------------------------------------ 화면
    def screen(self, raw=False):
        """LCD 렌더러에 주소 32개를 직접 넣어서 지금 화면을 읽음 (상태는 건드리지 않음)"""
        s = self.sim
        keep = list(s.s)
        a = s.names["u_lcd.dd_addr"]
        rows = []
        for r in range(2):
            line = []
            for c in range(16):
                s.s[a] = r * 16 + c
                s.settle()
                line.append(s.get("u_render.dd_char"))
            rows.append(line)
        s.s[:] = keep
        if raw:
            return rows
        return ["".join(SYM.get(v, chr(v) if 32 < v < 127 else "?") for v in line) for line in rows]

    def cgram(self, slot):
        s = self.sim
        keep = list(s.s)
        a = s.names["u_lcd.cg_addr"]
        rows = []
        for r in range(8):
            s.s[a] = slot * 8 + r
            s.settle()
            rows.append(s.get("u_render.cg_row"))
        s.s[:] = keep
        return rows

    def show(self, title=""):
        a, b = self.screen()
        print(f"  [{title:<22}] |{a}|  {self.st} t{self.g('turn')} hp{self.hp()} seg[{self.seg8()}]")
        print(f"  {'':<24} |{b}|")

    def seg8(self):
        """7세그 스캔을 한 바퀴 지켜보고 8자리 글자로"""
        s = self.sim
        out = [" "] * 8
        for _ in range(40):
            s.clock()
            com = s.get("seg_com") ^ 0xFF
            if com and com & (com - 1) == 0:
                d = s.get("seg_data")
                i = com.bit_length() - 1
                out[i] = SEGCH.get(d >> 1, "?") + ("." if d & 1 else "")
        return "".join(out)

    # ------------------------------------------------------------ 조작 묶음
    def start(self):
        self.wait("TITLE")
        self.press("5")
        self.wait(("MOVE", "AIM"), 400)

    def end_move(self):
        self.press("5")

    def set_angle(self, ang):
        while self.g("cur_ang") != ang:
            self.press("2" if self.g("cur_ang") < ang else "8", 14, 14)

    def select_shell(self, sh):
        cur = self.g("shell_eff")
        if cur == sh:
            return
        if cur != 0 and sh == 0:
            self.press(SHELL_KEY[cur])
        elif sh != 0:
            self.press(SHELL_KEY[sh])
        assert self.g("shell_eff") == sh, (self.g("shell_eff"), sh)

    def fire(self, power):
        """5를 누르고 있다가 게이지가 power 일 때 뗌"""
        self.hold("5", True)
        self.wait("CHARGE", 20)
        for _ in range(4000):
            if self.g("gauge_pow") == power and self.g("st_t") >= 2:
                break
            self.clock(4)
        self.hold("5", False)
        self.wait("FLIGHT", 20)
        return self.g("gauge_pow")


# ================================================================ 기준 모델 (시뮬레이터 JS 를 Python 으로 옮김)
G_NORM = 18
SHELLS = {0: ((35, 20, 10), (4, 8)), 1: ((20, 12, 6), (4, 8)), 2: ((22, 16, 8), (7, 13)),
          3: ((0, 0, 0), (0, 0)), 4: ((30, 15, 0), (4, 8)), 5: ((20, 20, 10), (4, 7))}


def ref_shot(owner, pos, ang, power, walls, wall2_col, wind=0, grav=G_NORM, shell=0, meteor_cell=None):
    """한 발의 결과: dict(kind, ix, dmg=[d0,d1], frz=[f0,f1], wall, ticks)
    power 는 게임 파워 1~8 (ROM 파워 = 2*power). owner = -1, meteor_cell = 칸 이면 유성"""
    p0, p1 = pos
    cannon = (p0 + 1, p1 - 1)
    cells = [(1, 7), (1, 8), (0, 8 if wall2_col else 7)]
    if meteor_cell is not None:
        x, h, vx, vh, age, shell = (5 * meteor_cell + 2) << 8, 34 << 8, 0, -90, 99, 5
    else:
        d = 1 if owner == 0 else -1
        pivot = 5 * cannon[owner] + (1 if owner == 0 else 3)
        mx, h0 = gen_roms.MROM[ang - 30]
        vx, vh = gen_roms.VROM[(ang - 30) * 16 + (2 * power - 1)]
        x, h, vx, vh, age = (pivot << 8) + d * mx, h0, d * vx, vh, 0
    res = None
    while res is None:
        vx += wind
        vh -= grav
        x += vx
        h += vh
        px, py = x >> 8, 15 - (h >> 9)
        c = px // 5
        if px < -4 or px > 84:
            res = dict(kind="out")
            break
        for i, (r, cc) in enumerate(cells):
            top = r * 8 + (0 if walls[i] >= 2 else 4)
            if walls[i] > 0 and cc == c and top <= py < r * 8 + 8:
                res = dict(kind="wall", wall=i)
                break
        if res is None and py >= 11:
            for pi in (0, 1):
                if pi == owner and age < 8:
                    continue
                if c == pos[pi] or c == cannon[pi]:
                    res = dict(kind="direct", who=pi)
                    break
        if res is None and h <= 0:
            res = dict(kind="ground")
        age += 1
        if res is None and age > 600 + (99 if meteor_cell is not None else 0):
            res = dict(kind="out")
    res["ticks"] = age
    res["dmg"], res["frz"] = [0, 0], [False, False]
    if res["kind"] == "out":
        if shell == 4:
            res["dmg"][owner] += 15
        return res
    ix = max(0, min(79, px))
    res["ix"] = ix
    center = (5 * p0 + 5, 5 * p1)
    tank = ((p0, p0 + 1), (p1 - 1, p1))
    if shell == 3:
        c = ix // 5
        res["frz"] = [any(abs(t - c) <= 1 for t in tank[pi]) for pi in (0, 1)]
        return res
    dm, rad = SHELLS[shell]
    enemy = False
    for pi in (0, 1):
        if res["kind"] == "direct" and res["who"] == pi:
            v = dm[0]
        else:
            dx = abs(ix - center[pi])
            v = dm[1] if dx <= rad[0] else dm[2] if dx <= rad[1] else 0
        res["dmg"][pi] += v
        if v and pi != owner:
            enemy = True
    if shell == 4:
        if enemy:
            res["heal"] = 15
        else:
            res["dmg"][owner] += 15
    return res
