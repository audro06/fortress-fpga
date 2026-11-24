# RTL 구조 (모듈 = 객체)

회로를 "객체"처럼 나눴어요. 각 모듈은 자기 상태를 직접 갖고, 다른 모듈과는 정해진 포트(명령 펄스 / 상태 출력)로만 이야기해요.
그래서 모듈 하나만 떼어서 테스트벤치로 따로 시뮬레이션할 수 있어요.

```
fortress_top
├─ reset_gen, tick_gen(30 Hz 프레임 / 1 kHz), lfsr(16비트 난수)          rtl/common
├─ keypad_ctrl ── debounce x10, trigger x10 (수업 모듈)                    rtl/input
├─ game_core (메인 FSM, 지휘자)                                            rtl/core
│   ├─ player_unit #(PI=0)   P1: 체력·위치·각도·포탄·얼음·깜빡임·seen·last
│   ├─ player_unit #(PI=1)   P2
│   ├─ wall_unit             벽 블록 3개, 부서짐·떨어짐
│   ├─ event_unit            3턴 이벤트, 용암·바람·중력·유성 예고
│   ├─ power_gauge           파워 1~8 왕복
│   ├─ trajectory            탄도 (시뮬레이터와 비트 단위로 같음)
│   ├─ collision             충돌 판정 (조합회로)
│   ├─ impact_calc           피해·얼림 계산 (조합회로)
│   ├─ cpu_ai                CPU 조준 탐색(자기 trajectory+collision 보유) + 회피 위치
│   └─ fx_unit               폭발·흔들림·LED 번쩍임·알림 문구·불꽃놀이 타이머
├─ lcd_renderer (화면 합성, 조합회로)                                      rtl/display
│   ├─ lcd_field x3          전장 바닥 레이어 (지금 칸 / 폭발 칸 / 포탄 칸)
│   ├─ hud_span x3           윗줄 글자 묶음 ── msg_rom
│   ├─ cgram_slot x2         슬롯 그림 ── glyph_rom, cannon_rom
│   └─ glyph_rom             폭발 프레임
├─ lcd_ctrl ── lcd_driver    초기화 + 98바이트 반복 갱신, E/RS 타이밍
├─ scoreboard ── seg8_ctrl ── seg_font                                     rtl/output
├─ seg_font (1자리)
├─ led_gauge, rgb_ctrl, servo_ctrl, stepper_ctrl
└─ piezo_ctrl ── sfx_rom (자동 생성)
```

## 메인 FSM (game_core)

| 상태 | 하는 일 | 다음 |
|---|---|---|
| TITLE | 포신 흔들기, 5 누르면 설정 화면 | SETUP |
| SETUP | DIP 상태 표시 (LCD·7세그·LED). 스위치를 바꾸면 그 설명으로, 아니면 45틱마다 다음 설명. 4/6으로 넘김, 5 누르면 시작 | START |
| START | DIP 읽기, 객체 초기화, 벽 배치 난수 | NEXT |
| NEXT | 차례 바꾸기, 턴 수, 이벤트 턴 처리 (클럭 단위 7단계) | INTRO 또는 METEOR |
| INTRO | 이름 표시 45틱. 이벤트 턴이면 룰렛 → 적용 | AIM 또는 MOVE(첫 턴) |
| AIM | 2/8 각도(길게 누르면 반복), 1/3/7/9 포탄, 5 누르면 충전. CPU는 계획대로 각도 돌림 | CHARGE |
| CHARGE | 파워 왕복, 5 떼면 발사 (CPU는 목표 파워에서) | FLIGHT |
| FLIGHT | 틱마다 탄도 한 걸음 → 충돌 검사 → 탄착 처리 2단계 | IMPACT |
| IMPACT | 폭발 애니메이션 기다림, 두 발이면 둘째 탄 | FLIGHT 또는 RESULT |
| RESULT | 결과 문구, 체력 표시가 다 내려갈 때까지 | MOVE / NEXT / OVER |
| MOVE | 4/6 이동, 5로 끝 (얼음이면 60틱 못 움직임). CPU는 회피 위치로 | NEXT |
| METEOR | 예고 칸에 유성 3개 낙하 | INTRO 또는 OVER |
| OVER | 승자 표시, LCD 깜빡임, 불꽃놀이, 40틱 뒤 5로 설정 화면 | SETUP |

- `#`은 언제든 TITLE로 돌아가요.
- 키 입력은 펄스를 모아 뒀다가(pend) 프레임 틱이 아닌 클럭에 한 개씩 처리해요. 상태와 맞지 않는 키는 버려요 (시뮬레이터 onKey와 같음).
- 명령은 1클럭 펄스(`c_*`)로 객체에 보내요. 피해 → 회복처럼 순서가 중요한 건 클럭을 나눠서 보내요.

