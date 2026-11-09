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
| TITLE | 포신 흔들기, 5 누르면 시작 | START |
| START | DIP 읽기, 객체 초기화, 벽 배치 난수 | NEXT |
| NEXT | 차례 바꾸기, 턴 수, 이벤트 턴 처리 (클럭 단위 6단계) | INTRO 또는 METEOR |
| INTRO | 이름 표시 45틱. 이벤트 턴이면 룰렛 → 적용 | AIM 또는 MOVE(첫 턴) |
| AIM | 2/8 각도(길게 누르면 반복), 1/3/7/9 포탄, 5 누르면 충전. CPU는 계획대로 각도 돌림 | CHARGE |
| CHARGE | 파워 왕복, 5 떼면 발사 (CPU는 목표 파워에서) | FLIGHT |
| FLIGHT | 틱마다 탄도 한 걸음 → 충돌 검사 → 탄착 처리 2단계 | IMPACT |
| IMPACT | 폭발 애니메이션 기다림, 두 발이면 둘째 탄 | FLIGHT 또는 RESULT |
| RESULT | 결과 문구, 체력 표시가 다 내려갈 때까지 | MOVE / NEXT / OVER |
| MOVE | 4/6 이동, 5로 끝 (얼음이면 60틱 못 움직임). CPU는 회피 위치로 | NEXT |
| METEOR | 예고 칸에 유성 3개 낙하 | INTRO 또는 OVER |
| OVER | 승자 표시, LCD 깜빡임, 불꽃놀이, 40틱 뒤 5로 재시작 | START |

- `#`은 언제든 TITLE로 돌아가요.
- 키 입력은 펄스를 모아 뒀다가(pend) 프레임 틱이 아닌 클럭에 한 개씩 처리해요. 상태와 맞지 않는 키는 버려요 (시뮬레이터 onKey와 같음).
- 명령은 1클럭 펄스(`c_*`)로 객체에 보내요. 피해 → 회복처럼 순서가 중요한 건 클럭을 나눠서 보내요.

## 클럭과 타이밍
- 모든 모듈이 `clk` 하나(기본 1 MHz)를 쓰고, 느린 동작은 `tick_frame`(30 Hz), `tick_ms`(1 kHz) enable로 맞춰요.
- CPU 탐색: 408가지 x 최대 600걸음 x 2클럭. 보통 수십 ms라 조준 연출(10틱) 전에 끝나요.
- LCD 한 바퀴: 98바이트 x 약 52 us = 약 5 ms.

## 보드에서 확인할 것 (파라미터로 빼 둠)
| 항목 | 기본값 | 바꾸는 곳 |
|---|---|---|
| 보드 클럭 | 1 MHz, 핀 B6 | `fortress_top #(CLK_HZ)`, `constraints/fortress.xdc` |
| 버튼 눌림 극성 | 눌림 = 1 | `KEY_ACTIVE_LOW` |
| DIP 극성 | ON = 1 | `DIP_ACTIVE_LOW` |
| 7세그 자리 순서 | S0 = 맨 왼쪽 | `seg8_ctrl #(REVERSE)` |
| 서보 펄스 폭 | 0.7 ms ~ 2.3 ms | `SERVO_MIN_US`, `SERVO_MAX_US` |
| 스텝모터 1바퀴 스텝 | 200 | `STEPS_PER_REV` |
| 원점 센서 감지 값 | 1 | `STEP_HOME_LEVEL` |

## 파일 생성
- `tools/gen_roms.py`: 시뮬레이터 수식으로 `rom/*.mem`, `rtl/include/glyph_ids.vh`, `msg_ids.vh`, `rtl/output/sfx_rom.v`, `sim/tb_trajectory.v` 생성
- `tools/check_rtl.py`: 포트 이름·선언·begin/end 짝 정적 검사 (Vivado 합성을 대신하진 못해요)
