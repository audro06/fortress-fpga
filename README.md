# Fortress FPGA

논리회로 설계 및 실험 텀프로젝트 — 포트리스(서보 포탑 2인 대전) FPGA 구현.

## 폴더 구조
| 폴더 | 내용 |
|---|---|
| `rtl/` | Verilog 설계 소스 (trigger.v, 이후 trajectory.v 등) |
| `sim/` | 테스트벤치 (`tb_모듈명.v`) |
| `rom/` | ROM 초기화 파일 (`.mem`) — vel/muzzle/cannon/glyph/msg |
| `constraints/` | 핀 제약 파일 (`.xdc`) |
| `docs/` | 설계 사양서 |

설계 사양은 [docs/design_spec.md](docs/design_spec.md) 참고.

## 협업 규칙
1. `main`에는 직접 push하지 않고, 기능마다 브랜치(`feature/모듈명`)를 만들어 Pull Request로 합쳐요.
2. 한 모듈은 한 사람이 담당하고, 담당자는 아래 표에 적어요.
3. Vivado 프로젝트 폴더는 올리지 않아요(`.gitignore` 처리). 소스(`rtl/`, `sim/`, `constraints/`)만 올려요.
4. 모듈을 올릴 때는 `sim/`에 테스트벤치도 같이 올려요.
5. 포트·단위(1/256 픽셀 등)를 바꾸면 `docs/design_spec.md`도 같이 고쳐요.

## 담당 표
| 모듈 | 담당 | 상태 |
|---|---|---|
| trigger (입력 에지 검출) | | 완료 |
| trajectory (탄도) | | |
| LCD 제어 | | |
| 게임 FSM (턴·이동·숨김) | | |
| 7세그·서보·LED·Piezo | | |
