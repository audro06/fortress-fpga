#!/usr/bin/env python3
"""minisim: 이 레포의 RTL만 돌릴 수 있는 아주 작은 Verilog 시뮬레이터 (검증용)

Vivado 없이 게임 로직을 클럭 단위로 돌려 보려고 만들었어요. 합성 가능한 Verilog-2001의 일부만 알아들어요.
  - 클럭 하나(posedge), 2-state(0/1, X 없음), 비트 폭·부호 규칙은 IEEE 1364 식 계산 규칙을 따름
  - module/parameter/localparam, wire/reg/integer/메모리, assign, always @(posedge clk) / @(*),
    function, task, generate-for, 인스턴스, $readmemh
  - 지연(#), initial 테스트벤치 문법은 못 읽어요 -> 테스트는 Python 으로 써요 (tools/sim_tests.py)
Vivado xsim 을 대신하는 건 아니에요. 보드에 올리기 전에 Vivado 시뮬레이션·합성은 꼭 따로 해 보세요.

쓰는 법:
    from minisim import Sim
    sim = Sim("fortress_top", params={"CLK_HZ": 1000000})
    sim.set("key", 0); sim.clock(100); print(sim.get("u_game.st"))
"""
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ============================================================================ 실행 시 도우미
def _sx(v, b, k):            # 부호 확장: 부호 비트 b 가 켜져 있으면 윗비트 k 를 채움
    return v | k if v & b else v


def _ts(v, w):               # w비트 값을 부호 있는 정수로
    return v - (1 << w) if v >> (w - 1) else v


def _sdiv(a, b, w, mod):
    a, b = _ts(a, w), _ts(b, w)
    if b == 0:
        return 0
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    r = a - q * b
    return (r if mod else q) & ((1 << w) - 1)


def _udiv(a, b):
    return a // b if b else 0


def _umod(a, b):
    return a % b if b else 0


def _mr(arr, i):
    return arr[i] if 0 <= i < len(arr) else 0


def _par(v):
    return bin(v).count("1") & 1


HELPERS = dict(_sx=_sx, _ts=_ts, _sdiv=_sdiv, _udiv=_udiv, _umod=_umod, _mr=_mr, _par=_par)


def mask(w):
    return (1 << w) - 1


# ============================================================================ 토큰
TOK = re.compile(r"""
 (?P<ws>\s+)
|(?P<num>(?:\d[\d_]*)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ]+)
|(?P<dec>\d[\d_]*)
|(?P<id>[A-Za-z_$][A-Za-z0-9_$]*)
|(?P<str>"(?:\\.|[^"\\])*")
|(?P<op><<<|>>>|<=|>=|==|!=|&&|\|\||<<|>>|\+:|-:|[-+*/%&|^~!<>=?:;,.()\[\]{}\#@])
""", re.X)


def preprocess(path, incdirs):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)

    def inc(m):
        for d in incdirs:
            p = os.path.join(d, m.group(1))
            if os.path.exists(p):
                return preprocess(p, incdirs)
        raise FileNotFoundError(m.group(1))
    src = re.sub(r'`include\s+"([^"]+)"', inc, src)
    src = re.sub(r"`timescale[^\n]*", "", src)
    return src


def tokenize(src):
    out, pos = [], 0
    while pos < len(src):
        m = TOK.match(src, pos)
        if not m:
            raise SyntaxError("토큰 오류: " + src[pos:pos + 40])
        pos = m.end()
        k = m.lastgroup
        if k != "ws":
            out.append((k, m.group(k)))
    return out


def parse_number(t):
    if "'" not in t:
        return ("num", int(t.replace("_", "")), None, True)
    size, rest = t.split("'")
    signed = rest[0] in "sS"
    if signed:
        rest = rest[1:]
    base = {"b": 2, "o": 8, "d": 10, "h": 16}[rest[0].lower()]
    v = int(rest[1:].replace("_", ""), base)
    w = int(size.replace("_", "")) if size else 32
    return ("num", v & mask(w), w, signed)


# ============================================================================ 파서
BINPREC = {"||": 1, "&&": 2, "|": 3, "^": 4, "&": 5, "==": 6, "!=": 6, "<": 7, "<=": 7, ">": 7, ">=": 7,
           "<<": 8, ">>": 8, ">>>": 8, "<<<": 8, "+": 9, "-": 9, "*": 10, "/": 10, "%": 10}
DIRS = ("input", "output", "inout")


