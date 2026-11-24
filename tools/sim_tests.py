#!/usr/bin/env python3
"""minisim 으로 돌리는 회귀 테스트 (Vivado 없이 로직 검증)

    python3 tools/sim_tests.py            # 전부 (몇 분 걸림)
    python3 tools/sim_tests.py units      # 모듈 단위 검사만
    python3 tools/sim_tests.py setup      # 설정 화면
    python3 tools/sim_tests.py game 3     # 무작위 플레이 3판 (2인)
    python3 tools/sim_tests.py cpu 2      # CPU 대전 2판

무작위 플레이는 키를 아무렇게나 눌러 여러 판을 끝까지 돌리면서
  - 포탄 한 발마다 탄착·피해·얼음·벽 파손이 기준 모델(웹 시뮬레이터 수식을 옮긴 simlib.ref_shot)과 같은지
  - 위치·각도·체력 범위, 용암 칸, 이벤트 주기 같은 규칙이 깨지지 않는지
를 매 클럭 검사해요.
"""
import random
import sys
import time

from simlib import Game, ST, ref_shot, gen_roms
from minisim import Sim

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)
        print("  FAIL:", msg)
    return cond


# ============================================================================ 모듈 단위
def test_trajectory():
    sim = Sim("trajectory")
    sim.set("rst", 1); sim.clock(2); sim.set("rst", 0)
    bad = 0
    for (a, p, pv, d, w, gr, t, px, out) in gen_roms.golden_cases():
        for n, v in (("angle_idx", a - 30), ("power_idx", p - 1), ("dir", 1 if d < 0 else 0), ("pivot_x", pv),
                     ("wind", w), ("grav", gr), ("use_raw", 0)):
            sim.set(n, v)
        sim.set("start", 1); sim.clock(); sim.set("start", 0)
        n = 0
        while not (sim.get("out_of_map") or sim.get("hit_ground")) and n < 700:
            sim.set("step", 1); sim.clock(); sim.set("step", 0)
            n += 1
        bad += (n, sim.get("px"), sim.get("out_of_map")) != (t, px, out)
        sim.set("stop", 1); sim.clock(); sim.set("stop", 0)
    check(bad == 0, f"trajectory 정답 불일치 {bad}개")
    print(f"trajectory: 정답 104개 중 {104 - bad}개 일치")


def test_servo():
    sim = Sim("servo_ctrl")
    sim.set("rst", 1); sim.clock(2); sim.set("rst", 0)
    res = {}
    for deg in (0, 30, 90, 150, 180):
        sim.set("target_deg", deg)
        for _ in range(30):                       # 목표 각도까지 따라가게 함
            sim.set("tick_frame", 1); sim.clock(); sim.set("tick_frame", 0)
        while sim.get("servo"):
            sim.clock()
        while not sim.get("servo"):
            sim.clock()
        hi = 0
        while sim.get("servo"):
            sim.clock(); hi += 1
        lo = 0
        while not sim.get("servo"):
            sim.clock(); lo += 1
        res[deg] = (hi, hi + lo)
    exp = {0: 700, 30: 966, 90: 1500, 150: 2033, 180: 2300}
    ok = all(res[d] == (exp[d], 20000) for d in exp)
    check(ok, f"servo 펄스 폭 {res}")
    print("servo: 펄스 폭(us)", {d: v[0] for d, v in res.items()}, "주기", res[0][1])


