// =====================================================================
// 포트리스 공통 파라미터
//   - 탄도·맵·포탄 값은 웹 시뮬레이터(11-03 설계사양)와 같아요.
//   - 파워 단계와 체력은 제안서(11-10) 기준이에요: 파워 1~8, 체력 50 (DIP6 ON이면 100)
//   - 각 모듈 안에서 `include "params.vh" 로 불러 써요. (모듈 밖에 include하지 마세요)
// =====================================================================

// ---- 탄도 (1/256 픽셀 단위 정수)
localparam integer MIN_ANG    = 30;   // 최저 각도 (직사 방지)
localparam integer MAX_ANG    = 90;
localparam integer CPU_MAX_ANG = 80;  // CPU가 탐색하는 최대 각도
localparam integer POW_MAX    = 8;    // 파워 1~8 (제안서). 속도 ROM 파워 = 파워*2
localparam integer G_NORM     = 18;   // 중력
localparam integer G_LOW      = 11;   // 저중력 이벤트
localparam integer HIT_Y      = 11;   // 이 y 픽셀 이상이면 탱크 직격 판정
localparam integer SELF_SKIP  = 8;    // 발사 직후 자기 탱크를 판정에서 빼는 틱 수
localparam integer MAX_FLIGHT = 600;  // 최대 비행 틱
localparam integer METEOR_VH  = -90;  // 유성 시작 속도
localparam integer METEOR_H0  = 34*256;

// ---- 맵 (칸 번호 0~15, 한 칸 = 5픽셀)
localparam integer P1_MIN = 0,  P1_MAX = 5;
localparam integer P2_MIN = 10, P2_MAX = 15;
localparam integer WALL_C0 = 7, WALL_C1 = 8;

// ---- 체력 (제안서 기준)
localparam integer HP_BASE = 50;
localparam integer HP_LONG = 100;     // DIP6 ON

// ---- 포탄 종류 (3비트)
localparam [2:0] SH_NORMAL = 3'd0;
localparam [2:0] SH_DOUBLE = 3'd1;
localparam [2:0] SH_WIDE   = 3'd2;
localparam [2:0] SH_ICE    = 3'd3;
localparam [2:0] SH_FIRE   = 3'd4;
localparam [2:0] SH_METEOR = 3'd5;    // 내부용 (유성)

// ---- 피해 [직격, 근접, 스침], 범위 [근접, 스침] (픽셀)
localparam integer NORMAL_D0 = 35, NORMAL_D1 = 20, NORMAL_D2 = 10, NORMAL_R0 = 4, NORMAL_R1 = 8;
localparam integer DOUBLE_D0 = 20, DOUBLE_D1 = 12, DOUBLE_D2 = 6,  DOUBLE_R0 = 4, DOUBLE_R1 = 8;
localparam integer WIDE_D0   = 22, WIDE_D1   = 16, WIDE_D2   = 8,  WIDE_R0   = 7, WIDE_R1   = 13;
localparam integer FIRE_D0   = 30, FIRE_D1   = 15, FIRE_D2   = 0,  FIRE_R0   = 4, FIRE_R1   = 8;
localparam integer METEOR_D0 = 20, METEOR_D1 = 20, METEOR_D2 = 10, METEOR_R0 = 4, METEOR_R1 = 7;
localparam integer FIRE_HEAL = 15;    // 불 포탄 명중 시 자기 회복
localparam integer FIRE_BACK = 15;    // 불 포탄 실패 시 자기 피해

// ---- 이벤트
localparam integer EVENT_PERIOD = 3;  // 3턴마다
localparam integer EVENT_LEN    = 2;  // 2턴 유지
localparam [2:0] EV_LAVA   = 3'd0;
localparam [2:0] EV_LOWG   = 3'd1;
localparam [2:0] EV_GUST   = 3'd2;
localparam [2:0] EV_QUAKE  = 3'd3;
localparam [2:0] EV_FOG    = 3'd4;
localparam [2:0] EV_METEOR = 3'd5;

// ---- 메인 FSM 상태 (렌더러·주변장치도 이 값을 봐요)
localparam [3:0] ST_TITLE  = 4'd0;
localparam [3:0] ST_INTRO  = 4'd1;
localparam [3:0] ST_AIM    = 4'd2;
localparam [3:0] ST_CHARGE = 4'd3;
localparam [3:0] ST_FLIGHT = 4'd4;
localparam [3:0] ST_IMPACT = 4'd5;
localparam [3:0] ST_RESULT = 4'd6;
localparam [3:0] ST_MOVE   = 4'd7;
localparam [3:0] ST_METEOR = 4'd8;
localparam [3:0] ST_OVER   = 4'd9;
localparam [3:0] ST_START  = 4'd10;   // 내부: 새 게임 준비 (1~2클럭)
localparam [3:0] ST_NEXT   = 4'd11;   // 내부: 다음 턴 준비 (몇 클럭)
localparam [3:0] ST_SETUP  = 4'd12;   // 설정 화면: DIP 상태를 보여 주고, 5를 누르면 그때 DIP을 읽어 시작

