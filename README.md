# 포트리스 (Fortress FPGA)

논리회로 설계 및 실험 텀프로젝트 4조 (김도영, 길명근)

FPGA 보드(Combo II-DLD, Spartan-7)에서 돌아가는 **2인 턴제 포격 게임**이에요.
두 플레이어가 번갈아 포신 각도와 파워를 정해서 포탄을 쏘고, 상대 체력을 먼저 0으로 만들면 이겨요.
Text LCD에 전장이 그려지고, 서보모터가 지금 포신 각도를 실제로 가리키고, 스텝모터는 3턴마다 이벤트 룰렛을 돌려요.

> 처음이면 아래 [빠른 시작](#빠른-시작) 다섯 단계만 따라 하면 보드에 올릴 수 있어요.
> 막히면 [문제가 생겼을 때](#문제가-생겼을-때)를 먼저 보세요.

## 목차
- [빠른 시작](#빠른-시작)
- [게임 방법](#게임-방법)
- [Vivado에서 자세히](#vivado에서-자세히)
- [보드에 맞게 값 바꾸기](#보드에-맞게-값-바꾸기)
- [문제가 생겼을 때](#문제가-생겼을-때)
- [코드 구조](#코드-구조)
- [Vivado 없이 로직 확인하기](#vivado-없이-로직-확인하기)
- [협업 규칙](#협업-규칙)

---

## 빠른 시작

준비물: Vivado (수업 때 쓰는 버전), Git, 레포 접근 권한 (private 레포라 collaborator 초대가 필요해요)

**1. 코드 받기**
```
git clone https://github.com/audro06/fortress-fpga.git
```
이미 받았으면 그 폴더에서 `git pull` 만 하면 최신 코드가 돼요.
Git이 낯설면 GitHub 레포 페이지에서 **Code > Download ZIP** 으로 받아 압축을 풀어도 돼요.

**2. Vivado 프로젝트 만들기 (자동)**
Vivado를 켜고, 첫 화면 아래쪽 **Tcl Console** 에 두 줄을 입력해요. 경로는 레포를 받은 폴더로 바꾸고, 구분 기호는 `\` 대신 `/` 를 써요.
```
cd C:/Users/내이름/fortress-fpga
source scripts/create_project.tcl
```
레포 안에 `vivado/` 폴더가 생기고, 소스·헤더·ROM 파일·핀 제약·테스트벤치가 전부 들어간 프로젝트가 열려요.
(손으로 만들고 싶으면 [Vivado에서 자세히](#vivado에서-자세히)를 보세요.)

**3. 탄도 회로 시뮬레이션으로 확인**
왼쪽 **Flow Navigator > SIMULATION > Run Simulation > Run Behavioral Simulation**.
Tcl Console 에 아래 줄이 나오면 정상이에요.
```
PASS: all 104 vectors match
```

**4. 비트스트림 만들기**
**Flow Navigator > PROGRAM AND DEBUG > Generate Bitstream** (합성·배치가 자동으로 같이 돌아요, 몇 분 걸려요).

**5. 보드에 올리기**
보드 클럭 스위치를 **1 MHz** 로 두고, JTAG 케이블을 연결하고 전원을 켠 뒤
**Open Hardware Manager > Open Target > Auto Connect > Program Device**.
LCD에 `FORTRESS` 타이틀이 뜨면 성공이에요. 키패드 **5** 를 누르면 설정 화면이 나오고, DIP 스위치로 설정한 뒤 **5** 를 한 번 더 누르면 게임이 시작돼요.

---

## 게임 방법

### 한 턴의 흐름
1. **첫 턴**: 두 플레이어 모두 쏘지 않고 위치만 정해요 (P1 → P2). 4·6으로 움직이고 5로 끝내요.
2. **조준**: 2·8로 각도(30~90°)를 맞추면 서보모터가 따라 움직여요. 1·3·7·9로 포탄을 골라요.
3. **충전과 발사**: 5를 **누르고 있으면** 파워가 1~8 사이를 왕복하고 (LED 게이지, 음 높이), **떼는 순간** 발사돼요.
4. **결과**: 맞으면 체력이 깎이고 LCD가 흔들려요.
5. **회피 이동**: 상대의 다음 포격을 피하도록 4·6으로 이동하고 5로 턴을 넘겨요.

내 차례에는 **상대 탱크가 안 보이고** 마지막으로 본 자리에 `?` 만 떠요. 누군가 발사하는 순간 서로 위치가 드러나요.

### 키패드
| 키 | 하는 일 | 키 | 하는 일 | 키 | 하는 일 |
|:-:|---|:-:|---|:-:|---|
| 1 | 두 발 포탄 | 2 | 각도 올리기 (길게 누르면 반복) | 3 | 넓은 폭탄 |
| 4 | 왼쪽 이동 (설정 화면: 이전 설명) | 5 | 설정 화면 / 시작 / 충전·발사 / 이동 끝 | 6 | 오른쪽 이동 (설정 화면: 다음 설명) |
| 7 | 얼음 포탄 | 8 | 각도 내리기 (길게 누르면 반복) | 9 | 불 포탄 |
| * | (안 씀) | 0 | (안 씀) | # | 처음 화면으로 |

같은 포탄 키를 한 번 더 누르면 일반 포탄으로 돌아가요.

### 포탄
| 번호 | 포탄 | 피해 (직격 / 근접 / 스침) | 특징 |
|:-:|---|---|---|
| 0 | 일반 | 35 / 20 / 10 | |
| 1 | 두 발 | 20 / 12 / 6 | 두 발 연속, 둘째 발은 파워 ±1 |
| 2 | 넓은 폭탄 | 22 / 16 / 8 | 피해 범위가 넓음 |
| 3 | 얼음 | 피해 없음 | 맞은 탱크는 다음 이동 차례에 못 움직임 |
| 4 | 불 | 30 / 15 / 0 | 맞히면 내 체력 +15, 빗나가면 -15 |

### 설정 화면과 DIP 스위치
타이틀(또는 게임 끝 화면)에서 **5** 를 누르면 설정 화면이 나와요. DIP 스위치를 바꾸는 대로 화면이 바로 따라와서 외울 필요가 없어요.

```
SETUP   1--45-78     <- 윗줄: 켜진 스위치는 번호, 꺼진 건 '-'. 설명 중인 스위치가 깜빡여요
3 CPU HARD    ON     <- 아랫줄: 스위치 하나의 이름과 ON/OFF
```
- 스위치를 바꾸면 아랫줄이 그 스위치 설명으로 바로 바뀌어요. 가만히 두면 1.5초마다 1→8번을 차례로 보여 줘요. 4·6으로 직접 넘겨 볼 수도 있어요.
- 8자리 7세그와 LED 8개도 DIP 상태를 그대로 보여 줘요 (예: 7세그 `1--45-78`, LED i = DIP i).
- **5** 를 누르는 순간의 DIP 값으로 게임이 시작되고, 그 판 동안은 바꿔도 반영되지 않아요 (DIP7만 언제든 바로 반영). `#` 을 누르면 타이틀로 돌아가요.

| DIP | 켜면 | DIP | 켜면 |
|:-:|---|:-:|---|
| 1 | 특수 포탄 사용 (끄면 일반만) | 5 | 발사 후 이동 (끄면 이동 없음) |
| 2 | P2를 CPU로 | 6 | 체력 100 (끄면 50) |
| 3 | CPU 고수 모드 | 7 | 효과음 (언제든 바로 반영) |
| 4 | 3턴마다 이벤트 | 8 | 가운데 벽 |

추천 설정: 2인 대전은 **1·4·5·7·8 ON**, CPU 대전은 여기에 **2 ON**.

### 3턴마다 이벤트 (DIP4)
스텝모터 룰렛이 돌아서 하나를 고르고, 2턴 동안 유지돼요.

| 7세그 | 이벤트 | 효과 |
|:-:|---|---|
| E1 | LAVA | 양쪽 진영에 용암 칸이 생겨 그 칸으로 못 감 |
| E2 | LOW-G | 중력이 약해짐 (포탄이 멀리 감) |
| E3 | GUST | 바람이 붊 (LCD 윗줄에 방향·세기) |
| E4 | QUAKE | 탱크가 한 칸씩 밀리고 벽이 한 단계 부서짐 |
| E5 | FOG | 날아가는 포탄이 안 보임 |
| E6 | METEOR | `!` 로 표시한 3칸에 이벤트가 끝날 때 유성이 떨어짐 |

### 화면 읽는 법
- **LCD 아랫줄**: 땅. 탱크(몸통+포신 2칸), 가운데 벽, 용암, `?` 숨은 상대, `.` 지난 탄착
- **LCD 윗줄**: 지금 차례의 정보. 포탄 이름, 각도·파워(`52° P4`), 바람, 결과 문구 (`HIT!`, `MISS` ...)
- **8자리 7세그**: `P1 체력 │ 다음 이벤트까지 남은 턴 (또는 E1~E6) │ P2 체력`
- **1자리 7세그**: 고른 포탄 번호 (0~4)
- **LED 8개**: 파워 게이지
- **Full color LED**: 차례 색 (P1 빨강, P2 파랑), 발사·피격 때 번쩍임

---

## Vivado에서 자세히

### 프로젝트를 손으로 만들 때
스크립트 대신 직접 만들려면 이 순서로 해요. (스크립트가 하는 일과 같아요)

1. **File > Project > New** → RTL Project → "Do not specify sources at this time" 체크
2. Part 선택: **Family Spartan-7, 칩 `xc7s75fgga484-1`** (수업 2주차 자료와 같음)
3. **Add Sources > Add or create design sources > Add Files**:
   - `rtl/` 아래 `.v` 파일 전부 (하위 폴더 포함, 35개)
   - `rtl/include/` 의 `.vh` 3개
   - `rom/` 의 `.mem` 6개
   - "Copy sources into project" 는 **체크 해제** (레포 파일을 그대로 쓰게)
4. **Add Sources > Add or create constraints** → `constraints/fortress.xdc`
5. **Add Sources > Add or create simulation sources** → `sim/tb_trajectory.v`, `sim/tb_fortress_top.v`
6. **Settings > General > Verilog options > Include Dirs** 에 `rtl/include` 폴더 추가
   (안 하면 `` `include "params.vh" `` 를 못 찾는다는 에러가 나요)
7. Sources 창에서 `fortress_top` 오른쪽 클릭 → **Set as Top**
8. **Settings > Simulation > Simulation 탭 > xsim.simulate.runtime** 을 `all` 로 (기본 1000 ns 면 테스트가 중간에 멈춰요)

### 테스트벤치 두 개
| 테스트벤치 | 무엇을 보나 | 시간 |
|---|---|---|
| `tb_trajectory` | 탄도 회로가 웹 시뮬레이터 정답 104개와 같은지 | 몇 초 |
| `tb_fortress_top` | 게임 전체: 시작 → 이동 → 발사 → 결과. LCD 화면이 바뀔 때마다 글자로 찍어 줘요 | 수 분 (게임 몇 초 분량을 1 MHz로 돌림) |

시뮬레이션할 테스트벤치를 바꾸려면 Sources 창의 **Simulation Sources > sim_1** 에서 원하는 테스트벤치를 오른쪽 클릭 → **Set as Top**.
`tb_fortress_top` 결과 화면의 숫자 0~7은 직접 만든 문자(탱크, 포신, 벽 등) 자리, `#` 은 꽉 찬 블록(온전한 벽)이에요.

---

## 보드에 맞게 값 바꾸기

보드마다 달라질 수 있는 값은 전부 `rtl/fortress_top.v` 맨 위 `parameter` 에 모아 뒀어요. 숫자만 바꾸고 다시 Generate Bitstream 하면 돼요.

```verilog
module fortress_top #(
    parameter integer CLK_HZ          = 1_000_000,   // 보드 클럭 (클럭 스위치와 맞춰야 함)
    parameter         KEY_ACTIVE_LOW  = 1'b0,        // 버튼을 눌렀을 때 0이 들어오는 보드면 1
    parameter         DIP_ACTIVE_LOW  = 1'b0,        // DIP ON 이 0인 보드면 1
    parameter integer STEPS_PER_REV   = 200,         // 스텝모터 한 바퀴 스텝 수
    parameter         STEP_HOME_LEVEL = 1'b1,        // 원점 센서가 감지됐을 때 값
    parameter integer SERVO_MIN_US    = 700,         // 서보 0° 펄스 폭 (us)
    parameter integer SERVO_MAX_US    = 2300         // 서보 180° 펄스 폭 (us)
)
```

이 밖에 두 가지는 다른 파일에 있어요.
- LCD 글자 쓰기 대기 시간: `rtl/display/lcd_ctrl.v` 의 `EXEC_US` (기본 100 us)
- 8자리 7세그 자리 순서: `rtl/output/seg8_ctrl.v` 의 `REVERSE` (기본 0 = S0이 맨 왼쪽)

핀 번호는 `constraints/fortress.xdc` 에 있어요 (`LCDL/Xilinx_S7_Pin_Map.xlsx` 기준).

**룰렛 원판 만들기**: 원점 센서 자리부터 모터가 도는 방향으로 60°마다 LAVA, LOW-G, GUST, QUAKE, FOG, METEOR 순서로 붙여요.

---

## 문제가 생겼을 때

### Vivado 에러
| 증상 | 원인과 해결 |
|---|---|
| `cannot open include file 'params.vh'` | include 경로가 없어요. 스크립트로 다시 만들거나 [6번](#프로젝트를-손으로-만들-때)처럼 Include Dirs 에 `rtl/include` 추가 |
| `module 'xxx' not found` | 그 모듈 파일이 프로젝트에 빠졌어요. `rtl/` 하위 폴더 파일까지 다 추가했는지 확인 |
| `$readmemh` 관련 경고 / 시뮬레이션에서 LCD 그림이나 탄도가 이상함 | `rom/*.mem` 6개가 프로젝트에 안 들어갔어요. Design Sources 에 추가 |
| 시뮬레이션이 1000 ns 에서 멈춤 | `xsim.simulate.runtime` 을 `all` 로 |
| 에러가 났는데 원인을 모르겠음 | Tcl Console / Messages 창의 **빨간 줄 전체**를 복사해서 공유해 주세요 |

### 보드에서
| 증상 | 확인할 것 |
|---|---|
| 아무것도 반응이 없음 | 클럭 스위치가 1 MHz 인지, xdc의 클럭 핀(B6)이 수업 때 쓰던 핀과 같은지 |
| 게임이 너무 빠르거나 느림, 소리 음정이 이상함 | 클럭 스위치와 `CLK_HZ` 가 다름 |
| LCD에 아무것도 안 나오거나 검은 네모만 나옴 | 클럭 확인, LCD 대비 조절 나사(가변저항)가 있으면 돌려 보기, 그래도 안 되면 `EXEC_US` 를 200 정도로 |
| LCD 글자가 군데군데 빠지거나 밀림 | `EXEC_US` 를 늘리기 |
| 안 눌렀는데 계속 눌린 것처럼 동작 (각도가 혼자 움직임 등) | `KEY_ACTIVE_LOW` 를 반대로 |
| 일부 버튼만 안 먹힘 | 핀맵에 KEY06~12가 키패드 행/열 겸용으로 적혀 있어요. 보드에 Button / Keypad 전환 스위치가 있으면 **Button** 쪽으로 |
| DIP 설정이 반대로 먹힘 | `DIP_ACTIVE_LOW` 를 반대로 |
| 7세그 자리 순서가 거꾸로 (체력이 반대편에) | `seg8_ctrl` 의 `REVERSE` 를 1로 |
| 서보 각도가 화면 각도와 다름 | `SERVO_MIN_US` / `SERVO_MAX_US` 를 조금씩 바꿔 맞추기 (7주차 실습처럼) |
| 스텝모터가 안 돌고 떨기만 함 | `rtl/output/stepper_ctrl.v` 의 `FAST_MS` 를 키워서 천천히 돌리기 |
| 룰렛이 엉뚱한 칸에서 멈춤 | `STEPS_PER_REV` 를 실제 모터 값으로, 원판을 붙인 방향 확인 |
| 룰렛이 시작할 때 한참 돌다 멈춤 | 원점 센서를 못 찾는 중이에요. `STEP_HOME_LEVEL` 을 반대로 |
| 소리가 안 남 | DIP 7 ON 확인 |

값을 바꾼 뒤에는 Generate Bitstream 을 다시 하고 Program Device 하면 돼요.

---

## 코드 구조

회로를 역할별 모듈로 나눴어요. 각 모듈은 자기 상태를 직접 갖고, 다른 모듈과는 포트로만 이야기해서 하나씩 떼어 시뮬레이션할 수 있어요.

```
fortress_top                 보드 핀 연결 (최상위)
├─ 공통      reset_gen, tick_gen(30 Hz 게임 틱 / 1 kHz), lfsr(난수), debounce, trigger(수업 모듈)
├─ 입력      keypad_ctrl
├─ 게임      game_core(메인 FSM)
│            ├─ player_unit ×2   체력·위치·각도·포탄
│            ├─ wall_unit        가운데 벽
│            ├─ event_unit       3턴 이벤트
│            ├─ power_gauge      파워 왕복
│            ├─ trajectory       탄도 (웹 시뮬레이터와 비트 단위로 같음)
│            ├─ collision        충돌 판정
│            ├─ impact_calc      피해 계산
│            ├─ cpu_ai           CPU 조준·회피
│            └─ fx_unit          폭발·흔들림·불꽃놀이
├─ LCD       lcd_ctrl + lcd_driver (LCD 신호), lcd_renderer (화면 합성)
└─ 출력      7세그, LED, Full color LED, 서보, 스텝모터, Piezo
```

### 코드를 처음 읽는다면 이 순서로
1. `rtl/include/params.vh`: 게임에 쓰는 숫자(체력, 피해, 상태 번호)가 다 모여 있어요
2. `rtl/fortress_top.v`: 모듈들이 어떻게 연결되는지
3. `rtl/core/game_core.v`: 메인 FSM. `case (st)` 부분이 게임 진행이에요
4. 관심 있는 장치 모듈 (`rtl/output/servo_ctrl.v` 처럼 수업 실습과 비슷한 것부터)

### 폴더
| 폴더 | 내용 |
|---|---|
| `rtl/` | Verilog 소스 (위 구조) |
| `rtl/include/` | 공통 상수 `params.vh`, 자동 생성 번호표 `glyph_ids.vh`, `msg_ids.vh` |
| `rom/` | ROM 초기화 파일 `.mem` (속도, 포구, 포신 그림, 문자 그림, 메시지) |
| `sim/` | Vivado 테스트벤치 |
| `constraints/` | 핀 제약 `fortress.xdc` |
| `scripts/` | Vivado 프로젝트 생성 `create_project.tcl` |
| `tools/` | ROM 생성기, 정적 검사, 간이 시뮬레이터 (Python) |
| `docs/` | [게임 사양](docs/design_spec.md), [회로 구조·FSM·검증](docs/rtl_architecture.md) |
| `vivado/` | 스크립트가 만드는 Vivado 프로젝트 (git에 안 올라가요) |

### 메시지·효과음·그림 바꾸기
`rom/*.mem`, `rtl/include/glyph_ids.vh`, `msg_ids.vh`, `rtl/output/sfx_rom.v`, `sim/tb_trajectory.v` 는 `tools/gen_roms.py` 가 만든 파일이에요. 손으로 고치지 말고 `gen_roms.py` 안의 표(`MSGS`, `SFX`, `GL`)를 고친 뒤 다시 만들어요.
```
python3 tools/gen_roms.py
```

---

## Vivado 없이 로직 확인하기

`tools/minisim.py` 는 이 레포의 Verilog만 읽어서 돌리는 작은 시뮬레이터예요. Python만 있으면 노트북 어디서든 돼요.
```
python3 tools/check_rtl.py           # 포트 이름·선언·begin/end 짝·예약어 검사 (1초)
python3 tools/sim_tests.py units     # 모듈 단위 검사: 탄도, 서보, Piezo, 스텝모터, LCD, 키패드 (1~2분)
python3 tools/sim_tests.py game 3    # 키를 무작위로 눌러 3판 끝까지 (포탄마다 웹 시뮬레이터 수식과 비교)
python3 tools/sim_tests.py cpu 2     # CPU 대전 2판
python3 tools/sim_tests.py           # 전부
```
마지막 줄에 `결과: 모두 통과` 가 나오면 돼요. 실패하면 `FAIL:` 줄에 무엇이 달랐는지 나와요.
합성 문제나 Vivado 문법 차이는 못 잡으니, 보드에 올리기 전에는 Vivado 시뮬레이션·합성을 꼭 해 보세요.

---

## 협업 규칙
1. `main` 에 바로 push 해요. push 전에 `git pull` 로 최신 코드를 먼저 받아요.
2. push 전에 `python3 tools/check_rtl.py` 와 `python3 tools/sim_tests.py units` 를 한 번 돌려요.
3. `vivado/` 같은 Vivado 생성물은 올리지 않아요 (`.gitignore` 처리돼 있어요).
4. 포트나 단위(1/256 픽셀 등)를 바꾸면 `docs/` 도 같이 고쳐요.
5. 보드에서 맞춘 값(극성, 서보 펄스 폭 등)은 커밋 메시지에 "보드 확인" 이라고 남겨요.

### 담당과 상태
| 모듈 | 담당 | 상태 |
|---|---|---|
| keypad_ctrl / debounce / trigger | | 간이 시뮬 통과, 보드 확인 전 |
| trajectory / collision / impact_calc | | 정답 104개·무작위 플레이 일치, Vivado 시뮬 전 |
| game_core + player / wall / event / power / fx | | 무작위 플레이 통과, 보드 확인 전 |
| cpu_ai | | CPU 대전 통과, 보드 확인 전 |
| LCD (lcd_ctrl, lcd_driver, lcd_renderer ...) | | 간이 시뮬 통과, 보드 확인 전 |
| 7세그 · LED · Full color LED | | 값 확인, 보드 확인 전 |
| 서보 · 스텝모터 · Piezo | | 1 MHz 타이밍 확인, 보드 확인 전 |