class Parser:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else ("eof", "")

    def nxt(self):
        tok = self.peek()
        self.i += 1
        return tok

    def at(self, v):
        return self.peek()[1] == v and self.peek()[0] != "str"

    def eat(self, v):
        if self.at(v):
            self.i += 1
            return True
        return False

    def expect(self, v):
        if not self.eat(v):
            ctx = " ".join(t[1] for t in self.t[max(0, self.i - 12):self.i + 6])
            raise SyntaxError(f"'{v}' 가 와야 하는데 '{self.peek()[1]}' : ... {ctx}")

    def ident(self):
        k, v = self.nxt()
        if k != "id":
            raise SyntaxError(f"이름이 와야 하는데 '{v}'")
        return v

    # ---------------------------------------------------------------- 식
    def expr(self):
        c = self.binop(1)
        if self.eat("?"):
            a = self.expr()
            self.expect(":")
            b = self.expr()
            return ("tern", c, a, b)
        return c

    def binop(self, minp):
        lhs = self.unary()
        while True:
            k, op = self.peek()
            if k == "op" and op in BINPREC and BINPREC[op] >= minp:
                self.nxt()
                rhs = self.binop(BINPREC[op] + 1)
                lhs = ("bin", op, lhs, rhs)
            else:
                return lhs

    def unary(self):
        k, v = self.peek()
        if k == "op" and v in ("!", "~", "-", "+", "&", "|", "^"):
            self.nxt()
            return ("un", v, self.unary())
        return self.primary()

    def selects(self, base):
        while self.at("["):
            self.nxt()
            a = self.expr()
            if self.eat(":"):
                b = self.expr()
                base = ("part", base, a, b)
            elif self.eat("+:"):
                base = ("ipart", base, a, self.expr(), 1)
            elif self.eat("-:"):
                base = ("ipart", base, a, self.expr(), -1)
            else:
                base = ("idx", base, a)
            self.expect("]")
        return base

    def primary(self):
        k, v = self.nxt()
        if v == "(" and k == "op":
            e = self.expr()
            self.expect(")")
            return e
        if v == "{" and k == "op":
            first = self.expr()
            if self.at("{"):
                self.nxt()
                parts = [self.expr()]
                while self.eat(","):
                    parts.append(self.expr())
                self.expect("}")
                self.expect("}")
                return ("rep", first, parts)
            parts = [first]
            while self.eat(","):
                parts.append(self.expr())
            self.expect("}")
            return ("cat", parts)
        if k in ("num", "dec"):
            return parse_number(v)
        if k == "id":
            if self.at("("):
                self.nxt()
                args = []
                if not self.at(")"):
                    args.append(self.expr())
                    while self.eat(","):
                        args.append(self.expr())
                self.expect(")")
                return ("call", v, args)
            return self.selects(("id", v))
        if k == "str":
            return ("str", v[1:-1])
        raise SyntaxError(f"식에서 예상 못 한 '{v}'")

    # ---------------------------------------------------------------- 문장
    def stmt(self):
        k, v = self.peek()
        if v == "begin":
            self.nxt()
            if self.eat(":"):
                self.ident()
            body = []
            while not self.at("end"):
                body.append(self.stmt())
            self.nxt()
            return ("block", body)
        if v == "if":
            self.nxt()
            self.expect("(")
            c = self.expr()
            self.expect(")")
            a = self.stmt()
            b = self.stmt() if self.eat("else") else None
            return ("if", c, a, b)
        if v in ("case", "casez", "casex"):
            self.nxt()
            self.expect("(")
            e = self.expr()
            self.expect(")")
            items = []
            while not self.at("endcase"):
                if self.eat("default"):
                    self.eat(":")
                    items.append((None, self.stmt()))
                else:
                    labels = [self.expr()]
                    while self.eat(","):
                        labels.append(self.expr())
                    self.expect(":")
                    items.append((labels, self.stmt()))
            self.nxt()
            return ("case", e, items)
        if v == "for":
            self.nxt()
            self.expect("(")
            lv = self.selects(("id", self.ident()))
            self.expect("=")
            init = ("ba", lv, self.expr())
            self.expect(";")
            cond = self.expr()
            self.expect(";")
            lv = self.selects(("id", self.ident()))
            self.expect("=")
            step = ("ba", lv, self.expr())
            self.expect(")")
            return ("for", init, cond, step, self.stmt())
        if v == ";" and k == "op":
            self.nxt()
            return ("null",)
        if k == "id" and v.startswith("$"):
            self.nxt()
            args = []
            if self.eat("("):
                if not self.at(")"):
                    args.append(self.expr())
                    while self.eat(","):
                        args.append(self.expr())
                self.expect(")")
            self.expect(";")
            return ("sys", v, args)
        name = self.ident()
        if self.at("(") or self.at(";"):
            args = []
            if self.eat("("):
                if not self.at(")"):
                    args.append(self.expr())
                    while self.eat(","):
                        args.append(self.expr())
                self.expect(")")
            self.expect(";")
            return ("tcall", name, args)
        lv = self.selects(("id", name))
        if self.eat("="):
            e = self.expr()
            self.expect(";")
            return ("ba", lv, e)
        self.expect("<=")
        e = self.expr()
        self.expect(";")
        return ("nba", lv, e)

    # ---------------------------------------------------------------- 선언
    def rng(self):
        if self.eat("["):
            a = self.expr()
            self.expect(":")
            b = self.expr()
            self.expect("]")
            return (a, b)
        return None

    def decl_tail(self, kind, signed, rng, portdir, stop_at_dir=False):
        """이름 [배열] [= 초기값] {, 이름 ...}  -> decl 목록"""
        out = []
        while True:
            name = self.ident()
            arr = self.rng()
            init = self.expr() if self.eat("=") else None
            out.append(("decl", kind, signed, rng, name, arr, init, portdir))
            if self.at(",") and not (stop_at_dir and self.peek(1)[1] in DIRS):
                self.nxt()
                continue
            return out

    def decl_head(self):
        portdir = self.nxt()[1] if self.peek()[1] in DIRS else None
        kind = "wire"
        if self.peek()[1] in ("wire", "reg", "integer", "genvar"):
            kind = self.nxt()[1]
        if portdir and self.peek()[1] == "integer":
            self.nxt()
            kind = "integer"
        signed = self.eat("signed")
        rng = self.rng()
        return kind, signed, rng, portdir

    def param_decl(self, local):
        """parameter/localparam [integer|signed|[r]] 이름 = 식 {, 이름 = 식}"""
        typ = None
        if self.eat("integer"):
            typ = ("int",)
        else:
            signed = self.eat("signed")
            r = self.rng()
            if r or signed:
                typ = ("range", r, signed)
        out = []
        while True:
            name = self.ident()
            self.expect("=")
            out.append(("param", name, typ, self.expr(), local))
            if self.at(",") and self.peek(1)[1] not in ("parameter", "localparam"):
                self.nxt()
                continue
            return out

    def module(self):
        self.expect("module")
        name = self.ident()
        items, ports = [], []
        if self.eat("#"):
            self.expect("(")
            while not self.at(")"):
                self.expect("parameter")
                items += self.param_decl(False)
                self.eat(",")
            self.nxt()
        if self.eat("("):
            while not self.at(")"):
                if self.peek()[1] in DIRS:
                    kind, signed, rng, portdir = self.decl_head()
                    ds = self.decl_tail(kind, signed, rng, portdir, stop_at_dir=True)
                    items += ds
                    ports += [d[4] for d in ds]
                else:
                    ports.append(self.ident())
                self.eat(",")
            self.nxt()
        self.expect(";")
        items += self.items(("endmodule",))
        self.nxt()
        return dict(name=name, ports=ports, items=items)

    def items(self, stops):
        items = []
        while self.peek()[1] not in stops:
            k, v = self.peek()
            if v in ("parameter", "localparam"):
                self.nxt()
                items += self.param_decl(v == "localparam")
                self.expect(";")
            elif v in DIRS or v in ("wire", "reg", "integer", "genvar"):
                kind, signed, rng, portdir = self.decl_head()
                items += self.decl_tail(kind, signed, rng, portdir)
                self.expect(";")
            elif v == "assign":
                self.nxt()
                while True:
                    lv = self.selects(("id", self.ident()))
                    self.expect("=")
                    items.append(("assign", lv, self.expr()))
                    if not self.eat(","):
                        break
                self.expect(";")
            elif v == "always":
                self.nxt()
                self.expect("@")
                self.expect("(")
                seq = False
                while not self.at(")"):
                    if self.nxt()[1] == "posedge":
                        seq = True
                self.nxt()
                items.append(("always", "seq" if seq else "comb", self.stmt()))
            elif v == "initial":
                self.nxt()
                items.append(("initial", self.stmt()))
            elif v == "function":
                self.nxt()
                signed = self.eat("signed")
                rng = self.rng()
                fname = self.ident()
                self.expect(";")
                decls = []
                while self.peek()[1] in DIRS + ("reg", "integer"):
                    kind, sg, r, portdir = self.decl_head()
                    decls += self.decl_tail(kind, sg, r, portdir)
                    self.expect(";")
                body = self.stmt()
                self.expect("endfunction")
                items.append(("func", fname, signed, rng, decls, body))
            elif v == "task":
                self.nxt()
                tname = self.ident()
                self.expect(";")
                decls = []
                while self.peek()[1] in DIRS + ("reg", "integer"):
                    kind, sg, r, portdir = self.decl_head()
                    decls += self.decl_tail(kind, sg, r, portdir)
                    self.expect(";")
                body = self.stmt()
                self.expect("endtask")
                items.append(("task", tname, decls, body))
            elif v == "generate":
                self.nxt()
                items += self.items(("endgenerate",))
                self.nxt()
            elif v == "for":
                self.nxt()
                self.expect("(")
                var = self.ident()
                self.expect("=")
                init = self.expr()
                self.expect(";")
                cond = self.expr()
                self.expect(";")
                self.ident()
                self.expect("=")
                step = self.expr()
                self.expect(")")
                self.expect("begin")
                label = self.ident() if self.eat(":") else "genblk"
                sub = self.items(("end",))
                self.nxt()
                items.append(("genfor", var, init, cond, step, label, sub))
            elif k == "id":
                mod = self.ident()
                params = []
                if self.eat("#"):
                    self.expect("(")
                    while not self.at(")"):
                        self.expect(".")
                        pn = self.ident()
                        self.expect("(")
                        params.append((pn, self.expr()))
                        self.expect(")")
                        self.eat(",")
                    self.nxt()
                inst = self.ident()
                self.expect("(")
                conns = []
                while not self.at(")"):
                    self.expect(".")
                    pn = self.ident()
                    self.expect("(")
                    conns.append((pn, None if self.at(")") else self.expr()))
                    self.expect(")")
                    self.eat(",")
                self.nxt()
                self.expect(";")
                items.append(("inst", mod, params, inst, conns))
            else:
                raise SyntaxError(f"모듈 항목에서 예상 못 한 '{v}'")
        return items