// ---- CGRAM 슬롯 (게임 화면에서 용도 고정)
localparam [2:0] SLOT_P1     = 3'd0;
localparam [2:0] SLOT_P1C    = 3'd1;
localparam [2:0] SLOT_P2     = 3'd2;
localparam [2:0] SLOT_P2C    = 3'd3;
localparam [2:0] SLOT_CRACK  = 3'd4;  // 타이틀: 두 발 아이콘, 게임 끝: 트로피
localparam [2:0] SLOT_RUBBLE = 3'd5;  // 타이틀: 넓은 폭탄 아이콘
localparam [2:0] SLOT_LAVA   = 3'd6;  // 타이틀: 얼음 아이콘
localparam [2:0] SLOT_SPR    = 3'd7;  // 포탄 / 폭발 / 유성. 타이틀: 불 아이콘

// ---- LCD 내장 문자 코드 (HD44780 A00)
localparam [7:0] CH_SPACE = 8'h20;
localparam [7:0] CH_FULL  = 8'hFF;    // 벽 (온전)
localparam [7:0] CH_DOT   = 8'hA5;    // 포탄 궤적
localparam [7:0] CH_UP    = 8'h5E;    // ^ 화면 위로 나감
localparam [7:0] CH_MARK  = 8'h2E;    // . 지난 탄착
localparam [7:0] CH_HIDE  = 8'h3F;    // ? 숨은 상대
localparam [7:0] CH_WARN  = 8'h21;    // ! 유성 경고
localparam [7:0] CH_STAR  = 8'h2A;    // * 넓은 폭발
localparam [7:0] CH_PLUS  = 8'h2B;
localparam [7:0] CH_MINUS = 8'h2D;
localparam [7:0] CH_DEG   = 8'hDF;    // °
localparam [7:0] CH_SMALLO = 8'h6F;   // o (스프라이트 슬롯이 이미 쓰일 때의 포탄)
localparam [7:0] CH_GT    = 8'h3E;    // >
localparam [7:0] CH_LT    = 8'h3C;    // <
localparam [7:0] CH_P     = 8'h50;    // P

// ---- 논리 키 번호 (keypad_ctrl 출력 비트). 제안서 키 배치
//   1 두발   2 각도▲  3 넓은
//   4 ◀이동  5 발사   6 이동▶
//   7 얼음   8 각도▼  9 불
//   *  -     0  -     # 처음으로
localparam integer K_FIRE  = 0;   // 5 (누르는 동안 파워 충전, 떼면 발사)
localparam integer K_UP    = 1;   // 2
localparam integer K_DOWN  = 2;   // 8
localparam integer K_LEFT  = 3;   // 4
localparam integer K_RIGHT = 4;   // 6
localparam integer K_SH1   = 5;   // 1 두 발
localparam integer K_SH2   = 6;   // 3 넓은 폭탄
localparam integer K_SH3   = 7;   // 7 얼음
localparam integer K_SH4   = 8;   // 9 불
localparam integer K_RESET = 9;   // #
localparam integer NKEYS   = 10;

// ---- 효과음 번호 (sfx_rom.v)
localparam [4:0] SFX_NONE     = 5'd0;
localparam [4:0] SFX_TICK     = 5'd1;
localparam [4:0] SFX_ERR      = 5'd2;
localparam [4:0] SFX_MOVE     = 5'd3;
localparam [4:0] SFX_FIRE     = 5'd4;
localparam [4:0] SFX_BOOM     = 5'd5;
localparam [4:0] SFX_BOOM_BIG = 5'd6;
localparam [4:0] SFX_HIT      = 5'd7;
localparam [4:0] SFX_MISS     = 5'd8;
localparam [4:0] SFX_ARM      = 5'd9;
localparam [4:0] SFX_TURN     = 5'd10;
localparam [4:0] SFX_START    = 5'd11;
localparam [4:0] SFX_WIN      = 5'd12;
localparam [4:0] SFX_LOSE     = 5'd13;
localparam [4:0] SFX_OUT      = 5'd14;
localparam [4:0] SFX_FREEZE   = 5'd15;
localparam [4:0] SFX_BURN     = 5'd16;
localparam [4:0] SFX_HEAL     = 5'd17;   // 폭발음 + 회복음
localparam [4:0] SFX_ROUL     = 5'd18;
localparam [4:0] SFX_FANFARE  = 5'd19;
localparam [4:0] SFX_METEOR   = 5'd20;
localparam [4:0] SFX_SPARK    = 5'd21;
localparam [4:0] SFX_QUAKE    = 5'd22;

// ---- Full color LED 색 {R,G,B}
localparam [2:0] C_OFF = 3'b000, C_RED = 3'b100, C_GREEN = 3'b010, C_BLUE = 3'b001;
localparam [2:0] C_YELLOW = 3'b110, C_CYAN = 3'b011, C_MAGENTA = 3'b101, C_WHITE = 3'b111;
