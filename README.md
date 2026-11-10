# Fortress FPGA

논리회로 설계 및 실험 텀프로젝트 (4조) — 포트리스(서보 포탑 2인 대전) FPGA 구현.

- 게임 규칙·수치: [docs/design_spec.md](docs/design_spec.md) (시뮬레이터 + 제안서 기준)
- 회로 구조·FSM·보드 확인 항목: [docs/rtl_architecture.md](docs/rtl_architecture.md)

## 폴더 구조
| 폴더 | 내용 |
|---|---|
| `rtl/fortress_top.v` | 최상위 모듈 (보드 핀과 연결) |
| `rtl/common/` | reset_gen, tick_gen, lfsr, debounce, trigger(수업 모듈) |
| `rtl/input/` | keypad_ctrl |
| `rtl/core/` | game_core(메인 FSM) + player_unit, wall_unit, event_unit, power_gauge, trajectory, collision, impact_calc, cpu_ai, fx_unit |
| `rtl/display/` | lcd_ctrl, lcd_driver, lcd_renderer, lcd_field, hud_span, cgram_slot, glyph/cannon/msg ROM |
| `rtl/output/` | seg8_ctrl, seg_font, scoreboard, led_gauge, rgb_ctrl, servo_ctrl, stepper_ctrl, piezo_ctrl, sfx_rom |
| `rtl/include/` | params.vh (공통 상수), glyph_ids.vh, msg_ids.vh |
| `rom/` | ROM 초기화 파일 (`.mem`) — vel/muzzle/cannon/glyph/msg |
| `sim/` | 테스트벤치 (`tb_trajectory.v`, `tb_fortress_top.v`) |
| `constraints/` | 핀 제약 파일 `fortress.xdc` |
| `tools/` | ROM 생성기 `gen_roms.py`, 정적 검사 `check_rtl.py`, 간이 시뮬레이터 `minisim.py` + 회귀 테스트 `sim_tests.py` |

## Vivado 프로젝트 만들기
1. **Design Sources**: `rtl/` 아래 `.v` 전부 + `rtl/include/*.vh` 를 추가해요. (`.vh` 는 include 파일이라 Vivado가 이름으로 찾아요)
2. 같은 곳에 `rom/*.mem` 6개도 추가해요 (`$readmemh` 가 이름으로 읽어요).
3. **Constraints**: `constraints/fortress.xdc`
4. **Simulation Sources**: `sim/tb_trajectory.v`, `sim/tb_fortress_top.v`
5. Top은 `fortress_top`. 보드 클럭 스위치는 1 MHz.
6. 먼저 `tb_trajectory` 를 돌려서 `PASS: all 104 vectors match` 가 나오는지 확인하세요.

## ROM·헤더 다시 만들기
`tools/gen_roms.py` 가 시뮬레이터 수식으로 `rom/*.mem`, `rtl/include/glyph_ids.vh`, `msg_ids.vh`, `rtl/output/sfx_rom.v`, `sim/tb_trajectory.v` 를 만들어요.
메시지·효과음·그림을 바꿀 땐 이 파일을 고치고 다시 실행하세요.
```
python3 tools/gen_roms.py
python3 tools/check_rtl.py     # 포트 이름·선언·begin/end 짝 검사
```

## Vivado 없이 로직 돌려 보기
`tools/minisim.py`는 이 레포의 RTL만 읽는 작은 Verilog 시뮬레이터예요. 노트북에 Python만 있으면 돼요.
```
python3 tools/sim_tests.py units     # 모듈 단위 검사 (탄도, 서보, Piezo, 스텝모터, LCD, 키패드)
python3 tools/sim_tests.py game 3    # 무작위 플레이 3판 (포탄마다 기준 모델과 비교)
python3 tools/sim_tests.py cpu 2     # CPU 대전 2판
python3 tools/sim_tests.py           # 전부
```
RTL을 고친 뒤에는 이걸 한 번 돌려 보세요. 무엇을 검사하는지와 한계는 [docs/rtl_architecture.md](docs/rtl_architecture.md)의 "검증"에 있어요.
Vivado 시뮬레이션·합성을 대신하지는 못해요.

## 협업 규칙
1. 한 모듈은 한 사람이 담당하고, 담당자는 아래 표에 적어요.
2. Vivado 프로젝트 폴더는 올리지 않아요(`.gitignore` 처리). 소스(`rtl/`, `sim/`, `rom/`, `constraints/`)만 올려요.
3. 모듈을 올릴 때는 `sim/`에 테스트벤치도 같이 올려요.
4. 포트·단위(1/256 픽셀 등)를 바꾸면 `docs/`도 같이 고쳐요.
5. 올리기 전에 `python3 tools/check_rtl.py` 와 `python3 tools/sim_tests.py units` 를 한 번 돌려요.

## 담당 표
| 모듈 | 담당 | 상태 |
|---|---|---|
| trigger (입력 에지 검출) | | 완료 |
| keypad_ctrl / debounce | | minisim 검사 통과 (보드 확인 전) |
| trajectory (탄도) | | minisim 에서 정답 104개 일치 (Vivado 시뮬 전) |
| collision / impact_calc | | 무작위 플레이에서 기준 모델과 일치 (보드 확인 전) |
| game_core + player/wall/event/power/fx | | 무작위 플레이 통과 (보드 확인 전) |
| cpu_ai | | CPU 대전 통과 (보드 확인 전) |
| LCD (lcd_ctrl, lcd_driver, lcd_renderer ...) | | minisim 검사 통과 (보드 확인 전) |
| 7세그·LED·Full color LED | | 값 확인 (보드 확인 전) |
| 서보·스텝모터·Piezo | | 1 MHz 타이밍 확인 (보드 확인 전) |