# ============================================================================ 엘라보레이션 + 코드 생성
class Scope:
    def __init__(self, parent, prefix):
        self.parent, self.prefix, self.names = parent, prefix, {}

    def lookup(self, name):
        sc = self
        while sc:
            if name in sc.names:
                return sc.names[name]
            sc = sc.parent
        raise NameError(f"선언 안 된 이름 '{name}' ({self.prefix})")


class Ctx:
    """코드 한 덩어리(프로세스·함수)를 만들면서 읽고 쓴 신호를 모음"""
    def __init__(self, seq=False):
        self.reads, self.writes, self.calls, self.seq = set(), set(), set(), seq


class Sim:
    def __init__(self, top, params=None, srcdirs=("rtl",), romdir="rom", randinit=None, verbose=False):
        self.modules = {}
        incdirs = [os.path.join(ROOT, "rtl", "include")]
        for d in srcdirs:
            for dp, _, fs in os.walk(os.path.join(ROOT, d)):
                for f in sorted(fs):
                    if f.endswith(".v"):
                        p = Parser(tokenize(preprocess(os.path.join(dp, f), incdirs)))
                        while p.peek()[0] != "eof":
                            m = p.module()
                            self.modules[m["name"]] = m
        self.romdir = os.path.join(ROOT, romdir)
        self.names, self.sigw, self.sigs_signed = {}, [], []      # 이름 -> id, 폭, 부호
        self.init = []                                           # 초기값
        self.mem_names, self.mem_init, self.mem_w = {}, [], []
        self.locals = set()                                      # 함수·태스크 지역 신호 (의존성에서 뺌)
        self.procs, self.seqs, self.defs = [], [], []
        self.seq_written, self.explicit_init, self.rom_mems = set(), set(), set()
        self.uid = 0
        self.func_globals = []
        self.port_names = {}
        self.rng = random.Random(randinit)
        top_sc = Scope(None, "")
        ov = {k: (v & mask(32), 32, True) for k, v in (params or {}).items()}
        self.elab_module(top, top_sc, ov)
        self.build(verbose)
        self.reset_state(randinit)

    # ---------------------------------------------------------------- 신호
    def new_sig(self, sc, name, w, signed, local=False):
        i = len(self.sigw)
        self.sigw.append(w)
        self.sigs_signed.append(signed)
        self.init.append(0)
        self.names[sc.prefix + name] = i
        if local:
            self.locals.add(i)
        return i

    def tmp(self):
        self.uid += 1
        return f"_t{self.uid}"

    # ---------------------------------------------------------------- 폭·부호
    def typeof(self, e, sc):
        k = e[0]
        if k == "num":
            return (e[2] or 32, e[3])
        if k == "id":
            sym = sc.lookup(e[1])
            if sym[0] in ("sig", "const"):
                return (sym[2], sym[3])
            raise TypeError(f"'{e[1]}' 는 값으로 쓸 수 없음")
        if k == "idx":
            if e[1][0] == "id":
                sym = sc.lookup(e[1][1])
                if sym[0] == "mem":
                    return (sym[2], sym[3])
            return (1, False)
        if k == "part":
            return (self.cint(e[2], sc) - self.cint(e[3], sc) + 1, False)
        if k == "ipart":
            return (self.cint(e[3], sc), False)
        if k == "cat":
            return (sum(self.typeof(p, sc)[0] for p in e[1]), False)
        if k == "rep":
            return (self.cint(e[1], sc) * sum(self.typeof(p, sc)[0] for p in e[2]), False)
        if k == "un":
            return (1, False) if e[1] in ("!", "&", "|", "^") else self.typeof(e[2], sc)
        if k == "bin":
            op = e[1]
            if op in ("==", "!=", "<", "<=", ">", ">=", "&&", "||"):
                return (1, False)
            if op in ("<<", ">>", ">>>", "<<<"):
                return self.typeof(e[2], sc)
            (wl, sl), (wr, sr) = self.typeof(e[2], sc), self.typeof(e[3], sc)
            return (max(wl, wr), sl and sr)
        if k == "tern":
            (wa, sa), (wb, sb) = self.typeof(e[2], sc), self.typeof(e[3], sc)
            return (max(wa, wb), sa and sb)
        if k == "call":
            if e[1] in ("$signed", "$unsigned"):
                return (self.typeof(e[2][0], sc)[0], e[1] == "$signed")
            sym = sc.lookup(e[1])
            return (sym[2], sym[3])
        raise TypeError(k)

    # ---------------------------------------------------------------- 상수 계산
    def cval(self, e, sc):
        w, s = self.typeof(e, sc)
        return eval(self.gen(e, sc, w, s, Ctx()), dict(HELPERS)), w, s

    def cint(self, e, sc):
        v, w, s = self.cval(e, sc)
        return _ts(v, w) if s else v

    # ---------------------------------------------------------------- 식 -> Python
    @staticmethod
    def ext(code, w0, s0, W, S):
        if W <= w0:
            return code
        if S and s0:
            return f"_sx({code},{1 << (w0 - 1)},{mask(W) ^ mask(w0)})"
        return code

    def gen(self, e, sc, W, S, ctx):
        """식 e 를 문맥 폭 W, 문맥 부호 S 로 계산하는 Python 식 (결과는 W비트 부호 없는 정수)"""
        k = e[0]
        M = mask(W)
        if k == "un" and e[1] in ("-", "~", "+"):
            a = self.gen(e[2], sc, W, S, ctx)
            return a if e[1] == "+" else f"((-{a})&{M})" if e[1] == "-" else f"({a}^{M})"
        if k == "bin" and e[1] in ("+", "-", "*", "&", "|", "^", "/", "%"):
            a, b = self.gen(e[2], sc, W, S, ctx), self.gen(e[3], sc, W, S, ctx)
            op = e[1]
            if op in ("&", "|", "^"):
                return f"({a}{op}{b})"
            if op in ("/", "%"):
                if S:
                    return f"_sdiv({a},{b},{W},{op == '%'})"
                return f"({'_udiv' if op == '/' else '_umod'}({a},{b})&{M})"
            return f"(({a}{op}{b})&{M})"
        if k == "bin" and e[1] in ("<<", ">>", ">>>", "<<<"):
            a = self.gen(e[2], sc, W, S, ctx)
            wr, sr = self.typeof(e[3], sc)
            b = self.gen(e[3], sc, wr, sr, ctx)
            if e[1] in ("<<", "<<<"):
                return f"(({a}<<{b})&{M})"
            if e[1] == ">>>" and S:
                return f"((_ts({a},{W})>>{b})&{M})"
            return f"({a}>>{b})"
        if k == "tern":
            c = self.gself(e[1], sc, ctx)[0]
            return f"({self.gen(e[2], sc, W, S, ctx)} if {c} else {self.gen(e[3], sc, W, S, ctx)})"
        code, w0, s0 = self.gself(e, sc, ctx)
        return self.ext(code, w0, s0, W, S)

    def gself(self, e, sc, ctx):
        """자기 폭으로 계산 -> (코드, 폭, 부호)"""
        k = e[0]
        w, s = self.typeof(e, sc)
        if k == "num":
            return str(e[1]), w, s
        if k == "id":
            sym = sc.lookup(e[1])
            if sym[0] == "const":
                return str(sym[1]), w, s
            ctx.reads.add(sym[1])
            return f"s[{sym[1]}]", w, s
        if k == "idx":
            wi, si = self.typeof(e[2], sc)
            i = self.gen(e[2], sc, wi, si, ctx)
            if e[1][0] == "id":
                sym = sc.lookup(e[1][1])
                if sym[0] == "mem":
                    ctx.reads.add(("m", sym[1]))
                    return f"_mr(m[{sym[1]}],{i})", w, s
            b = self.gself(e[1], sc, ctx)[0]
            return f"(({b}>>{i})&1)", 1, False
        if k == "part":
            b = self.gself(e[1], sc, ctx)[0]
            lo = self.cint(e[3], sc)
            return f"(({b}>>{lo})&{mask(w)})", w, False
        if k == "ipart":
            b = self.gself(e[1], sc, ctx)[0]
            wi, si = self.typeof(e[2], sc)
            st = self.gen(e[2], sc, wi, si, ctx)
            if e[4] < 0:
                st = f"({st}-{w - 1})"
            return f"(({b}>>{st})&{mask(w)})", w, False
        if k in ("cat", "rep"):
            parts = e[1] if k == "cat" else e[2]
            code, tot = "0", 0
            for p in parts:
                c, pw, _ = self.gself(p, sc, ctx)
                code = f"(({code}<<{pw})|{c})"
                tot += pw
            if k == "rep":
                n = self.cint(e[1], sc)
                t = code
                code = "0"
                for _ in range(n):
                    code = f"(({code}<<{tot})|{t})"
            return code, w, False
        if k == "un":
            wo, so = self.typeof(e[2], sc)
            a = self.gen(e[2], sc, wo, so, ctx)
            if e[1] == "!":
                return f"(0 if {a} else 1)", 1, False
            if e[1] == "|":
                return f"(1 if {a} else 0)", 1, False
            if e[1] == "&":
                return f"(1 if {a}=={mask(wo)} else 0)", 1, False
            if e[1] == "^":
                return f"_par({a})", 1, False
            return self.gen(e, sc, w, s, ctx), w, s
        if k == "bin":
            op = e[1]
            if op in ("&&", "||"):
                a, b = self.gself(e[2], sc, ctx)[0], self.gself(e[3], sc, ctx)[0]
                return f"(1 if ({a}) {'and' if op == '&&' else 'or'} ({b}) else 0)", 1, False
            if op in ("==", "!=", "<", "<=", ">", ">="):
                (wl, sl), (wr, sr) = self.typeof(e[2], sc), self.typeof(e[3], sc)
                wc, scm = max(wl, wr), sl and sr
                a, b = self.gen(e[2], sc, wc, scm, ctx), self.gen(e[3], sc, wc, scm, ctx)
                if scm and op not in ("==", "!="):
                    a, b = f"_ts({a},{wc})", f"_ts({b},{wc})"
                return f"(1 if {a}{op}{b} else 0)", 1, False
            return self.gen(e, sc, w, s, ctx), w, s
        if k == "tern":
            return self.gen(e, sc, w, s, ctx), w, s
        if k == "call":
            if e[1] in ("$signed", "$unsigned"):
                return self.gself(e[2][0], sc, ctx)[0], w, s
            sym = sc.lookup(e[1])
            _, py, rw, rs, ins, info = sym
            args = [self.assign_val(a, sc, iw, ctx) for a, (iw, _) in zip(e[2], ins)]
            ctx.calls.add(info)
            return f"{py}(s,m,{','.join(args)})", rw, rs
        raise TypeError(k)

    def assign_val(self, e, sc, wl, ctx):
        """대입: 오른쪽을 max(왼쪽 폭, 오른쪽 폭)으로 계산한 뒤 왼쪽 폭으로 자름"""
        wr, sr = self.typeof(e, sc)
        W = max(wl, wr)
        code = self.gen(e, sc, W, sr, ctx)
        return f"({code}&{mask(wl)})" if W > wl else code

    # ---------------------------------------------------------------- 문장 -> Python
    def lv_info(self, lv, sc):
        """(종류, id, 폭, 추가) : full / bit / part / mem"""
        k = lv[0]
        if k == "id":
            sym = sc.lookup(lv[1])
            return ("full", sym[1], sym[2], None)
        base = sc.lookup(lv[1][1])
        if k == "idx":
            if base[0] == "mem":
                return ("mem", base[1], base[2], lv[2])
            return ("bit", base[1], 1, lv[2])
        if k == "part":
            hi, lo = self.cint(lv[2], sc), self.cint(lv[3], sc)
            return ("part", base[1], hi - lo + 1, lo)
        if k == "ipart":
            w = self.cint(lv[3], sc)
            return ("ipart", base[1], w, (lv[2], lv[4]))
        raise TypeError(k)

    def emit_assign(self, out, ind, lv, e, sc, ctx, nb):
        kind, sid, w, extra = self.lv_info(lv, sc)
        val = self.assign_val(e, sc, w, ctx)
        pad = "    " * ind
        if kind == "mem":
            wi, si = self.typeof(extra, sc)
            idx = self.gen(extra, sc, wi, si, ctx)
            if nb:
                ctx.writes.add(("m", sid))
                out.append(f"{pad}n.append((2,{sid},{idx},{val}))")
            else:
                ctx.writes.add(("m", sid))
                t = self.tmp()
                out.append(f"{pad}{t}={idx}")
                out.append(f"{pad}if {t}<len(m[{sid}]): m[{sid}][{t}]={val}")
            return
        ctx.writes.add(sid)
        if kind == "full":
            out.append(f"{pad}n.append((0,{sid},{val}))" if nb else f"{pad}s[{sid}]={val}")
            return
        if kind == "bit":
            wi, si = self.typeof(extra, sc)
            pos = self.gen(extra, sc, wi, si, ctx)
        elif kind == "part":
            pos = str(extra)
        else:
            wi, si = self.typeof(extra[0], sc)
            pos = self.gen(extra[0], sc, wi, si, ctx)
            if extra[1] < 0:
                pos = f"({pos}-{w - 1})"
        t = self.tmp()
        out.append(f"{pad}{t}={pos}")
        if nb:
            out.append(f"{pad}n.append((1,{sid},{mask(w)}<<{t},({val})<<{t}))")
        else:
            out.append(f"{pad}s[{sid}]=(s[{sid}]&~({mask(w)}<<{t}))|(({val})<<{t})")

    def emit(self, out, ind, st, sc, ctx):
        pad = "    " * ind
        k = st[0]
        if k == "block":
            if not st[1]:
                out.append(pad + "pass")
            for x in st[1]:
                self.emit(out, ind, x, sc, ctx)
        elif k == "if":
            out.append(f"{pad}if {self.gself(st[1], sc, ctx)[0]}:")
            self.emit(out, ind + 1, st[2], sc, ctx)
            if st[3]:
                out.append(pad + "else:")
                self.emit(out, ind + 1, st[3], sc, ctx)
        elif k == "case":
            ws = [self.typeof(st[1], sc)] + [self.typeof(l, sc) for labels, _ in st[2] if labels for l in labels]
            wc, scm = max(w for w, _ in ws), all(s for _, s in ws)
            t = self.tmp()
            out.append(f"{pad}{t}={self.gen(st[1], sc, wc, scm, ctx)}")
            first, default = True, None
            for labels, body in st[2]:
                if labels is None:
                    default = body
                    continue
                cond = " or ".join(f"{t}=={self.gen(l, sc, wc, scm, ctx)}" for l in labels)
                out.append(f"{pad}{'if' if first else 'elif'} {cond}:")
                self.emit(out, ind + 1, body, sc, ctx)
                first = False
            if default is not None:
                if first:
                    self.emit(out, ind, default, sc, ctx)
                else:
                    out.append(pad + "else:")
                    self.emit(out, ind + 1, default, sc, ctx)
        elif k == "for":
            self.emit(out, ind, st[1], sc, ctx)
            out.append(f"{pad}while {self.gself(st[2], sc, ctx)[0]}:")
            self.emit(out, ind + 1, st[4], sc, ctx)
            self.emit(out, ind + 1, st[3], sc, ctx)
        elif k in ("ba", "nba"):
            if k == "nba" and not ctx.seq:
                raise TypeError("조합 블록 안의 <=")
            self.emit_assign(out, ind, st[1], st[2], sc, ctx, k == "nba")
        elif k == "tcall":
            sym = sc.lookup(st[1])
            _, py, ins, info = sym
            args = [self.assign_val(a, sc, iw, ctx) for a, (iw, _) in zip(st[2], ins)]
            ctx.calls.add(info)
            out.append(f"{pad}{py}(s,m,n{''.join(',' + a for a in args)})")
        elif k in ("null", "sys"):
            out.append(pad + "pass")
        else:
            raise TypeError(k)

    # ---------------------------------------------------------------- 모듈 항목
    def decl_width(self, d, sc):
        _, kind, signed, rng, name, arr, init, portdir = d
        if kind == "integer":
            return 32, True
        if rng:
            hi, lo = self.cint(rng[0], sc), self.cint(rng[1], sc)
            assert lo == 0, f"{name}: [N:0] 꼴만 지원"
            return hi + 1, signed
        return 1, signed

    def declare(self, d, sc, local=False):
        _, kind, signed, rng, name, arr, init, portdir = d
        w, sg = self.decl_width(d, sc)
        if kind == "genvar":
            return
        if arr:
            a, b = self.cint(arr[0], sc), self.cint(arr[1], sc)
            mid = len(self.mem_init)
            self.mem_init.append([0] * (max(a, b) + 1))
            self.mem_w.append(w)
            self.mem_names[sc.prefix + name] = mid
            sc.names[name] = ("mem", mid, w, sg)
            return
        if name in sc.names:
            if sc.names[name][0] == "sig" and portdir is None and name in self.port_names.get(sc.prefix, ()):
                return                                           # 비 ANSI 포트: output 뒤에 reg 다시 선언
            raise NameError(f"'{sc.prefix}{name}' 를 두 번 선언함")
        if portdir:
            self.port_names.setdefault(sc.prefix, set()).add(name)
        sid = self.new_sig(sc, name, w, sg, local)
        sc.names[name] = ("sig", sid, w, sg)

    def process_items(self, items, sc, overrides):
        # 1) 선언·상수·함수 머리
        funcs = []
        for it in items:
            k = it[0]
            if k == "param":
                _, name, typ, e, local = it
                if not local and name in overrides:
                    v, w, s = overrides[name]
                else:
                    v, w, s = self.cval(e, sc)
                if typ == ("int",):
                    v, w, s = (_ts(v, w) if s else v) & mask(32), 32, True
                elif typ:
                    r, sg = typ[1], typ[2]
                    nw = self.cint(r[0], sc) - self.cint(r[1], sc) + 1 if r else w
                    v = (_sx(v, 1 << (w - 1), mask(nw) ^ mask(w)) if (s and nw > w) else v) & mask(nw)
                    w, s = nw, sg
                if name in sc.names:
                    raise NameError(f"'{sc.prefix}{name}' 를 두 번 선언함")
                sc.names[name] = ("const", v, w, s)
            elif k == "decl":
                self.declare(it, sc)
                if it[6] is not None and it[1] == "reg":
                    sid = sc.names[it[4]][1]
                    self.init[sid] = self.cval(it[6], sc)[0] & mask(self.sigw[sid])
                    self.explicit_init.add(sid)
            elif k in ("func", "task"):
                name = it[1]
                fsc = Scope(sc, sc.prefix + name + ".")
                decls = it[4] if k == "func" else it[2]
                ins = []
                for d in decls:
                    self.declare(d, fsc, local=True)
                    if d[7] == "input":
                        ins.append((fsc.names[d[4]][1], fsc.names[d[4]][2], fsc.names[d[4]][3]))
                self.uid += 1
                py = f"{'f' if k == 'func' else 't'}{self.uid}_{name}"
                info = Ctx(seq=(k == "task"))
                if k == "func":
                    rw = self.cint(it[3][0], sc) - self.cint(it[3][1], sc) + 1 if it[3] else 1
                    rid = self.new_sig(fsc, name, rw, it[2], local=True)
                    fsc.names[name] = ("sig", rid, rw, it[2])
                    sc.names[name] = ("func", py, rw, it[2], [(w, s) for _, w, s in ins], info)
                else:
                    rid = None
                    sc.names[name] = ("task", py, [(w, s) for _, w, s in ins], info)
                funcs.append((it, fsc, py, ins, rid, info))
        # 2) 함수·태스크 몸통
        for it, fsc, py, ins, rid, info in funcs:
            body = it[5] if it[0] == "func" else it[3]
            argn = [f"a{i}" for i in range(len(ins))]
            lines = [f"def {py}(s,m{',n' if it[0] == 'task' else ''}{''.join(',' + a for a in argn)}):"]
            for a, (sid, _, _) in zip(argn, ins):
                lines.append(f"    s[{sid}]={a}")
            self.emit(lines, 1, body, fsc, info)
            if rid is not None:
                lines.append(f"    return s[{rid}]")
                outside = [x for x in info.reads if x not in self.locals]
                if outside:      # xsim 등에서는 assign/always @* 가 이런 신호의 변화를 못 봄
                    self.func_globals.append(sc.prefix + it[1])
            self.defs.append("\n".join(lines))
        # 3) 동작
        for it in items:
            k = it[0]
            if k == "decl" and it[6] is not None and it[1] == "wire":
                self.add_comb([("ba", ("id", it[4]), it[6])], sc, sc.prefix + it[4])
            elif k == "assign":
                self.add_comb([("ba", it[1], it[2])], sc, sc.prefix + "assign")
            elif k == "always":
                if it[1] == "comb":
                    self.add_comb([it[2]], sc, sc.prefix + "always@*")
                else:
                    ctx = Ctx(seq=True)
                    lines = []
                    self.emit(lines, 1, it[2], sc, ctx)
                    self.seqs.append("\n".join(lines))
                    self.collect_seq_writes(ctx)
            elif k == "initial":
                self.do_initial(it[1], sc)
            elif k == "inst":
                self.elab_inst(it, sc)
            elif k == "genfor":
                _, var, init, cond, step, label, sub = it
                gsc = Scope(sc, sc.prefix)
                gsc.names[var] = ("const", self.cint(init, sc) & mask(32), 32, True)
                while self.cint(cond, gsc):
                    i = _ts(gsc.names[var][1], 32)
                    isc = Scope(gsc, f"{sc.prefix}{label}[{i}].")
                    self.process_items(sub, isc, {})
                    gsc.names[var] = ("const", self.cint(step, gsc) & mask(32), 32, True)

    def collect_seq_writes(self, ctx, seen=None):
        seen = seen or set()
        self.seq_written |= ctx.writes
        for c in ctx.calls:
            if id(c) not in seen:
                seen.add(id(c))
                self.collect_seq_writes(c, seen)

    def add_comb(self, stmts, sc, name):
        ctx = Ctx()
        lines = []
        for st in stmts:
            self.emit(lines, 1, st, sc, ctx)
        self.procs.append(dict(name=name, lines=lines, ctx=ctx))

    def do_initial(self, st, sc):
        if st[0] == "block":
            for x in st[1]:
                self.do_initial(x, sc)
        elif st[0] == "sys" and st[1] == "$readmemh":
            fname, mem = st[2][0][1], sc.lookup(st[2][1][1])
            words = []
            with open(os.path.join(self.romdir, fname), encoding="utf-8") as f:
                for line in f:
                    line = line.split("//")[0]
                    words += [int(x, 16) for x in line.split()]
            arr = self.mem_init[mem[1]]
            assert len(words) <= len(arr), f"{fname}: 메모리보다 큼"
            for i, v in enumerate(words):
                arr[i] = v & mask(mem[2])
            self.rom_mems.add(mem[1])

    def elab_module(self, modname, sc, overrides):
        self.process_items(self.modules[modname]["items"], sc, overrides)

    def elab_inst(self, it, sc):
        _, modname, params, inst, conns = it
        mod = self.modules[modname]
        ov = {pn: self.cval(e, sc) for pn, e in params}
        pnames = {i[1] for i in mod["items"] if i[0] == "param" and not i[4]}
        for pn in ov:
            assert pn in pnames, f"{modname} 에 파라미터 {pn} 없음"
        csc = Scope(None, sc.prefix + inst + ".")
        self.elab_module(modname, csc, ov)
        dirs = {d[4]: d[7] for d in mod["items"] if d[0] == "decl" and d[7]}
        for pn, e in conns:
            assert pn in dirs, f"{modname} 에 포트 {pn} 없음"
            if e is None:
                continue
            child = csc.names[pn]
            if dirs[pn] == "input":
                ctx = Ctx()
                val = self.assign_val(e, sc, child[2], ctx)
                ctx.writes.add(child[1])
                self.procs.append(dict(name=csc.prefix + pn, lines=[f"    s[{child[1]}]={val}"], ctx=ctx))
            else:
                ctx = Ctx()
                lines = []
                kind, sid, w, extra = self.lv_info(e, sc)
                # 자식 출력 -> 부모 신호 (부모 쪽 폭에 맞춤)
                self.uid += 1
                tmpname = f"__o{self.uid}"
                tsc = Scope(sc, sc.prefix)
                tsc.names[tmpname] = child
                self.emit_assign(lines, 1, e, ("id", tmpname), tsc, ctx, False)
                self.procs.append(dict(name=csc.prefix + pn, lines=lines, ctx=ctx))
        missing = [p for p, d in dirs.items() if d == "input" and p not in {c[0] for c in conns}]
        assert not missing, f"{sc.prefix}{inst}: 입력 포트 연결 안 됨 {missing}"

    # ---------------------------------------------------------------- 조합 순서 + 코드 만들기
    def build(self, verbose):
        def all_reads(ctx, seen):
            r = set(ctx.reads)
            for c in ctx.calls:
                if id(c) not in seen:
                    seen.add(id(c))
                    r |= all_reads(c, seen)
            return r
        n = len(self.procs)
        writers = {}
        for i, p in enumerate(self.procs):
            p["w"] = {x for x in p["ctx"].writes if x not in self.locals}
            p["r"] = {x for x in all_reads(p["ctx"], set()) if x not in self.locals} - p["w"]
            for x in p["w"]:
                writers.setdefault(x, []).append(i)
        succ, indeg = [set() for _ in range(n)], [0] * n
        for i, p in enumerate(self.procs):
            for x in p["r"]:
                for wtr in writers.get(x, ()):
                    if wtr != i and i not in succ[wtr]:
                        succ[wtr].add(i)
                        indeg[i] += 1
        order, ready = [], [i for i in range(n) if indeg[i] == 0]
        while ready:
            i = ready.pop()
            order.append(i)
            for j in succ[i]:
                indeg[j] -= 1
                if indeg[j] == 0:
                    ready.append(j)
        self.cyclic = [self.procs[i]["name"] for i in range(n) if indeg[i] > 0]
        order += [i for i in range(n) if indeg[i] > 0]
        # 조합 신호를 여러 프로세스가 통째로 쓰면 오류 (다중 구동)
        self.comb_written = set(writers)
        src = ["\n\n".join(self.defs), "def comb(s,m):"]
        for i in order:
            src += self.procs[i]["lines"]
        src.append("    return None")
        src.append("def seq(s,m,n):")
        for blk in self.seqs:
            src.append(blk)
        src.append("    return None")
        self.source = "\n".join(src)
        env = dict(HELPERS)
        exec(compile(self.source, "<minisim>", "exec"), env)
        self._comb, self._seq = env["comb"], env["seq"]
        both = {x for x in self.seq_written & self.comb_written if x not in self.locals}
        inv = {v: k for k, v in self.names.items()}
        self.multi = sorted(inv.get(x, str(x)) for x in both if not isinstance(x, tuple))
        if verbose:
            print(f"신호 {len(self.sigw)}개, 메모리 {len(self.mem_init)}개, 조합 프로세스 {n}개, 클럭 블록 {len(self.seqs)}개")
            if self.cyclic:
                print("조합 루프(블록 단위):", self.cyclic)
            if self.multi:
                print("조합·클럭 양쪽에서 쓰는 신호:", self.multi)
            if self.func_globals:
                print("모듈 신호를 직접 읽는 함수:", self.func_globals)

    # ---------------------------------------------------------------- 실행
    def reset_state(self, randinit=None):
        self.s = list(self.init)
        self.m = [list(a) for a in self.mem_init]
        if randinit is not None:       # 리셋 안 한 레지스터에 기대는 버그를 찾으려고 아무 값이나 넣음
            for x in self.seq_written:
                if isinstance(x, tuple):
                    if x[1] not in self.rom_mems:
                        self.m[x[1]] = [self.rng.getrandbits(self.mem_w[x[1]]) for _ in self.m[x[1]]]
                elif x not in self.explicit_init and x not in self.locals:
                    self.s[x] = self.rng.getrandbits(self.sigw[x])
        self.cycles = 0
        self.settle()

    def settle(self):
        s, m = self.s, self.m
        self._comb(s, m)
        if self.cyclic:
            for _ in range(20):
                before = list(s)
                self._comb(s, m)
                if before == s:
                    return
            raise RuntimeError("조합 루프가 안정되지 않음")

    def clock(self, n=1):
        s, m, seq, comb = self.s, self.m, self._seq, self._comb
        for _ in range(n):
            nb = []
            seq(s, m, nb)
            for u in nb:
                if u[0] == 0:
                    s[u[1]] = u[2]
                elif u[0] == 1:
                    s[u[1]] = (s[u[1]] & ~u[2]) | u[3]
                elif u[2] < len(m[u[1]]):
                    m[u[1]][u[2]] = u[3]
            if self.cyclic:
                self.settle()
            else:
                comb(s, m)
        self.cycles += n

    def set(self, name, v):
        i = self.names[name]
        self.s[i] = v & mask(self.sigw[i])
        self.settle()

    def get(self, name, signed=None):
        i = self.names[name]
        v = self.s[i]
        if signed if signed is not None else self.sigs_signed[i]:
            return _ts(v, self.sigw[i])
        return v

    def mem(self, name):
        return self.m[self.mem_names[name]]


if __name__ == "__main__":
    import sys
    top = sys.argv[1] if len(sys.argv) > 1 else "fortress_top"
    sim = Sim(top, verbose=True)
    print("엘라보레이션 성공:", top)