def test_piezo():
    sim = Sim("piezo_ctrl")
    sim.set("rst", 1); sim.clock(2); sim.set("rst", 0)
    sim.set("enable", 1); sim.set("rnd", 0x1234)

    def run_ms(ms):
        edges, last, t = [], sim.get("piezo"), 0
        for _ in range(ms):
            for i in range(1000):
                sim.set("tick_ms", 1 if i == 999 else 0) if i in (0, 999) else None
                sim.clock(); t += 1
                v = sim.get("piezo")
                if v != last:
                    edges.append(t); last = v
        return edges
    # 충전음: 파워 4 -> 660 Hz (반주기 758 us)
    sim.set("charge_on", 1); sim.set("charge_pow", 4)
    e = run_ms(20)
    half = e[5] - e[4]
    check(half == 758, f"충전음 반주기 {half}")
    sim.set("charge_on", 0)
    # 효과음 TURN(10): 523 Hz 68 ms, 쉼 12 ms, 784 Hz 68 ms, 쉼 12 ms
    sim.set("sfx_id", 10); sim.set("sfx_req", 1); sim.clock(); sim.set("sfx_req", 0)
    e = run_ms(200)
    h1, h2 = e[3] - e[2], e[-2] - e[-3]
    dur = e[-1]
    check(h1 == 956 and h2 == 638 and 140 < dur / 1000 < 152, f"TURN 효과음 반주기 {h1}, {h2}, 끝 {dur}us")
    sim.set("enable", 0)
    sim.set("sfx_id", 10); sim.set("sfx_req", 1); sim.clock(); sim.set("sfx_req", 0)
    check(not run_ms(30), "DIP7 OFF 인데 소리가 남")
    print(f"piezo: 충전음 반주기 {half}us, TURN 반주기 {h1}/{h2}us 길이 {dur / 1000:.0f}ms, 음소거 확인")