## 클럭과 타이밍
- 모든 모듈이 `clk` 하나(기본 1 MHz)를 쓰고, 느린 동작은 `tick_frame`(30 Hz), `tick_ms`(1 kHz) enable로 맞춰요.
- CPU 탐색: 408가지 x 최대 600걸음 x 2클럭. 보통 수십 ms라 조준 연출(10틱) 전에 끝나요.
- LCD 한 바퀴: 99바이트 x 약 105 us = 약 10 ms.
- 명령 펄스는 보낸 다음 클럭에 객체가 받고, 그 결과는 그다음 클럭부터 보여요. 그래서 "명령 → 결과 읽기" 사이에는 한 클럭을 쉬어요 (NEXT 단계, 탄착 2단계가 그 예).

## 보드에서 확인할 것 (파라미터로 빼 둠)
| 항목 | 기본값 | 바꾸는 곳 |
|---|---|---|
| 보드 클럭 | 1 MHz, 핀 B6 | `fortress_top #(CLK_HZ)`, `constraints/fortress.xdc` |
| 버튼 눌림 극성 | 눌림 = 1 | `KEY_ACTIVE_LOW` |
| DIP 극성 | ON = 1 | `DIP_ACTIVE_LOW` |
| 7세그 자리 순서 | S0 = 맨 왼쪽 | `seg8_ctrl #(REVERSE)` |
| 버튼 방식 | Button Switch (핀 하나씩) | 보드 전환 스위치가 있으면 Button 쪽 |
| LCD 글자 쓰기 대기 | 100 us | `lcd_ctrl #(EXEC_US)` (글자가 빠지면 늘리기) |
| 서보 펄스 폭 | 0.7 ms ~ 2.3 ms | `SERVO_MIN_US`, `SERVO_MAX_US` |
| 서보 좌우 | 뒤집음 (P1 = 180-각도, P2 = 각도) | `SERVO_MIRROR` |
| 스텝모터 1바퀴 스텝 | 200 | `STEPS_PER_REV` |
| 원점 센서 감지 값 | 1 | `STEP_HOME_LEVEL` |

## 파일 생성
- `tools/gen_roms.py`: 시뮬레이터 수식으로 `rom/*.mem`, `rtl/include/glyph_ids.vh`, `msg_ids.vh`, `rtl/output/sfx_rom.v`, `sim/tb_trajectory.v` 생성
- `tools/check_rtl.py`: 포트 이름·선언·begin/end 짝·예약어 정적 검사 (Vivado 합성을 대신하진 못해요)

## 검증 (Vivado 없이 돌린 것)
`tools/minisim.py`는 이 레포의 RTL만 읽을 수 있는 작은 Verilog 시뮬레이터예요(클럭 하나, 0/1만, 비트 폭·부호 규칙은 표준대로).
`tools/sim_tests.py`가 이걸로 아래를 검사해요.

| 검사 | 내용 |
|---|---|
| trajectory | 시뮬레이터 수식으로 만든 정답 104개와 비교 |
| servo / piezo / stepper | 1 MHz에서 펄스 폭(0.7~2.3 ms, 주기 20 ms), 음 주파수와 길이, 원점 찾기·룰렛 목표 칸 |
| lcd_ctrl | 초기화 명령 6개와 간격, 갱신 99바이트 내용, 흔들림·ON/OFF 명령 |
| keypad | 채터링 걸러내기, 키 10개 매핑 |
| setup | 설정 화면 LCD·7세그·LED 표시, 스위치 바꾸면 그 설명으로, 자동 넘김, 4·6, `#` 취소, 시작할 때 DIP 반영·게임 중 고정 |
| reset | 아무 상태에서 `#` → 타이틀 → 깨끗한 새 판 |
| game / cpu | 무작위로 키를 눌러 여러 판을 끝까지 진행. 포탄 한 발마다 탄착·피해·얼음·벽 파손을 기준 모델(`simlib.ref_shot`, 웹 시뮬레이터 수식)과 비교하고, 위치·각도·체력 범위, 용암, 이벤트 주기·내용, 승자 판정을 매 클럭 확인. 일부 판은 레지스터 초기값을 아무 값으로 넣어서 리셋 누락도 봄 |

한계: 합성·타이밍·핀 문제, X 전파, Vivado 문법 차이는 못 잡아요. 보드에 올리기 전에 Vivado에서 `tb_trajectory`, `tb_fortress_top` 시뮬레이션과 합성을 꼭 해 보세요.
