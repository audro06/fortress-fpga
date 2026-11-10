#!/usr/bin/env python3
"""가벼운 Verilog 정적 검사 (시뮬레이터가 없는 환경에서 실수 거르기용)

검사 항목
  1. module/endmodule, begin/end, case/endcase, function/task, generate 짝
  2. 인스턴스 포트 이름이 실제 모듈 포트에 있는지, 빠진 포트(경고)
  3. 선언 안 된 식별자 사용 (오타 찾기)
  4. 선언보다 먼저 쓴 wire/reg (Vivado 에러)
실행: python3 tools/check_rtl.py   (레포 루트에서)
Vivado 문법 검사를 대신하지는 못해요. 보드에 올리기 전 Vivado에서 꼭 합성해 보세요.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = os.path.join(ROOT, "rtl", "include")

KEYWORDS = set("""
module endmodule input output inout wire reg integer real time parameter localparam genvar generate endgenerate
always initial begin end if else case casez casex endcase default for while repeat forever assign posedge negedge or
and not function endfunction task endtask signed unsigned wait disable fork join
""".split())


RESERVED = set("""always and assign automatic begin buf bufif0 bufif1 case casex casez cell cmos config deassign default
defparam design disable edge else end endcase endconfig endfunction endgenerate endmodule endprimitive endspecify endtable
endtask event for force forever fork function generate genvar highz0 highz1 if ifnone incdir include initial inout input
instance integer join large liblist library localparam macromodule medium module nand negedge nmos nor noshowcancelled not
notif0 notif1 or output parameter pmos posedge primitive pull0 pull1 pulldown pullup pulsestyle_onevent pulsestyle_ondetect
rcmos real realtime reg release repeat rnmos rpmos rtran rtranif0 rtranif1 scalared showcancelled signed small specify
specparam strong0 strong1 supply0 supply1 table task time tran tranif0 tranif1 tri tri0 tri1 triand trior trireg unsigned use
vectored wait wand weak0 weak1 while wire wor xnor xor""".split())
# SystemVerilog 예약어 (파일을 SV로 읽는 도구를 쓸 때를 대비)
RESERVED_SV = set("""alias always_comb always_ff always_latch assert assume before bind bins binsof bit break byte chandle
checker class clocking const constraint context continue cover covergroup coverpoint cross dist do endchecker endclass
endclocking endgroup endinterface endpackage endprogram endproperty endsequence enum expect export extends extern final
first_match foreach forkjoin iff ignore_bins illegal_bins import inside int interface intersect join_any join_none let local
logic longint matches modport new null package packed priority program property protected pure rand randc randcase
randsequence ref return sequence shortint shortreal solve static string struct super tagged this throughout timeprecision
timeunit type typedef union unique var virtual void wait_order wildcard with within""".split())


def strip(src):
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    return src


def expand_includes(src):
    def rep(m):
        p = os.path.join(INC, m.group(1))
        with open(p, encoding="utf-8") as f:
            return strip(f.read())
    return re.sub(r'`include\s+"([^"]+)"', rep, src)


def files():
    out = []
    for d in ("rtl", "sim"):
        for dp, _, fs in os.walk(os.path.join(ROOT, d)):
            for f in fs:
                if f.endswith(".v"):
                    out.append(os.path.join(dp, f))
    return sorted(out)


MOD_RE = re.compile(r"\bmodule\s+(\w+)\s*(#\s*\((.*?)\))?\s*(\((.*?)\))?\s*;(.*?)\bendmodule\b", re.S)


def parse_ports(header, body):
    ports = {}
    text = (header or "")
    text = re.sub(r"=\s*[^,)]*", "", text)
    for m in re.finditer(r"\b(input|output|inout)\b([^,;()]*?)(\w+)\s*(?=,|$|\))", text + ")"):
        ports[m.group(3)] = m.group(1)
    if ports:
        return ports
    # 비 ANSI 스타일 (trigger.v): 몸통의 input/output 선언 (function/task 안은 제외)
    body = re.sub(r"\b(function|task)\b.*?\bend(function|task)\b", " ", body, flags=re.S)
    for m in re.finditer(r"\b(input|output|inout)\b([^;]*);", body):
        decl = m.group(2)
        decl = re.sub(r"\[[^\]]*\]", " ", decl)
        decl = re.sub(r"\b(wire|reg|signed)\b", " ", decl)
        for n in re.findall(r"\b([A-Za-z_]\w*)\b", decl):
            ports[n] = m.group(1)
    return ports


def balance(name, body, errs):
    toks = re.findall(r"\b(begin|end|case|casez|casex|endcase|function|endfunction|task|endtask|generate|endgenerate|fork|join)\b", body)
    st = []
    pair = {"end": "begin", "endcase": "case", "endfunction": "function", "endtask": "task", "endgenerate": "generate", "join": "fork"}
    for t in toks:
        if t in ("casez", "casex"):
            t = "case"
        if t in pair:
            if not st or st[-1] != pair[t]:
                errs.append(f"{name}: '{t}' 짝이 안 맞음 (스택 {st[-3:]})")
                return
            st.pop()
        else:
            st.append(t)
    if st:
        errs.append(f"{name}: 닫히지 않은 블록 {st}")


def declared_names(header, params, body):
    names = set()
    all_text = (params or "") + " ; " + (header or "") + " ; " + body
    decl_re = re.compile(r"\b(wire|reg|integer|genvar|input|output|inout|localparam|parameter)\b(.*?)(;|\)\s*;|$)", re.S)
    for m in decl_re.finditer(all_text):
        d = m.group(2)
        d = re.sub(r"\[[^\]]*\]", " ", d)
        # 초기값/대입 부분 제거: name = expr, ...
        parts = split_top(d)
        for p in parts:
            p = p.split("=")[0]
            p = re.sub(r"\b(wire|reg|signed|unsigned|integer|input|output|inout)\b", " ", p)
            ids = re.findall(r"\b([A-Za-z_]\w*)\b", p)
            if ids:
                names.add(ids[-1])
    for m in re.finditer(r"\b(function|task)\b\s*(?:\[[^\]]*\]\s*)?(\w+)", body):
        names.add(m.group(2))
    for m in re.finditer(r"\bbegin\s*:\s*(\w+)", body):
        names.add(m.group(1))
    return names


def split_top(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "({":
            depth += 1
        elif ch in ")}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return out


def main():
    errs, warns = [], []
    mods = {}
    srcs = {}
    for p in files():
        with open(p, encoding="utf-8") as f:
            raw = f.read()
            raw = re.sub(r'`include\s+"([^"]+)"', lambda m: "`include <" + m.group(1) + ">", raw)
            s = strip(raw)
            s = re.sub(r"`include\s+<([^>]+)>", lambda m: strip(open(os.path.join(INC, m.group(1)), encoding="utf-8").read()), s)
        srcs[p] = s
        for m in MOD_RE.finditer(s):
            name, params, header, body = m.group(1), m.group(3), m.group(5), m.group(6)
            mods[name] = dict(file=os.path.relpath(p, ROOT), params=params, header=header, body=body,
                              ports=parse_ports(header, body))
    mod_names = set(mods)

    for name, md in mods.items():
        body = md["body"]
        balance(name, body, errs)
        decl = declared_names(md["header"], md["params"], body)
        decl |= set(md["ports"])
        for bad in sorted((decl | {name}) & (RESERVED | RESERVED_SV)):
            errs.append(f"{name}: 예약어 '{bad}' 를 이름으로 씀")
        # 인스턴스
        inst_re = re.compile(r"\b(\w+)\s*(#\s*\((?:[^()]|\([^()]*\))*\))?\s+(\w+)\s*\(((?:[^;])*?)\)\s*;", re.S)
        inst_names = set()
        for im in inst_re.finditer(body):
            mn, iname, conns = im.group(1), im.group(3), im.group(4)
            if mn not in mod_names:
                continue
            inst_names.add(iname)
            sub = mods[mn]
            used = set()
            for pm in re.finditer(r"\.(\w+)\s*\(", conns):
                pn = pm.group(1)
                used.add(pn)
                if pn not in sub["ports"]:
                    errs.append(f"{name}.{iname}: 모듈 {mn} 에 포트 '{pn}' 없음")
            if "." in conns:
                miss = [p for p in sub["ports"] if p not in used]
                if miss:
                    warns.append(f"{name}.{iname}: {mn} 포트 연결 안 함 {miss}")
            if im.group(2):
                for pm in re.finditer(r"\.(\w+)\s*\(", im.group(2)):
                    if not re.search(r"\bparameter\b[^;]*?\b" + pm.group(1) + r"\b", (sub["params"] or "") + sub["body"]):
                        errs.append(f"{name}.{iname}: 모듈 {mn} 에 파라미터 '{pm.group(1)}' 없음")
        # 식별자
        text = re.sub(r"\.(\w+)\s*\(", "(", body)                  # .port( 제거
        text = re.sub(r"\$\w+", " ", text)                        # 시스템 함수
        text = re.sub(r"(?<=\w)(\.\w+)+", " ", text)              # 계층 참조 dut.u_game.st
        text = re.sub(r"\d+'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+", " ", text)   # 크기 있는 숫자
        text = re.sub(r"'[bBoOdDhH][0-9a-fA-F_xXzZ]+", " ", text)
        for idm in re.finditer(r"\b([A-Za-z_]\w*)\b", text):
            w = idm.group(1)
            if w in KEYWORDS or w in decl or w in mod_names or w in inst_names:
                continue
            if re.fullmatch(r"\d\w*", w):
                continue
            errs.append(f"{name}: 선언 안 된 이름 '{w}'")
        # 선언 전 사용 (wire/reg). 숫자 리터럴·.포트(·function/task 안은 빼고 봄
        clean = re.sub(r"\b(function|task)\b.*?\bend(function|task)\b", lambda m: " " * len(m.group(0)), body, flags=re.S)
        clean = re.sub(r"\d*'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+", lambda m: " " * len(m.group(0)), clean)
        clean = re.sub(r"\.\w+\s*\(", lambda m: " " * (len(m.group(0)) - 1) + "(", clean)
        for dm in re.finditer(r"\b(wire|reg)\b[^;]*?\b([A-Za-z_]\w*)\s*(=|;|,|\[)", clean):
            n = dm.group(2)
            if n in ("signed",):
                continue
            first_use = re.search(r"\b" + re.escape(n) + r"\b", clean)
            if first_use and first_use.start() < dm.start(2):
                errs.append(f"{name}: '{n}' 를 선언 전에 사용")

    # 중복 제거
    seen = set()
    errs = [e for e in errs if not (e in seen or seen.add(e))]
    for w in warns:
        print("경고:", w)
    for e in errs:
        print("오류:", e)
    print(f"모듈 {len(mods)}개 검사, 오류 {len(errs)}개, 경고 {len(warns)}개")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