def test_stepper():
    sim = Sim("stepper_ctrl")
    sim.set("rst", 1); sim.clock(2); sim.set("rst", 0)
    sim.set("sensor", 0)

    def run(maxms=5000, sensor_at=None):
        steps, last, ms = 0, sim.get("coil"), 0
        seq = []
        while ms < maxms:
            sim.set("tick_ms", 1); sim.clock(); sim.set("tick_ms", 0); sim.clock(2)
            ms += 1
            c = sim.get("coil")
            if c != last and c:
                steps += 1; seq.append(c)
            last = c or last
            if sensor_at is not None and steps == sensor_at:
                sim.set("sensor", 1)
            if not sim.get("busy"):
                break
        return steps, ms, seq
    sim.set("home", 1); sim.clock(); sim.set("home", 0)
    st, ms, seq = run(sensor_at=37)
    check(sim.get("pos") == 0 and 36 <= st <= 39, f"원점 찾기 스텝 {st}")
    check(seq[:4] in ([4, 2, 1, 8], [2, 1, 8, 4], [1, 8, 4, 2], [8, 4, 2, 1]), f"코일 순서 {seq[:6]}")
    sim.set("sensor", 0)
    out = []
    for target in (2, 5, 0, 3):
        before = sim.get("pos")
        sim.set("target_sector", target); sim.set("spin", 1); sim.clock(); sim.set("spin", 0)
        st, ms, _ = run()
        out.append((target, sim.get("pos"), st, ms))
        check(sim.get("pos") == target * 200 // 6 and 200 <= st < 400, f"룰렛 목표 {target}: pos {sim.get('pos')} 스텝 {st}")
        check(ms < 2300, f"룰렛이 너무 오래 돎 {ms}ms")
    # 센서가 없을 때: 2바퀴 돌고 포기
    sim.set("home", 1); sim.clock(); sim.set("home", 0)
    st, ms, _ = run()
    check(st == 400 and not sim.get("busy"), f"센서 없음: {st}스텝")
    print("stepper: 원점 찾기·코일 순서 확인, 룰렛 (목표칸, 위치, 스텝, ms)", out)


def lcd_decode(sim, clocks, e="lcd_e", rs="lcd_rs", data="lcd_data"):
    """LCD 버스를 지켜보고 (시각, rs, data) 목록으로"""
    out, last = [], 0
    ie, irs, idt = sim.names[e], sim.names[rs], sim.names[data]
    for t in range(clocks):
        sim.clock()
        v = sim.s[ie]
        if last and not v:
            out.append((sim.cycles, sim.s[irs], sim.s[idt]))
        last = v
    return out


def test_lcd_ctrl():
    sim = Sim("lcd_ctrl")
    sim.set("rst", 1); sim.clock(2); sim.set("rst", 0)
    sim.set("want_on", 1); sim.set("want_shift", 0)
    # 렌더러 대신: cg_row = 주소 하위 5비트, dd_char = 0x40 + 주소
    log = []
    ie, irs, idt = sim.names["lcd_e"], sim.names["lcd_rs"], sim.names["lcd_data"]
    icg, idd = sim.names["cg_addr"], sim.names["dd_addr"]
    last, t0 = 0, sim.cycles
    for _ in range(110000):
        sim.s[sim.names["cg_row"]] = sim.s[icg] & 31
        sim.s[sim.names["dd_char"]] = 0x40 + sim.s[idd]
        sim.clock()
        v = sim.s[ie]
        if last and not v:
            log.append((sim.cycles - t0, sim.s[irs], sim.s[idt]))
        last = v
    init = [(rs, d) for _, rs, d in log[:6]]
    check(init == [(0, 0x38), (0, 0x38), (0, 0x38), (0, 0x0C), (0, 0x01), (0, 0x06)], f"LCD 초기화 순서 {init}")
    check(log[0][0] >= 50000, f"전원 대기 {log[0][0]}us")
    gaps = [log[i + 1][0] - log[i][0] for i in range(5)]
    check(min(gaps) >= 4100, f"초기화 명령 간격 {gaps}")
    frame = log[6:6 + 99]
    exp = [(0, 0x40)] + [(1, i & 31) for i in range(64)] + [(0, 0x80)] + [(1, 0x40 + i) for i in range(16)] \
        + [(0, 0xC0)] + [(1, 0x50 + i) for i in range(16)]
    check([(rs, d) for _, rs, d in frame] == exp, "LCD 갱신 한 바퀴 내용이 다름")
    gap = min(frame[i + 1][0] - frame[i][0] for i in range(98))
    check(gap >= 100, f"글자 간격 {gap}us")
    period = log[6 + 99][0] - log[6][0]
    # 흔들림·깜빡임 명령
    sim.set("want_shift", 1)
    cmds = [d for _, rs, d in lcd_decode(sim, 25000) if rs == 0 and d not in (0x40, 0x80, 0xC0)]
    sim.set("want_shift", 2)
    cmds += [d for _, rs, d in lcd_decode(sim, 25000) if rs == 0 and d not in (0x40, 0x80, 0xC0)]
    sim.set("want_shift", 0); sim.set("want_on", 0)
    cmds += [d for _, rs, d in lcd_decode(sim, 25000) if rs == 0 and d not in (0x40, 0x80, 0xC0)]
    sim.set("want_on", 1)
    cmds += [d for _, rs, d in lcd_decode(sim, 25000) if rs == 0 and d not in (0x40, 0x80, 0xC0)]
    check(cmds == [0x1C, 0x18, 0x18, 0x1C, 0x08, 0x0C], f"흔들림/깜빡임 명령 {[hex(c) for c in cmds]}")
    print(f"lcd_ctrl: 초기화 6명령·간격 {min(gaps)}us, 갱신 99바이트 일치, 글자 간격 {gap}us, 한 바퀴 {period / 1000:.1f}ms, 이동/ONOFF 명령 확인")


def test_keypad():
    sim = Sim("keypad_ctrl")
    sim.set("rst", 1); sim.clock(2); sim.set("rst", 0)
    events = []

    def run(ms):
        for _ in range(ms):
            for i in range(4):
                sim.set("tick_ms", 1 if i == 3 else 0) if i in (0, 3) else None
                sim.clock()
                if sim.get("key_press"):
                    events.append(("press", sim.get("key_press")))
                if sim.get("key_release"):
                    events.append(("release", sim.get("key_release")))
    # 채터링: 5번 키(비트 4)가 1 ms 간격으로 떨다가 눌림
    for v in (1, 0, 1, 0, 1):
        sim.set("key_raw", v << 4); run(1)
    run(30)
    sim.set("key_raw", 0); run(2); sim.set("key_raw", 1 << 4); run(2); sim.set("key_raw", 0)   # 뗄 때 채터링
    run(30)
    check(events == [("press", 1), ("release", 1)], f"디바운스 {events}")
    events.clear()
    order = "123456789*0#"
    logical = {"5": 0, "2": 1, "8": 2, "4": 3, "6": 4, "1": 5, "3": 6, "7": 7, "9": 8, "#": 9}
    for ch, bit in logical.items():
        sim.set("key_raw", 1 << order.index(ch)); run(20); sim.set("key_raw", 0); run(20)
    exp = []
    for bit in logical.values():
        exp += [("press", 1 << bit), ("release", 1 << bit)]
    check(events == exp, f"키 매핑 {events}")
    print("keypad: 채터링 걸러냄(누름 1번·뗌 1번), 키 10개 매핑 확인")


def test_seg_font():
    sim = Sim("scoreboard")
    sim.set("title", 0); sim.set("hp0", 7); sim.set("hp1", 100); sim.set("mid0", 16); sim.set("mid1", 3)
    ch = [(sim.get("chars") >> (35 - 5 * i)) & 31 for i in range(8)]
    check(ch == [10, 10, 7, 16, 3, 1, 0, 0], f"scoreboard {ch}")
    print("scoreboard: '  7E3100' 확인")


# ============================================================================ 무작위 플레이
class Monitor:
    """매 클럭 게임 내부를 지켜보며 규칙·기준 모델과 비교"""

    def __init__(self, g, name):
        self.g, self.name = g, name
        self.shot = None
        self.settle = 0
        self.n_shots = 0
        self.kinds = {}
        self.events = {}
        self.res_msgs = set()
        self.last_st = None
        self.cturn = 0
        self.prev_turn_key = None
        self.ev_apply_wait = 0
        self.snap_ev = None
        s = g.sim
        self.i = {k: s.names["u_game." + k] for k in
                  ("sh_active", "imp2", "st", "c_ev_apply", "turn", "setup", "c_ev_turn", "c_pinit")}

    def err(self, msg):
        g = self.g
        check(False, f"[{self.name} @{g.sim.cycles} {g.st} t{g.g('turn')}] {msg}")

    def state(self):
        g = self.g
        return dict(pos=g.pos(), walls=g.walls(), hp=g.hp(),
                    frz=(g.g("u_p0.frozen"), g.g("u_p1.frozen")), mx=(g.g("u_p0.max_hp"), g.g("u_p1.max_hp")))

    def __call__(self, g):
        s = g.sim.s
        i = self.i
        # ---- 포탄 발사 감지
        if s[i["sh_active"]] and self.shot is None:
            st = self.state()
            st.update(wind=g.g("wind", True), grav=g.g("grav"), sh=g.g("sh_type"),
                      owner=g.g("sh_owner") if g.g("sh_owner_v") else -1,
                      ang=g.g("l_aidx") + 30, pidx=g.g("l_pidx"), raw=g.g("l_raw"), lx=g.g("l_x"))
            self.shot = st
        elif self.shot is not None and not s[i["sh_active"]] and s[i["imp2"]] == 0:
            self.settle += 1
            if self.settle == 4:                    # 피해·회복 명령이 다 반영된 뒤
                self.compare()
                self.shot, self.settle = None, 0
        # ---- 이벤트 적용 감지
        if s[i["c_ev_apply"]]:
            self.snap_ev = self.state()
            self.ev_apply_wait = 3
        elif self.ev_apply_wait:
            self.ev_apply_wait -= 1
            if self.ev_apply_wait == 0:
                self.check_event()
        # ---- 턴 세기 (이벤트 주기 검사)
        if s[i["c_pinit"]]:
            self.cturn = 0
        if s[i["c_ev_turn"]]:
            if not s[i["setup"]]:
                self.cturn += 1
            self.turn_check = 2
        elif getattr(self, "turn_check", 0):
            self.turn_check -= 1
            if self.turn_check == 0 and g.g("cfg_events"):
                want = self.cturn % 3 == 0 and not s[i["setup"]] and not g.g("ev_active")
                if bool(g.g("ev_new")) != want:
                    self.err(f"이벤트 주기: cturn {self.cturn} ev_new {g.g('ev_new')} ev_active {g.g('ev_active')}")
        # ---- 상태가 바뀔 때 규칙 검사
        if s[i["st"]] != self.last_st:
            self.last_st = s[i["st"]]
            self.invariants()

    def invariants(self):
        g = self.g
        p0, p1 = g.pos()
        if g.st in ("TITLE", "START"):
            return
        if not (0 <= p0 <= 5 and 10 <= p1 <= 15):
            self.err(f"위치 범위 {p0},{p1}")
        for pi in (0, 1):
            a = g.g(f"u_p{pi}.ang")
            if not 30 <= a <= 90:
                self.err(f"각도 범위 {a}")
            if g.g(f"u_p{pi}.hp") > g.g(f"u_p{pi}.max_hp"):
                self.err("체력이 최대보다 큼")
        lava = [v & 15 for v in (g.g("lava0"), g.g("lava1")) if v & 16]
        cells = [p0, p0 + 1, p1 - 1, p1]
        if any(c in cells for c in lava):
            self.err(f"탱크가 용암 위에 있음 lava {lava} pos {p0},{p1}")
        if g.st == "RESULT":
            self.res_msgs.add(g.g("res_msg"))
        for row in g.screen(raw=True):
            for v in row:
                if not (v < 8 or 0x20 <= v < 0x7F or v in (0xFF, 0xA5, 0xDF)):
                    self.err(f"화면에 이상한 문자 코드 {v:#x}")

    def compare(self):
        g, sh = self.g, self.shot
        self.n_shots += 1
        walls, w2 = sh["walls"]
        if sh["raw"]:
            cell = ((sh["lx"] >> 8) - 2) // 5
            exp = ref_shot(-1, sh["pos"], 0, 0, walls, w2, sh["wind"], sh["grav"], 5, meteor_cell=cell)
            owner = -1
        else:
            if sh["pidx"] % 2 != 1:
                self.err(f"ROM 파워 주소가 홀수가 아님 {sh['pidx']}")
            owner = sh["owner"]
            exp = ref_shot(owner, sh["pos"], sh["ang"], (sh["pidx"] + 1) // 2, walls, w2, sh["wind"], sh["grav"], sh["sh"])
        self.kinds[exp["kind"]] = self.kinds.get(exp["kind"], 0) + 1
        hp = [max(0, sh["hp"][pi] - exp["dmg"][pi]) for pi in (0, 1)]
        if exp.get("heal"):
            hp[owner] = min(sh["mx"][owner], hp[owner] + exp["heal"])
        w = list(walls)
        if exp["kind"] == "wall" and sh["sh"] != 3:
            w[exp["wall"]] = max(0, w[exp["wall"]] - 1)
            below = 1 if w2 else 0
            if w[2] and not w[below]:
                w[below], w[2] = w[2], 0
        frz = tuple(int(bool(a or b)) for a, b in zip(sh["frz"], exp["frz"]))
        now = self.state()
        if tuple(hp) != now["hp"] or w != now["walls"][0] or frz != now["frz"]:
            self.err(f"탄착 결과가 기준 모델과 다름\n      발사 {sh}\n      기준 {exp} -> hp {hp} walls {w} frz {frz}\n      RTL  hp {now['hp']} walls {now['walls'][0]} frz {now['frz']}")
        if "ix" in exp and owner >= 0:
            last = g.g(f"u_p{owner}.last")
            if last != exp["ix"] // 5:
                self.err(f"마지막 탄착 칸 {last} != {exp['ix'] // 5}")

    def check_event(self):
        g, b = self.g, self.snap_ev
        ev = g.g("ev_id")
        name = ["LAVA", "LOWG", "GUST", "QUAKE", "FOG", "METEOR"][ev]
        self.events[name] = self.events.get(name, 0) + 1
        if not g.g("ev_active"):
            self.err("이벤트 적용 뒤 ev_active 가 0")
        p0, p1 = g.pos()
        lava = [v & 15 for v in (g.g("lava0"), g.g("lava1")) if v & 16]
        wind, grav = g.g("wind", True), g.g("grav")
        marks = [(g.g("marks") >> (5 * k)) & 31 for k in range(3)]
        if name == "LAVA":
            ok = len(lava) == 2 and 0 <= lava[0] <= 6 and 9 <= lava[1] <= 15 and lava[0] not in (p0, p0 + 1) and lava[1] not in (p1 - 1, p1)
            if not ok:
                self.err(f"용암 칸 {lava} pos {p0},{p1}")
        elif lava:
            self.err("용암 이벤트가 아닌데 용암 칸이 있음")
        if (name == "GUST") != (wind != 0) or (name == "GUST" and not 3 <= abs(wind) <= 5):
            self.err(f"바람 {wind} ({name})")
        if grav != (11 if name == "LOWG" else 18):
            self.err(f"중력 {grav} ({name})")
        if name == "METEOR":
            cells = [m & 15 for m in marks]
            if not (all(m & 16 for m in marks) and len(set(cells)) == 3 and all(c <= 6 or c >= 9 for c in cells)):
                self.err(f"유성 예고 칸 {marks}")
        elif any(m & 16 for m in marks):
            self.err("유성 이벤트가 아닌데 예고 칸이 있음")
        if name == "QUAKE":
            if abs(p0 - b["pos"][0]) > 1 or abs(p1 - b["pos"][1]) > 1:
                self.err(f"지진 이동 {b['pos']} -> {p0},{p1}")
            w, w2 = b["walls"]
            w = [max(0, x - 1) for x in w]
            below = 1 if w2 else 0
            if w[2] and not w[below]:
                w[below], w[2] = w[2], 0
            if w != g.walls()[0]:
                self.err(f"지진 뒤 벽 {g.walls()[0]} != {w}")
        elif (p0, p1) != b["pos"]:
            self.err("지진이 아닌데 탱크가 움직임")


def best_shot(g, turn, rnd):
    """실제 상대 위치를 맞히는 (각도, 파워). 게임을 빨리 끝내려는 테스트용"""
    pos, (walls, w2) = g.pos(), g.walls()
    wind, grav = g.g("wind", True), g.g("grav")
    cands = []
    for a in range(30, 91, 2):
        for p in range(1, 9):
            r = ref_shot(turn, pos, a, p, walls, w2, wind, grav, 0)
            if r["dmg"][1 - turn] and not r["dmg"][turn]:
                cands.append((a, p))
    return rnd.choice(cands) if cands else None


def play(dip, seed, max_turns=80, verbose=False, cpu=False, randinit=None, best=0.3):
    rnd = random.Random(seed)
    g = Game(dip=dip, skew=rnd.randrange(5000), randinit=randinit)
    mon = Monitor(g, f"dip {dip} seed {seed}")
    g.hook = mon
    special, move_on = dip[0] == "1", dip[4] == "1"
    g.start()
    turns, last_key, idle = 0, None, 0
    t0 = time.time()
    while g.st != "OVER" and turns < max_turns:
        st, turn = g.st, g.g("turn")
        human = not (cpu and turn == 1)
        key = (st, turn, g.g("setup"))
        if key != last_key:
            last_key, idle = key, 0
            if verbose and st in ("AIM", "RESULT", "MOVE", "METEOR"):
                g.show(f"turn {turns}")
        idle += 1
        if idle > 4000:
            mon.err("상태가 안 바뀜 (멈춤)")
            break
        if st == "MOVE" and human:
            if g.g("mv_frozen"):
                g.press(rnd.choice("46"))                       # 얼었을 때는 눌러도 안 움직여야 함
                g.wait(("INTRO", "METEOR", "NEXT"), 120)
            else:
                before = g.pos()[turn]
                for _ in range(rnd.randrange(4)):
                    g.press(rnd.choice("46" + ("28" if rnd.random() < 0.2 else "")))
                if abs(g.pos()[turn] - before) > 3:
                    mon.err("한 번 누름에 두 칸 이상 움직임")
                g.end_move()
                g.wait(("INTRO", "METEOR", "NEXT", "AIM"), 60)
        elif st == "AIM" and human:
            turns += 1
            sh = rnd.choice([0, 0, 1, 2, 3, 4]) if special else 0
            if not special and rnd.random() < 0.3:
                g.press("1")                                   # NORM ONLY 여야 함
                check(g.g("shell_eff") == 0, "특수 포탄 OFF 인데 포탄이 바뀜")
            if rnd.random() < 0.2:
                g.press(rnd.choice("46"))                      # 조준 중 이동 키: 안 움직여야 함
            g.select_shell(sh)
            aim = best_shot(g, turn, rnd) if rnd.random() < best else None
            ang, pw = aim if aim else (rnd.randrange(30, 91), rnd.randrange(1, 9))
            if rnd.random() < 0.3:                             # 길게 눌러 자동 반복도 써 봄
                g.hold("2" if g.g("cur_ang") < ang else "8", True); g.tick(rnd.randrange(12, 40)); g.hold("2", False); g.hold("8", False); g.clock(20)
            g.set_angle(ang)
            g.fire(pw)
            g.wait(("RESULT",), 900)
        else:
            if rnd.random() < 0.02:                            # 조작할 수 없는 때 아무 키나 눌러 봄 (# 제외)
                g.press(rnd.choice("123456789*0"), rnd.randrange(3, 60), 5)
            g.clock(20)
    dt = time.time() - t0
    over = g.st == "OVER"
    if over:
        hp = g.hp()
        w = g.g("winner")
        check(w == (2 if hp == (0, 0) else 1 if hp[0] == 0 else 0), f"승자 {w} hp {hp}")
        g.tick(60)
        a, b = g.screen()
        check(("WINS!" in a) or ("DRAW" in a), f"게임 끝 화면: {a}")
        g.press("5")
        g.wait("SETUP", 20)
        check(g.st == "SETUP", "게임 끝에서 5 -> 설정 화면이 아님")
        g.press("5")
        g.wait(("MOVE", "AIM", "INTRO"), 200)
        check(g.hp() == (g.g("u_p0.max_hp"),) * 2 and g.pos() == (0, 15), "다시 시작 뒤 초기화가 안 됨")
    print(f"  dip {dip} seed {seed}: {'끝' if over else '미완'} {turns}턴, 포탄 {mon.n_shots}발 {mon.kinds}, 이벤트 {mon.events}, "
          f"결과문구 {len(mon.res_msgs)}종, {dt:.0f}s")
    return mon


def test_reset():
    """아무 때나 # 을 눌러도 타이틀로 돌아가고, 다시 시작하면 깨끗한 새 판이어야 함"""
    rnd = random.Random(7)
    g = Game(dip="10011111")
    for k in range(8):
        g.start()
        mon = Monitor(g, f"reset {k}")
        g.hook = mon
        stop_at = rnd.choice(["MOVE", "AIM", "CHARGE", "FLIGHT", "IMPACT", "RESULT", "INTRO"])
        for _ in range(400):
            st, turn = g.st, g.g("turn")
            if st == stop_at and rnd.random() < 0.3:
                break
            if st == "MOVE":
                g.press(rnd.choice("46")); g.end_move()
            elif st == "AIM":
                g.select_shell(rnd.randrange(5)); g.set_angle(rnd.randrange(40, 80))
                g.hold("5", True); g.wait("CHARGE", 20); g.tick(rnd.randrange(2, 20))
                if stop_at == "CHARGE":
                    break
                g.hold("5", False)
            else:
                g.clock(rnd.randrange(5, 60))
        g.hook = None
        g.press("#")
        g.hold("5", False)
        g.clock(30)
        check(g.st == "TITLE", f"# 뒤 상태 {g.st} ({stop_at} 에서 누름)")
        check(g.g("sh_active") == 0 and g.g("fx_on") == 0, "# 뒤에 포탄·폭발이 남음")
        a, _ = g.screen()
        check("FORTRESS" in a, f"타이틀 화면 {a}")
    g.start()
    check(g.hp() == (100, 100) and g.pos() == (0, 15) and g.g("ev_active") == 0 and g.g("wind", True) == 0
          and g.g("lava0") == 0 and g.g("marks") == 0 and g.g("turn") == 0 and g.g("setup") == 1, "리셋 뒤 새 판 상태")
    print("reset: 8가지 시점에서 # -> 타이틀 -> 새 판 확인")


def test_setup():
    """타이틀 -> 5 -> 설정 화면: DIP 상태 표시, 스위치 바꾸면 그 설명으로, 4·6 넘기기, # 취소, 5로 시작"""
    names = ["SPECIAL SH", "VS CPU", "CPU HARD", "EVENTS", "MOVE", "HP 100", "SND+MOTOR", "WALL"]
    g = Game(dip="10011011")
    g.wait("TITLE")
    g.press("5")
    check(g.st == "SETUP", f"타이틀에서 5 -> {g.st}")

    def dip_txt(dip):
        return "".join(str(i + 1) if c == "1" else "-" for i, c in enumerate(dip))

    def screen_ok(dip, sel, tag):
        g.tick(1)
        while g.g("gt") & 8:                      # 고른 스위치가 깜빡여 빈칸인 때를 피함
            g.tick(1)
        a, b = g.screen()
        exp_b = f"{sel + 1} {names[sel]}".ljust(16 - (2 if dip[sel] == "1" else 3)) + ("ON" if dip[sel] == "1" else "OFF")
        check(a[8:] == dip_txt(dip), f"{tag}: 윗줄 DIP {a!r}")
        check(a[:8].strip() in ("SETUP", "5:START"), f"{tag}: 윗줄 문구 {a!r}")
        check(b == exp_b, f"{tag}: 아랫줄 {b!r} (기대 {exp_b!r})")
        check(g.seg8() == dip_txt(dip), f"{tag}: 7세그 {g.seg8()!r}")
        check(g.sim.get("led") == int(dip[::-1], 2), f"{tag}: LED {g.sim.get('led'):08b}")

    dip = "10011011"
    screen_ok(dip, 0, "처음")
    # 스위치를 바꾸면 그 스위치 설명으로 넘어감
    for i in (2, 6, 1, 7):
        dip = dip[:i] + ("0" if dip[i] == "1" else "1") + dip[i + 1:]
        g.set_dip(dip)
        g.tick(3)
        check(g.g("set_sel") == i, f"DIP{i + 1} 바꿨는데 설명 {g.g('set_sel') + 1}")
        screen_ok(dip, i, f"DIP{i + 1} 바꿈")
    # 가만히 두면 3초(바꾼 직후) 뒤부터 1.5초마다 다음 설명
    sel = g.g("set_sel")
    g.tick(100)
    check(g.g("set_sel") == (sel + 1) % 8, "바꾼 뒤 설명이 안 넘어감")
    g.tick(47)
    check(g.g("set_sel") == (sel + 2) % 8, "1.5초마다 안 넘어감")
    # 4·6 으로 넘기기
    sel = g.g("set_sel")
    g.press("6"); check(g.g("set_sel") == (sel + 1) % 8, "6 으로 다음 설명")
    g.press("4"); g.press("4"); check(g.g("set_sel") == (sel - 1) % 8, "4 로 이전 설명")
    check(g.st == "SETUP", "설정 화면에서 4·6 뒤 상태")
    # # 이면 타이틀로, 다시 5 -> 설정 화면
    g.press("#"); g.clock(30)
    check(g.st == "TITLE", f"설정에서 # -> {g.st}")
    g.press("5")
    check(g.st == "SETUP" and g.g("set_sel") == 0, "다시 설정 화면")
    # 설정 화면에서 바꾼 DIP 이 시작할 때 반영되는지
    dip = "01001100"                              # 특수X, CPU, 이동, 체력 100, 소리X, 벽X
    g.set_dip(dip); g.tick(3)
    g.press("5")
    g.wait(("MOVE", "AIM"), 400)
    cfg = [g.g(n) for n in ("cfg_special", "cfg_cpu", "cfg_expert", "cfg_events", "cfg_move", "cfg_long", "cfg_walls")]
    check(cfg == [0, 1, 0, 0, 1, 1, 0], f"시작 설정 {cfg}")
    check(g.hp() == (100, 100), f"체력 {g.hp()}")
    # 게임 중에 DIP 을 바꿔도 그 판 설정은 그대로
    g.set_dip("10110011"); g.tick(5)
    check(g.g("cfg_cpu") == 1 and g.g("cfg_special") == 0, "게임 중 DIP 변경이 반영됨")
    print("setup: 표시(LCD·7세그·LED), 스위치 따라가기, 자동 넘김, 4·6, #, 시작 때 반영 확인")


def test_game(n=3, cpu=False):
    #        특수 CPU 고수 이벤트 이동 체력 소리 벽
    dips = ["10011111", "10011011", "10010111", "00011110", "10001111", "10011101", "10011011", "00000010"]
    if cpu:
        dips = ["11011111", "11111011", "11011110", "01001111", "11110111"]
    tot = {}
    for k in range(n):
        m = play(dips[k % len(dips)], seed=100 + k + (50 if cpu else 0), cpu=cpu,
                 randinit=(k if k % 3 == 2 else None), best=0.15 if cpu else 0.3)
        for name, c in list(m.kinds.items()) + list(m.events.items()):
            tot[name] = tot.get(name, 0) + c
    print(f"{'cpu' if cpu else 'game'}: {n}판 합계 {tot}")


def main():
    args = sys.argv[1:]
    what = args[0] if args else "all"
    n = int(args[1]) if len(args) > 1 else 3
    if what in ("all", "units"):
        test_trajectory(); test_servo(); test_piezo(); test_stepper(); test_lcd_ctrl(); test_keypad(); test_seg_font()
    if what in ("all", "setup"):
        test_setup()
    if what in ("all", "reset"):
        test_reset()
    if what in ("all", "game"):
        test_game(n)
    if what in ("all", "cpu"):
        test_game(max(1, n - 1) if what == "all" else n, cpu=True)
    print("\n결과:", "모두 통과" if not FAILS else f"실패 {len(FAILS)}건")
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
